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

    func getSnapshot(in context: Context, completion: @escaping (MBTAWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MBTAWidgetEntry>) -> Void) {
        Task {
            let timeline = await loadTimeline()
            completion(timeline)
        }
    }

    private func loadTimeline() async -> Timeline<MBTAWidgetEntry> {
        let state = await loadState()
        let now = Date()
        let entries = buildEntries(from: state, startingAt: now)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
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
        let minuteOffsets = Array(0...14)
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
        VStack(alignment: .leading, spacing: 10) {
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
            }

            if let message = entry.message {
                Spacer()
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                HStack(spacing: 10) {
                    ForEach(entry.predictions, id: \.self) { prediction in
                        VStack(spacing: 6) {
                            Text(prediction.minutesText)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
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
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .top)
                    }

                    if entry.predictions.count < 3 {
                        ForEach(entry.predictions.count..<3, id: \.self) { _ in
                            VStack(spacing: 6) {
                                Text("--")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 8)
                                    .background(Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255))
                                    .clipShape(Capsule())

                                Text(" ")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .top)
                        }
                    }
                }
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MBTAWidgetBundle: WidgetBundle {
    var body: some Widget {
        MBTAWidget()
    }
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

        let (data, response) = try await URLSession.shared.data(from: components.url!)
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

        let (data, response) = try await URLSession.shared.data(from: components.url!)
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
