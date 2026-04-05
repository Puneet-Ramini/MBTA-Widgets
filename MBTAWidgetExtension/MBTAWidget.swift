import SwiftUI
import WidgetKit

private enum WidgetTransportMode: String {
    case bus = "Bus"
    case subway = "Subway"
    case commuterRail = "Commuter Rail"

    var showsStopsAway: Bool {
        self == .bus
    }
}

struct MBTAWidgetEntry: TimelineEntry {
    let date: Date
    let routeName: String
    let directionLine: String
    let stopName: String
    let predictions: [WidgetArrivalDisplay]
    let message: String?
}

struct WidgetArrivalDisplay: Hashable {
    let minutesText: String
    let stopsAwayText: String
}

private struct WidgetArrivalSnapshot {
    let arrivalDate: Date
    let stopsAwayText: String
}

private struct WidgetContentState {
    let mode: WidgetTransportMode
    let routeName: String
    let directionLine: String
    let stopName: String
    let arrivals: [WidgetArrivalSnapshot]
    let message: String?
}

struct MBTAWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MBTAWidgetEntry {
        // This is shown in widget gallery and during loading
        MBTAWidgetEntry(
            date: Date(),
            routeName: "39",
            directionLine: "To Back Bay Station",
            stopName: "Huntington Ave @ Perkins St",
            predictions: [
                WidgetArrivalDisplay(minutesText: "6 min", stopsAwayText: "2 stops away"),
                WidgetArrivalDisplay(minutesText: "15 min", stopsAwayText: "5 stops away"),
                WidgetArrivalDisplay(minutesText: "22 min", stopsAwayText: "8 stops away")
            ],
            message: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MBTAWidgetEntry) -> Void) {
        // Always show nice preview in widget gallery
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            // For actual widget on home screen, try to load real data
            Task {
                let state = await loadState()
                let entry = buildPreviewEntry(from: state)
                completion(entry)
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MBTAWidgetEntry>) -> Void) {
        Task {
            let timeline = await loadTimeline()
            completion(timeline)
        }
    }
    
    private func buildPreviewEntry(from state: WidgetContentState) -> MBTAWidgetEntry {
        if let message = state.message {
            return MBTAWidgetEntry(
                date: Date(),
                routeName: state.routeName,
                directionLine: state.directionLine,
                stopName: state.stopName,
                predictions: [],
                message: message
            )
        }
        
        let predictions = state.arrivals.map { arrival in
            WidgetArrivalDisplay(
                minutesText: formatMinutes(arrival.arrivalDate),
                stopsAwayText: arrival.stopsAwayText
            )
        }
        
        return MBTAWidgetEntry(
            date: Date(),
            routeName: state.routeName,
            directionLine: state.directionLine,
            stopName: state.stopName,
            predictions: predictions,
            message: nil
        )
    }
    
    private func formatMinutes(_ date: Date) -> String {
        let minutes = Int(date.timeIntervalSinceNow / 60)
        if minutes < 1 {
            return "Now"
        }
        return "\(minutes) min"
    }

    private func loadTimeline() async -> Timeline<MBTAWidgetEntry> {
        let state = await loadState()
        let now = Date()
        let entries = buildEntries(from: state, startingAt: now)
        
        // Refresh more frequently - every 2 minutes for real-time accuracy
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 2, to: now) ?? now.addingTimeInterval(120)
        
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func loadState() async -> WidgetContentState {
        guard let selection = StoredWidgetSelection.load() else {
            return WidgetContentState(
                mode: .bus,
                routeName: "--",
                directionLine: "Pick a route in the app",
                stopName: "",
                arrivals: [],
                message: "Open the app and choose a bus, direction, and stop."
            )
        }

        do {
            let arrivals = try await WidgetMBTAService().fetchPredictions(
                mode: selection.mode,
                routeID: selection.routeID,
                stopID: selection.stopID
            )

            return WidgetContentState(
                mode: selection.mode,
                routeName: selection.routeName,
                directionLine: selection.directionLine,
                stopName: selection.stopName,
                arrivals: Array(arrivals.prefix(3)),
                message: arrivals.isEmpty ? "No upcoming buses right now." : nil
            )
        } catch {
            return WidgetContentState(
                mode: selection.mode,
                routeName: selection.routeName,
                directionLine: selection.directionLine,
                stopName: selection.stopName,
                arrivals: [],
                message: "Could not load bus times."
            )
        }
    }

    private func buildEntries(from state: WidgetContentState, startingAt startDate: Date) -> [MBTAWidgetEntry] {
        // Create entries for the next 2 minutes (since we refresh every 2 minutes)
        // This keeps the countdown accurate while not overloading the timeline
        let minuteOffsets = [0, 1]
        let entries = minuteOffsets.map { minuteOffset in
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: startDate) ?? startDate
            return MBTAWidgetEntry(
                date: entryDate,
                routeName: state.routeName,
                directionLine: state.directionLine,
                stopName: state.stopName,
                predictions: displays(for: state.arrivals, at: entryDate, mode: state.mode),
                message: state.message
            )
        }

        return entries
    }

    private func displays(for arrivals: [WidgetArrivalSnapshot], at date: Date, mode: WidgetTransportMode) -> [WidgetArrivalDisplay] {
        arrivals
            .filter { $0.arrivalDate >= date }
            .prefix(3)
            .map { arrival in
                let minutes = max(Int(arrival.arrivalDate.timeIntervalSince(date) / 60), 0)
                return WidgetArrivalDisplay(
                    minutesText: "\(minutes) min",
                    stopsAwayText: mode.showsStopsAway ? arrival.stopsAwayText : ""
                )
            }
    }
}

struct MBTAWidgetEntryView: View {
    var entry: MBTAWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(entry.routeName)
                    .font(.headline)
                    .bold()
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.directionLine)
                        .font(.subheadline)
                        .bold()
                        .lineLimit(2)

                    if !entry.stopName.isEmpty {
                        Text(entry.stopName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
            }

            if let message = entry.message {
                Spacer()
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                Spacer(minLength: 4)
                
                HStack(spacing: 8) {
                    ForEach(entry.predictions, id: \.self) { prediction in
                        VStack(spacing: 4) {
                            Text(prediction.minutesText)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 6)
                                .background(Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255))
                                .clipShape(Capsule())

                            if !prediction.stopsAwayText.isEmpty {
                                Text(prediction.stopsAwayText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(" ")
                                    .font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }

                    if entry.predictions.count < 3 {
                        ForEach(entry.predictions.count..<3, id: \.self) { _ in
                            VStack(spacing: 4) {
                                Text("--")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 6)
                                    .background(Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255))
                                    .clipShape(Capsule())

                                Text(" ")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
                
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }
}

struct MBTAWidget: Widget {
    let kind: String = "MBTAWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MBTAWidgetProvider()) { entry in
            MBTAWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MBTA Arrivals")
        .description("Shows the next 3 buses for your selected stop.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct MBTAWidgetBundle: WidgetBundle {
    var body: some Widget {
        MBTAWidget()
    }
}

// MARK: - Previews
#Preview(as: .systemMedium) {
    MBTAWidget()
} timeline: {
    MBTAWidgetEntry(
        date: Date(),
        routeName: "39",
        directionLine: "To Back Bay Station",
        stopName: "Huntington Ave @ Perkins St",
        predictions: [
            WidgetArrivalDisplay(minutesText: "6 min", stopsAwayText: "2 stops away"),
            WidgetArrivalDisplay(minutesText: "15 min", stopsAwayText: "5 stops away"),
            WidgetArrivalDisplay(minutesText: "22 min", stopsAwayText: "8 stops away")
        ],
        message: nil
    )
    
    MBTAWidgetEntry(
        date: Date().addingTimeInterval(60),
        routeName: "39",
        directionLine: "To Back Bay Station",
        stopName: "Huntington Ave @ Perkins St",
        predictions: [
            WidgetArrivalDisplay(minutesText: "5 min", stopsAwayText: "2 stops away"),
            WidgetArrivalDisplay(minutesText: "14 min", stopsAwayText: "5 stops away"),
            WidgetArrivalDisplay(minutesText: "21 min", stopsAwayText: "8 stops away")
        ],
        message: nil
    )
}

private struct StoredWidgetSelection {
    let mode: WidgetTransportMode
    let routeID: String
    let routeName: String
    let directionLine: String
    let stopID: String
    let stopName: String

    static func load() -> StoredWidgetSelection? {
        if let configuredSelection = loadConfiguredSelection() {
            return configuredSelection
        }

        guard
            let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
            let modeValue = defaults.string(forKey: "widget.mode"),
            let mode = WidgetTransportMode(rawValue: modeValue),
            let routeID = defaults.string(forKey: "widget.routeID"),
            let routeName = defaults.string(forKey: "widget.routeName"),
            let stopID = defaults.string(forKey: "widget.stopID"),
            let stopName = defaults.string(forKey: "widget.stopName")
        else {
            return nil
        }

        let directionName = defaults.string(forKey: "widget.directionName") ?? ""
        let destination = defaults.string(forKey: "widget.directionDestination") ?? ""
        let directionLine: String

        if !destination.isEmpty {
            directionLine = "To \(destination)"
        } else if !directionName.isEmpty {
            directionLine = directionName
        } else {
            directionLine = ""
        }

        return StoredWidgetSelection(
            mode: mode,
            routeID: routeID,
            routeName: routeName,
            directionLine: directionLine,
            stopID: stopID,
            stopName: stopName
        )
    }

    private static func loadConfiguredSelection() -> StoredWidgetSelection? {
        guard
            let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
            let data = defaults.data(forKey: "widget.configuration"),
            let configuration = try? JSONDecoder().decode(WidgetStoredConfiguration.self, from: data)
        else {
            return nil
        }

        let now = Date()
        let activeFavorite = configuration.activeFavorite(at: now) ?? configuration.defaultFavorite
        guard let favorite = activeFavorite else {
            return nil
        }

        let mode = WidgetTransportMode(rawValue: favorite.mode) ?? .bus
        let directionLine: String
        if !favorite.directionDestination.isEmpty {
            directionLine = "To \(favorite.directionDestination)"
        } else if !favorite.directionName.isEmpty {
            directionLine = favorite.directionName
        } else {
            directionLine = ""
        }

        return StoredWidgetSelection(
            mode: mode,
            routeID: favorite.routeID,
            routeName: favorite.routeName,
            directionLine: directionLine,
            stopID: favorite.stopID,
            stopName: favorite.stopName
        )
    }
}

private struct WidgetStoredConfiguration: Decodable {
    let defaultFavorite: WidgetStoredFavorite?
    let overrides: [WidgetStoredOverride]

    func activeFavorite(at date: Date) -> WidgetStoredFavorite? {
        overrides.first(where: { $0.isActive(at: date) })?.favorite
    }
}

private struct WidgetStoredOverride: Decodable {
    let id: String
    let favorite: WidgetStoredFavorite?
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int

    func isActive(at date: Date) -> Bool {
        let calendar = Calendar.current
        let nowMinutes = (calendar.component(.hour, from: date) * 60) + calendar.component(.minute, from: date)
        let startMinutes = (startHour * 60) + startMinute
        let endMinutes = (endHour * 60) + endMinute

        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        }

        return nowMinutes >= startMinutes || nowMinutes < endMinutes
    }
}

private struct WidgetStoredFavorite: Decodable {
    let mode: String
    let routeID: String
    let routeName: String
    let directionID: Int
    let directionName: String
    let directionDestination: String
    let stopID: String
    let stopName: String
}

private struct WidgetPredictionsResponse: Decodable {
    let data: [WidgetPredictionData]
}

private struct WidgetPredictionData: Decodable {
    let attributes: WidgetPredictionAttributes
    let relationships: WidgetPredictionRelationships?
}

private struct WidgetPredictionAttributes: Decodable {
    let arrivalTime: Date?
    let departureTime: Date?
    let stopSequence: Int?

    enum CodingKeys: String, CodingKey {
        case arrivalTime = "arrival_time"
        case departureTime = "departure_time"
        case stopSequence = "stop_sequence"
    }
}

private struct WidgetPredictionRelationships: Decodable {
    let vehicle: WidgetRelationship?
}

private struct WidgetRelationship: Decodable {
    let data: WidgetRelationshipData?
}

private struct WidgetRelationshipData: Decodable {
    let id: String
}

private struct WidgetVehiclesResponse: Decodable {
    let data: [WidgetVehicleData]
}

private struct WidgetVehicleData: Decodable {
    let id: String
    let attributes: WidgetVehicleAttributes
}

private struct WidgetVehicleAttributes: Decodable {
    let currentStopSequence: Int?

    enum CodingKeys: String, CodingKey {
        case currentStopSequence = "current_stop_sequence"
    }
}

private struct WidgetMBTAService {
    private let apiKey = "6aaf4b37ca464bc298e7573999c87d4d"

    func fetchPredictions(mode: WidgetTransportMode, routeID: String, stopID: String) async throws -> [WidgetArrivalSnapshot] {
        var components = URLComponents(string: "https://api-v3.mbta.com/predictions")!
        components.queryItems = [
            URLQueryItem(name: "filter[route]", value: routeID),
            URLQueryItem(name: "filter[stop]", value: stopID),
            URLQueryItem(name: "sort", value: "arrival_time"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        let url = components.url!
        var didRecord = false
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            WidgetAPIUsageStore.record(url: url, statusCode: statusCode, source: "widget")
            didRecord = true
        } catch {
            if !didRecord {
                WidgetAPIUsageStore.record(url: url, statusCode: nil, source: "widget")
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetPredictionsResponse.self, from: data)
        let now = Date()
        let vehiclesByID: [String: Int]
        if mode.showsStopsAway {
            let vehicleIDs = decoded.data.compactMap { $0.relationships?.vehicle?.data?.id }
            vehiclesByID = (try? await fetchVehicles(ids: vehicleIDs)) ?? [:]
        } else {
            vehiclesByID = [:]
        }

        return decoded.data
            .compactMap { prediction in
                guard let date = prediction.attributes.arrivalTime ?? prediction.attributes.departureTime else {
                    return nil
                }

                guard date >= now else {
                    return nil
                }

                let vehicleID = prediction.relationships?.vehicle?.data?.id
                let currentStopSequence = vehicleID.flatMap { vehiclesByID[$0] }
                let minutesAway = max(Int(date.timeIntervalSince(now) / 60), 0)

                return WidgetArrivalSnapshot(
                    arrivalDate: date,
                    stopsAwayText: formatStopsAway(
                        targetStopSequence: prediction.attributes.stopSequence,
                        currentStopSequence: currentStopSequence,
                        minutesAway: minutesAway
                    )
                )
            }
            .prefix(3)
            .map { $0 }
    }

    private func fetchVehicles(ids: [String]) async throws -> [String: Int] {
        let uniqueIDs = Array(Set(ids)).sorted()

        guard !uniqueIDs.isEmpty else {
            return [:]
        }

        var components = URLComponents(string: "https://api-v3.mbta.com/vehicles")!
        components.queryItems = [
            URLQueryItem(name: "filter[id]", value: uniqueIDs.joined(separator: ",")),
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        let url = components.url!
        var didRecord = false
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            WidgetAPIUsageStore.record(url: url, statusCode: statusCode, source: "widget")
            didRecord = true
        } catch {
            if !didRecord {
                WidgetAPIUsageStore.record(url: url, statusCode: nil, source: "widget")
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(WidgetVehiclesResponse.self, from: data)
        return decoded.data.reduce(into: [:]) { partialResult, vehicle in
            partialResult[vehicle.id] = vehicle.attributes.currentStopSequence
        }
    }

    private func formatStopsAway(targetStopSequence: Int?, currentStopSequence: Int?, minutesAway: Int?) -> String {
        guard let targetStopSequence, let currentStopSequence else {
            return "stops away unavailable"
        }

        let directDistance = max(targetStopSequence - currentStopSequence, 0)
        let stopsAway: Int
        if directDistance == 0, targetStopSequence > 1, let minutesAway, minutesAway > 1 {
            stopsAway = targetStopSequence - 1
        } else {
            stopsAway = directDistance
        }

        if stopsAway == 1 {
            return "1 stop away"
        }

        return "\(stopsAway) stops away"
    }
}

private struct WidgetAPIUsageEvent: Codable {
    let timestamp: Date
    let endpoint: String
    let source: String
    let statusCode: Int?
}

private struct WidgetAPIUsageSnapshot: Codable {
    var totalRequests: Int
    var successRequests: Int
    var failedRequests: Int
    var endpointCounts: [String: Int]
    var sourceCounts: [String: Int]
    var dailyCounts: [String: Int]
    var hourlyCounts: [String: Int]
    var minuteCounts: [String: Int]
    var recentRequests: [WidgetAPIUsageEvent]
    var lastUpdated: Date

    static let empty = WidgetAPIUsageSnapshot(
        totalRequests: 0,
        successRequests: 0,
        failedRequests: 0,
        endpointCounts: [:],
        sourceCounts: [:],
        dailyCounts: [:],
        hourlyCounts: [:],
        minuteCounts: [:],
        recentRequests: [],
        lastUpdated: .distantPast
    )
}

private enum WidgetAPIUsageStore {
    static func record(url: URL, statusCode: Int?, source: String) {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA") else {
            return
        }

        let now = Date()
        var snapshot = loadSnapshot(from: defaults)
        let endpoint = endpointName(from: url)
        let dayKey = dayFormatter.string(from: now)
        let hourKey = hourFormatter.string(from: now)
        let minuteKey = minuteFormatter.string(from: now)

        snapshot.totalRequests += 1
        if let statusCode, (200...299).contains(statusCode) {
            snapshot.successRequests += 1
        } else {
            snapshot.failedRequests += 1
        }
        snapshot.endpointCounts[endpoint, default: 0] += 1
        snapshot.sourceCounts[source, default: 0] += 1
        snapshot.dailyCounts[dayKey, default: 0] += 1
        snapshot.hourlyCounts[hourKey, default: 0] += 1
        snapshot.minuteCounts[minuteKey, default: 0] += 1
        snapshot.recentRequests.insert(
            WidgetAPIUsageEvent(timestamp: now, endpoint: endpoint, source: source, statusCode: statusCode),
            at: 0
        )
        snapshot.recentRequests = Array(snapshot.recentRequests.prefix(100))
        snapshot.lastUpdated = now

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: "apiUsageSnapshot")
        defaults.set(2000, forKey: "apiUsageLimit")
    }

    private static func loadSnapshot(from defaults: UserDefaults) -> WidgetAPIUsageSnapshot {
        guard let data = defaults.data(forKey: "apiUsageSnapshot") else {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetAPIUsageSnapshot.self, from: data)) ?? .empty
    }

    private static func endpointName(from url: URL) -> String {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.contains("/") {
            return String(path.split(separator: "/").first ?? "")
        }
        return path.isEmpty ? "unknown" : path
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH"
        return formatter
    }()

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

#Preview(as: .systemSmall) {
    MBTAWidget()
} timeline: {
    MBTAWidgetEntry(
        date: Date(),
        routeName: "39",
        directionLine: "To Back Bay Station",
        stopName: "S Huntington Ave @ Perkins St",
        predictions: [
            WidgetArrivalDisplay(minutesText: "6 min", stopsAwayText: "2 stops away"),
            WidgetArrivalDisplay(minutesText: "22 min", stopsAwayText: "7 stops away"),
            WidgetArrivalDisplay(minutesText: "28 min", stopsAwayText: "9 stops away")
        ],
        message: nil
    )
}
