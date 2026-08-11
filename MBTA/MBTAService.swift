import Foundation

/// Simple service that talks to the MBTA V3 API using URLSession.
final class MBTAService {
    static let shared = MBTAService()

    private let baseURL = URL(string: "https://api-v3.mbta.com")!
    private let apiKey = "6aaf4b37ca464bc298e7573999c87d4d"

    private init() {}

    /// Builds a full request URL like:
    /// https://api-v3.mbta.com/predictions?filter[stop]=64&sort=arrival_time&api_key=...
    private func buildURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems + [URLQueryItem(name: "api_key", value: apiKey)]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        return url
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil) async throws -> T {
        var didRecord = false
        let startTime = Date()

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let responseTime = Int(Date().timeIntervalSince(startTime) * 1000) // milliseconds
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            
            // Local logging
            APIUsageStore.record(url: url, statusCode: statusCode, source: "app")
            didRecord = true
            
            // Firebase monitoring (silent background logging)
            let endpoint = url.path.replacingOccurrences(of: "/", with: "")
            FirebaseMonitoring.shared.logAPICall(
                endpoint: endpoint,
                statusCode: statusCode,
                responseTimeMs: responseTime,
                routeName: routeName,
                directionName: directionName,
                stopName: stopName
            )

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            if !didRecord {
                APIUsageStore.record(url: url, statusCode: nil, source: "app")
                
                // Log error to Firebase
                let endpoint = url.path.replacingOccurrences(of: "/", with: "")
                FirebaseMonitoring.shared.logAPICall(endpoint: endpoint, statusCode: nil, routeName: routeName, directionName: directionName, stopName: stopName)
            }
            throw error
        }
    }

    /// Looks up one route by typed text and transport mode.
    func fetchRoute(matching query: String, mode: TransportMode) async throws -> Route {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try buildURL(
            path: "routes",
            queryItems: [URLQueryItem(name: "filter[type]", value: mode.routeTypeFilterValue)]
        )
        let response = try await fetch(RoutesResponse.self, from: url)
        let routes = response.data.map { route in
            Route(
                id: route.id,
                shortName: route.attributes.shortName,
                longName: route.attributes.longName,
                directionNames: route.attributes.directionNames,
                directionDestinations: route.attributes.directionDestinations
            )
        }

        if let exactMatch = routes.first(where: { route in
            routeMatches(route, query: trimmedQuery, exactOnly: true)
        }) {
            return exactMatch
        }

        if let partialMatch = routes.first(where: { route in
            routeMatches(route, query: trimmedQuery, exactOnly: false)
        }) {
            return partialMatch
        }

        throw URLError(.fileDoesNotExist)
    }

    /// Fetches all routes for a given transport mode.
    func fetchAllRoutes(mode: TransportMode) async throws -> [Route] {
        let url = try buildURL(
            path: "routes",
            queryItems: [URLQueryItem(name: "filter[type]", value: mode.routeTypeFilterValue)]
        )
        let response = try await fetch(RoutesResponse.self, from: url)
        return response.data.map { route in
            Route(
                id: route.id,
                shortName: route.attributes.shortName,
                longName: route.attributes.longName,
                directionNames: route.attributes.directionNames,
                directionDestinations: route.attributes.directionDestinations
            )
        }
    }

    /// Loads the stops for one route and one direction so the stop picker only shows relevant boarding stops.
    func fetchStops(routeId: String, directionId: Int) async throws -> [BusStop] {
        let url = try buildURL(
            path: "stops",
            queryItems: [
                URLQueryItem(name: "filter[route]", value: routeId),
                URLQueryItem(name: "filter[direction_id]", value: String(directionId))
            ]
        )
        let response = try await fetch(StopsResponse.self, from: url)

        return response.data
            .map {
                BusStop(
                    id: $0.id,
                    name: $0.attributes.name
                )
            }
    }

    /// Fetch predictions for a stop, optionally filtered by route and direction.
    /// For commuter rail, prefers departure times; for bus/subway, prefers arrival times.
    func fetchPredictions(stopId: String, routeId: String?, directionId: Int? = nil, mode: TransportMode = .bus, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil) async throws -> [BusArrival] {
        let isCommuterRail = mode == .commuterRail
        let sortField = isCommuterRail ? "departure_time" : "arrival_time"
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "filter[stop]", value: stopId),
            URLQueryItem(name: "sort", value: sortField)
        ]

        if let routeId, !routeId.isEmpty {
            queryItems.append(URLQueryItem(name: "filter[route]", value: routeId))
        }

        if let directionId {
            queryItems.append(URLQueryItem(name: "filter[direction_id]", value: String(directionId)))
        }

        let url = try buildURL(path: "predictions", queryItems: queryItems)
        let response = try await fetch(PredictionsResponse.self, from: url, routeName: routeName, directionName: directionName, stopName: stopName)
        let now = Date()
        let vehicleIDs = response.data.compactMap { $0.relationships?.vehicle?.data?.id }
        let vehiclesByID = try await fetchVehicles(ids: vehicleIDs)

        return response.data.compactMap { prediction in
            let attributes = prediction.attributes
            // Commuter rail: prefer departure (when the train leaves the station)
            // Bus/subway: prefer arrival (when the vehicle reaches the stop)
            let time = isCommuterRail
                ? (attributes.departureTime ?? attributes.arrivalTime)
                : (attributes.arrivalTime ?? attributes.departureTime)

            guard let time, time >= now else {
                return nil
            }

            let minutesAway = max(Int(time.timeIntervalSince(now) / 60), 0)
            let vehicleID = prediction.relationships?.vehicle?.data?.id
            let currentStopSequence = vehicleID.flatMap { vehiclesByID[$0] }
            let stopsAway = calculateStopsAway(
                targetStopSequence: attributes.stopSequence,
                currentStopSequence: currentStopSequence,
                minutesAway: minutesAway
            )

            return BusArrival(
                id: prediction.id,
                routeId: prediction.relationships?.route?.data?.id ?? routeId ?? "?",
                routeName: prediction.relationships?.route?.data?.id ?? routeId ?? "?",
                stopId: prediction.relationships?.stop?.data?.id ?? stopId,
                stopName: "",
                arrivalTime: attributes.arrivalTime,
                departureTime: attributes.departureTime,
                minutesAway: minutesAway,
                stopsAway: stopsAway,
                directionId: attributes.directionId,
                status: attributes.status
            )
        }
        .sorted { left, right in
            let leftTime = isCommuterRail
                ? (left.departureTime ?? left.arrivalTime ?? .distantFuture)
                : (left.arrivalTime ?? left.departureTime ?? .distantFuture)
            let rightTime = isCommuterRail
                ? (right.departureTime ?? right.arrivalTime ?? .distantFuture)
                : (right.arrivalTime ?? right.departureTime ?? .distantFuture)
            return leftTime < rightTime
        }
    }
    
    /// Fetch scheduled departures for a stop (used as fallback when predictions are empty).
    /// Returns remaining departures for the current day.
    func fetchSchedules(stopId: String, routeId: String, directionId: Int? = nil, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil) async throws -> [BusArrival] {
        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.startOfDay(for: now).addingTimeInterval(86400)
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "filter[stop]", value: stopId),
            URLQueryItem(name: "filter[route]", value: routeId),
            URLQueryItem(name: "filter[min_time]", value: timeString(from: now)),
            URLQueryItem(name: "filter[max_time]", value: timeString(from: endOfDay)),
            URLQueryItem(name: "sort", value: "departure_time")
        ]
        
        if let directionId {
            queryItems.append(URLQueryItem(name: "filter[direction_id]", value: String(directionId)))
        }
        
        let url = try buildURL(path: "schedules", queryItems: queryItems)
        let response = try await fetch(SchedulesResponse.self, from: url, routeName: routeName, directionName: directionName, stopName: stopName)
        
        return response.data.compactMap { schedule in
            let attributes = schedule.attributes
            let time = attributes.departureTime ?? attributes.arrivalTime
            
            guard let time, time >= now, time <= endOfDay else {
                return nil
            }
            
            let minutesAway = max(Int(time.timeIntervalSince(now) / 60), 0)
            
            return BusArrival(
                id: schedule.id,
                routeId: schedule.relationships?.route?.data?.id ?? routeId,
                routeName: schedule.relationships?.route?.data?.id ?? routeId,
                stopId: schedule.relationships?.stop?.data?.id ?? stopId,
                stopName: "",
                arrivalTime: attributes.arrivalTime,
                departureTime: attributes.departureTime,
                minutesAway: minutesAway,
                stopsAway: nil,
                directionId: attributes.directionId,
                status: nil,
                isScheduled: true
            )
        }
    }
    
    /// Fetch predictions + schedules for commuter rail and merge them.
    /// Live predictions replace matching scheduled entries; remaining schedules fill in the gaps.
    func fetchCommuterRailDepartures(stopId: String, routeId: String, directionId: Int? = nil, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil) async throws -> [BusArrival] {
        // Fetch both concurrently
        async let predictionsTask = fetchPredictions(
            stopId: stopId, routeId: routeId, directionId: directionId,
            mode: .commuterRail, routeName: routeName, directionName: directionName, stopName: stopName
        )
        async let schedulesTask = fetchSchedules(
            stopId: stopId, routeId: routeId, directionId: directionId,
            routeName: routeName, directionName: directionName, stopName: stopName
        )
        
        let predictions = (try? await predictionsTask) ?? []
        let schedules = (try? await schedulesTask) ?? []
        
        // If both are empty, nothing to show
        if predictions.isEmpty && schedules.isEmpty { return [] }
        
        // Start with all predictions (live data, isScheduled = false)
        var merged = predictions
        
        // Add schedules that don't overlap with any prediction (within 2 min tolerance)
        for schedule in schedules {
            let schedTime = schedule.departureTime ?? schedule.arrivalTime ?? .distantFuture
            let hasMatchingPrediction = predictions.contains { prediction in
                let predTime = prediction.departureTime ?? prediction.arrivalTime ?? .distantPast
                return abs(predTime.timeIntervalSince(schedTime)) < 120 // 2 min tolerance
            }
            if !hasMatchingPrediction {
                merged.append(schedule)
            }
        }
        
        // Sort by departure time
        let now = Date()
        return merged
            .sorted { a, b in
                let aTime = a.departureTime ?? a.arrivalTime ?? .distantFuture
                let bTime = b.departureTime ?? b.arrivalTime ?? .distantFuture
                return aTime < bTime
            }
            .map { arrival in
                // Recalculate minutesAway from now
                let time = arrival.departureTime ?? arrival.arrivalTime ?? Date()
                let minutes = max(Int(time.timeIntervalSince(now) / 60), 0)
                return BusArrival(
                    id: arrival.id,
                    routeId: arrival.routeId,
                    routeName: arrival.routeName,
                    stopId: arrival.stopId,
                    stopName: arrival.stopName,
                    arrivalTime: arrival.arrivalTime,
                    departureTime: arrival.departureTime,
                    minutesAway: minutes,
                    stopsAway: arrival.stopsAway,
                    directionId: arrival.directionId,
                    status: arrival.status,
                    isScheduled: arrival.isScheduled
                )
            }
    }
    
    /// Formats a Date into "HH:mm" for the MBTA schedule filter.
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func fetchVehicles(ids: [String]) async throws -> [String: Int] {
        let uniqueIDs = Array(Set(ids)).sorted()

        guard !uniqueIDs.isEmpty else {
            return [:]
        }

        let url = try buildURL(
            path: "vehicles",
            queryItems: [URLQueryItem(name: "filter[id]", value: uniqueIDs.joined(separator: ","))]
        )
        let response = try await fetch(VehiclesResponse.self, from: url)

        return response.data.reduce(into: [:]) { partialResult, vehicle in
            partialResult[vehicle.id] = vehicle.attributes.currentStopSequence
        }
    }

    private func calculateStopsAway(targetStopSequence: Int?, currentStopSequence: Int?, minutesAway: Int?) -> Int? {
        guard let targetStopSequence, let currentStopSequence else {
            return nil
        }

        let stopsAway = targetStopSequence - currentStopSequence

        // Bus hasn't started this trip or is past the stop
        if stopsAway <= 0 {
            return nil
        }

        return stopsAway
    }

    private func routeMatches(_ route: Route, query: String, exactOnly: Bool) -> Bool {
        let normalizedQuery = normalizeRouteText(query)
        let candidates = [
            route.id,
            route.shortName ?? "",
            route.longName ?? ""
        ]
        .map(normalizeRouteText)

        if exactOnly {
            return candidates.contains(normalizedQuery)
        }

        return candidates.contains(where: { candidate in
            candidate.contains(normalizedQuery) || normalizedQuery.contains(candidate)
        })
    }

    private func normalizeRouteText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "line", with: "")
            .replacingOccurrences(of: "commuterrail", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// Fetch all currently active alerts, optionally filtered by route IDs.
    func fetchAlerts(routeIDs: [String]? = nil) async throws -> [MBTAAlert] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "filter[datetime]", value: "NOW")
        ]
        if let routeIDs, !routeIDs.isEmpty {
            queryItems.append(URLQueryItem(name: "filter[route]", value: routeIDs.joined(separator: ",")))
        }

        let url = try buildURL(path: "alerts", queryItems: queryItems)
        let response = try await fetch(AlertsResponse.self, from: url)

        return response.data.compactMap { alert in
            let attrs = alert.attributes
            let routes = (attrs.informedEntity ?? []).compactMap { $0.route }
            let uniqueRoutes = Array(Set(routes))

            return MBTAAlert(
                id: alert.id,
                header: attrs.header ?? "",
                description: attrs.description ?? "",
                effect: attrs.effect ?? "UNKNOWN",
                severity: attrs.severity ?? 0,
                serviceEffect: attrs.serviceEffect ?? "",
                routeIDs: uniqueRoutes,
                updatedAt: attrs.updatedAt ?? ""
            )
        }
    }
}
