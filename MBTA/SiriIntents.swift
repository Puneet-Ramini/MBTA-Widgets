//
//  SiriIntents.swift
//  MBTA
//
//  Siri integration using App Intents for checking transit arrivals.
//  Uses a lightweight direct API call instead of MBTAService to avoid
//  Firebase/monitoring dependencies that aren't available in Siri's process.
//

import AppIntents
import SwiftUI

// MARK: - Check Arrival Intent

/// Main Siri intent: "When is my next arrival in MBTA Widgets"
/// Reads saved favorites and fetches live predictions directly from the MBTA API.
struct CheckArrivalIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Next Arrival"
    static var description = IntentDescription("Check when your next bus, train, or commuter rail is arriving.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Route Name")
    var routeName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let favorites = SiriHelpers.loadFavorites()

        // No favorites saved at all
        guard !favorites.isEmpty else {
            return .result(dialog: "You don't have any saved favorites yet. Open MBTA Widgets and save a route to use Siri.")
        }

        // Determine which favorite to use
        let favorite: SavedFavorite

        if let query = routeName, !query.isEmpty {
            let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            let matches = favorites.filter { fav in
                let routeID = fav.routeID.lowercased()
                let name = fav.routeName.lowercased()
                return routeID == normalizedQuery
                    || name == normalizedQuery
                    || routeID.contains(normalizedQuery)
                    || name.contains(normalizedQuery)
            }

            guard let first = matches.first else {
                return .result(dialog: IntentDialog(stringLiteral: "I couldn't find \(query) in your saved favorites. Open MBTA Widgets and save it first."))
            }

            favorite = first
        } else {
            // No route specified — use the first favorite
            favorite = favorites[0]
        }

        // Fetch predictions and build response
        let dialog = await fetchAndFormat(for: favorite)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }

    // MARK: - Fetch and Format

    private func fetchAndFormat(for favorite: SavedFavorite) async -> String {
        let arrivals = await SiriHelpers.fetchArrivals(for: favorite)
        return formatResponse(arrivals: arrivals, favorite: favorite)
    }

    // MARK: - Format Response by Transit Mode

    private func formatResponse(arrivals: [(minutes: Int, time: Date)], favorite: SavedFavorite) -> String {
        let top = Array(arrivals.prefix(3))

        guard let first = top.first else {
            return noServiceMessage(for: favorite)
        }

        let modeNoun = SiriHelpers.modeSpecificNoun(for: favorite.mode)
        let routeLabel = SiriHelpers.routeDisplayLabel(for: favorite)
        let verb = favorite.mode == .commuterRail ? "departs from" : "arrives at"
        let verbPresent = favorite.mode == .commuterRail ? "departing from" : "arriving at"

        if first.minutes == 0 {
            var response = "The \(routeLabel) \(modeNoun) is \(verbPresent) \(favorite.stopName) now!"
            if top.count > 1 {
                response += " The next one is in \(top[1].minutes) minute\(top[1].minutes == 1 ? "" : "s")."
            }
            return response
        }

        var response = "The next \(routeLabel) \(modeNoun) \(verb) \(favorite.stopName) in \(first.minutes) minute\(first.minutes == 1 ? "" : "s")."

        if top.count > 1 {
            response += " The one after that is in \(top[1].minutes) minute\(top[1].minutes == 1 ? "" : "s")."
        }

        return response
    }

    private func noServiceMessage(for favorite: SavedFavorite) -> String {
        let modeNoun = SiriHelpers.modeSpecificNoun(for: favorite.mode)
        let routeLabel = SiriHelpers.routeDisplayLabel(for: favorite)
        return "There are no upcoming \(routeLabel) \(modeNoun)\(modeNoun == "bus" ? "es" : "s") at \(favorite.stopName) right now."
    }
}

// MARK: - Shared Siri Helpers

enum SiriHelpers {
    static let apiKey = "6aaf4b37ca464bc298e7573999c87d4d"

    static func loadFavorites() -> [SavedFavorite] {
        let keys = ["quickRoute0", "quickRoute1", "quickRoute2", "quickRoute3"]
        let decoder = JSONDecoder()

        let fromStandard: [SavedFavorite] = keys.compactMap { key in
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? decoder.decode(SavedFavorite.self, from: data)
        }

        if !fromStandard.isEmpty {
            return fromStandard
        }

        guard let appGroup = UserDefaults(suiteName: "group.Widgets.MBTA"),
              let data = appGroup.data(forKey: "quickFavorites"),
              let favorites = try? decoder.decode([SavedFavorite?].self, from: data) else {
            return []
        }

        return favorites.compactMap { $0 }
    }

    static func fetchArrivals(for favorite: SavedFavorite) async -> [(minutes: Int, time: Date)] {
        let isCommuterRail = favorite.mode == .commuterRail
        
        do {
            var components = URLComponents(string: "https://api-v3.mbta.com/predictions")!
            components.queryItems = [
                URLQueryItem(name: "filter[stop]", value: favorite.stopID),
                URLQueryItem(name: "filter[route]", value: favorite.routeID),
                URLQueryItem(name: "filter[direction_id]", value: String(favorite.directionID)),
                URLQueryItem(name: "sort", value: isCommuterRail ? "departure_time" : "arrival_time"),
                URLQueryItem(name: "api_key", value: apiKey)
            ]

            let (data, response) = try await URLSession.shared.data(from: components.url!)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let predictionsResponse = try decoder.decode(SiriPredictionsResponse.self, from: data)

            let now = Date()
            var results: [(minutes: Int, time: Date)] = predictionsResponse.data.compactMap { prediction in
                let attrs = prediction.attributes
                // Commuter rail: prefer departure time
                let time = isCommuterRail
                    ? (attrs.departureTime ?? attrs.arrivalTime)
                    : (attrs.arrivalTime ?? attrs.departureTime)
                guard let time, time >= now else {
                    return nil
                }
                let minutes = max(Int(time.timeIntervalSince(now) / 60), 0)
                return (minutes: minutes, time: time)
            }
            
            // For commuter rail, merge with schedules to fill in non-predicted trips
            if isCommuterRail {
                let schedules = await fetchSchedules(for: favorite)
                for schedule in schedules {
                    let hasMatch = results.contains { abs($0.time.timeIntervalSince(schedule.time)) < 120 }
                    if !hasMatch {
                        results.append(schedule)
                    }
                }
                results.sort { $0.time < $1.time }
            }
            
            return results
        } catch {
            return []
        }
    }
    
    /// Fetch scheduled departures as fallback when predictions are empty.
    static func fetchSchedules(for favorite: SavedFavorite) async -> [(minutes: Int, time: Date)] {
        do {
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            
            var components = URLComponents(string: "https://api-v3.mbta.com/schedules")!
            components.queryItems = [
                URLQueryItem(name: "filter[stop]", value: favorite.stopID),
                URLQueryItem(name: "filter[route]", value: favorite.routeID),
                URLQueryItem(name: "filter[direction_id]", value: String(favorite.directionID)),
                URLQueryItem(name: "filter[min_time]", value: formatter.string(from: now)),
                URLQueryItem(name: "sort", value: "departure_time"),
                URLQueryItem(name: "api_key", value: apiKey)
            ]
            
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let schedulesResponse = try decoder.decode(SiriSchedulesResponse.self, from: data)
            
            return schedulesResponse.data.compactMap { schedule in
                let time = schedule.attributes.departureTime ?? schedule.attributes.arrivalTime
                guard let time, time >= now else { return nil }
                let minutes = max(Int(time.timeIntervalSince(now) / 60), 0)
                return (minutes: minutes, time: time)
            }
        } catch {
            return []
        }
    }

    static func modeSpecificNoun(for mode: TransportMode) -> String {
        switch mode {
        case .bus: return "bus"
        case .subway, .commuterRail: return "train"
        }
    }

    static func routeDisplayLabel(for favorite: SavedFavorite) -> String {
        switch favorite.mode {
        case .bus: return "Route \(favorite.routeName)"
        case .subway, .commuterRail: return favorite.routeName
        }
    }
}

// MARK: - Lightweight Siri-only API Response Models

private struct SiriPredictionsResponse: Decodable, Sendable {
    let data: [SiriPrediction]
}

private struct SiriPrediction: Decodable, Sendable {
    let attributes: SiriPredictionAttributes
}

private struct SiriPredictionAttributes: Decodable, Sendable {
    let arrivalTime: Date?
    let departureTime: Date?
    let directionId: Int?

    enum CodingKeys: String, CodingKey {
        case arrivalTime = "arrival_time"
        case departureTime = "departure_time"
        case directionId = "direction_id"
    }
}

// MARK: - Siri Schedule Response Models

private struct SiriSchedulesResponse: Decodable, Sendable {
    let data: [SiriSchedule]
}

private struct SiriSchedule: Decodable, Sendable {
    let attributes: SiriScheduleAttributes
}

private struct SiriScheduleAttributes: Decodable, Sendable {
    let arrivalTime: Date?
    let departureTime: Date?

    enum CodingKeys: String, CodingKey {
        case arrivalTime = "arrival_time"
        case departureTime = "departure_time"
    }
}

// MARK: - App Shortcuts Provider

struct MBTAShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckArrivalIntent(),
            phrases: [
                "Check my next arrival in \(.applicationName)",
                "When is my next arrival in \(.applicationName)",
                "Next arrival in \(.applicationName)",
                "When is my next bus in \(.applicationName)",
                "When is my next train in \(.applicationName)",
                "Check \(.applicationName)",
                "Open \(.applicationName) arrivals"
            ],
            shortTitle: "Next Arrival",
            systemImageName: "bus.fill"
        )
    }
}
