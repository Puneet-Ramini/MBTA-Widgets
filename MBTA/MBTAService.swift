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
            
            // Supabase monitoring (silent background logging)
            let endpoint = url.path.replacingOccurrences(of: "/", with: "")
            SupabaseMonitoring.shared.logAPICall(
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
                
                // Log error to Supabase
                let endpoint = url.path.replacingOccurrences(of: "/", with: "")
                SupabaseMonitoring.shared.logAPICall(endpoint: endpoint, statusCode: nil, routeName: routeName, directionName: directionName, stopName: stopName)
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

    /// Fetch predictions for a stop, optionally filtered by route.
    func fetchPredictions(stopId: String, routeId: String?, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil) async throws -> [BusArrival] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "filter[stop]", value: stopId),
            URLQueryItem(name: "sort", value: "arrival_time")
        ]

        if let routeId, !routeId.isEmpty {
            queryItems.append(URLQueryItem(name: "filter[route]", value: routeId))
        }

        let url = try buildURL(path: "predictions", queryItems: queryItems)
        let response = try await fetch(PredictionsResponse.self, from: url, routeName: routeName, directionName: directionName, stopName: stopName)
        let now = Date()
        let vehicleIDs = response.data.compactMap { $0.relationships?.vehicle?.data?.id }
        let vehiclesByID = try await fetchVehicles(ids: vehicleIDs)

        return response.data.compactMap { prediction in
            let attributes = prediction.attributes
            let time = attributes.arrivalTime ?? attributes.departureTime

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
            let leftTime = left.arrivalTime ?? left.departureTime ?? .distantFuture
            let rightTime = right.arrivalTime ?? right.departureTime ?? .distantFuture
            return leftTime < rightTime
        }
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

        let directDistance = max(targetStopSequence - currentStopSequence, 0)
        if directDistance == 0, targetStopSequence > 1, let minutesAway, minutesAway > 1 {
            return targetStopSequence - 1
        }

        return directDistance
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
}
