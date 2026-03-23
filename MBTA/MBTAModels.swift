import Foundation

// MARK: - Simple app model for displaying arrivals

enum TransportMode: String, CaseIterable, Codable, Identifiable {
    case bus = "Bus"
    case subway = "Subway"
    case commuterRail = "Commuter Rail"

    var id: String { rawValue }

    var fieldTitle: String {
        switch self {
        case .bus:
            return "Bus Number"
        case .subway, .commuterRail:
            return "Line"
        }
    }

    var placeholder: String {
        switch self {
        case .bus:
            return "39"
        case .subway:
            return "Red Line"
        case .commuterRail:
            return "Framingham/Worcester"
        }
    }

    var stopTitle: String {
        switch self {
        case .commuterRail:
            return "Station"
        case .bus, .subway:
            return "Stop"
        }
    }

    var routeTypeFilterValue: String {
        switch self {
        case .bus:
            return "3"
        case .subway:
            return "0,1"
        case .commuterRail:
            return "2"
        }
    }

    var defaultQuickLabels: [String] {
        []
    }

    var showsStopsAway: Bool {
        self == .bus
    }

    var presetLines: [PresetLine] {
        switch self {
        case .bus:
            return []
        case .subway:
            return [
                PresetLine(title: "Red Line", query: "Red", colorName: "red"),
                PresetLine(title: "Mattapan Line", query: "Mattapan", colorName: "red"),
                PresetLine(title: "Orange Line", query: "Orange", colorName: "orange"),
                PresetLine(title: "Blue Line", query: "Blue", colorName: "blue"),
                PresetLine(title: "Green Line", query: "Green", colorName: "green")
            ]
        case .commuterRail:
            return [
                PresetLine(title: "Framingham/Worcester", query: "Framingham/Worcester", colorName: "purple"),
                PresetLine(title: "Providence/Stoughton", query: "Providence/Stoughton", colorName: "purple"),
                PresetLine(title: "Fitchburg", query: "Fitchburg", colorName: "purple"),
                PresetLine(title: "Lowell", query: "Lowell", colorName: "purple"),
                PresetLine(title: "Franklin/Foxboro", query: "Franklin/Foxboro", colorName: "purple")
            ]
        }
    }

    var greenLineBranches: [PresetLine] {
        [
            PresetLine(title: "B", query: "Green-B", colorName: "green"),
            PresetLine(title: "C", query: "Green-C", colorName: "green"),
            PresetLine(title: "D", query: "Green-D", colorName: "green"),
            PresetLine(title: "E", query: "Green-E", colorName: "green")
        ]
    }
}

struct PresetLine: Identifiable, Hashable {
    let title: String
    let query: String
    let colorName: String

    var id: String { query }
}

/// Represents a single upcoming bus arrival that the UI can show.
struct BusArrival: Identifiable {
    let id: String
    let routeId: String
    let routeName: String
    let stopId: String
    let stopName: String
    let arrivalTime: Date?
    let departureTime: Date?
    let minutesAway: Int?
    let stopsAway: Int?
    let directionId: Int?
    let status: String?
}

struct BusStop: Identifiable {
    let id: String
    let name: String
}

struct Route: Identifiable {
    let id: String
    let shortName: String?
    let longName: String?
    let directionNames: [String]
    let directionDestinations: [String]

    var displayName: String {
        if let shortName, !shortName.isEmpty {
            return shortName
        }

        if let longName, !longName.isEmpty {
            return longName
        }

        return id
    }

    var directionOptions: [RouteDirection] {
        let count = max(directionNames.count, directionDestinations.count)

        return (0..<count).map { index in
            let name = directionNames.indices.contains(index) ? directionNames[index] : "Direction \(index)"
            let destination = directionDestinations.indices.contains(index) ? directionDestinations[index] : ""
            return RouteDirection(id: index, name: name, destination: destination)
        }
    }
}

struct RouteDirection: Identifiable, Hashable {
    let id: Int
    let name: String
    let destination: String

    var displayName: String {
        if destination.isEmpty {
            return name
        }

        return "\(name) to \(destination)"
    }
}

// MARK: - Minimal MBTA API response models

struct PredictionsResponse: Codable {
    let data: [PredictionData]
}

struct PredictionData: Codable {
    let id: String
    let attributes: PredictionAttributes
    let relationships: PredictionRelationships?
}

struct PredictionAttributes: Codable {
    let arrivalTime: Date?
    let departureTime: Date?
    let directionId: Int?
    let stopSequence: Int?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case arrivalTime = "arrival_time"
        case departureTime = "departure_time"
        case directionId = "direction_id"
        case stopSequence = "stop_sequence"
        case status
    }
}

struct PredictionRelationships: Codable {
    let route: PredictionRelationship?
    let stop: PredictionRelationship?
    let vehicle: PredictionRelationship?
}

struct PredictionRelationship: Codable {
    let data: PredictionRelationshipData?
}

struct PredictionRelationshipData: Codable {
    let id: String
}

struct StopResponse: Codable {
    let data: StopData
}

struct StopData: Codable {
    let id: String
    let attributes: StopAttributes
}

struct StopAttributes: Codable {
    let name: String
}

struct StopsResponse: Codable {
    let data: [StopData]
}

struct RoutesResponse: Codable {
    let data: [RouteData]
}

struct RouteData: Codable {
    let id: String
    let attributes: RouteAttributes
}

struct RouteResponse: Codable {
    let data: RouteData
}

struct RouteAttributes: Codable {
    let shortName: String?
    let longName: String?
    let directionNames: [String]
    let directionDestinations: [String]

    enum CodingKeys: String, CodingKey {
        case shortName = "short_name"
        case longName = "long_name"
        case directionNames = "direction_names"
        case directionDestinations = "direction_destinations"
    }
}

struct VehiclesResponse: Codable {
    let data: [VehicleData]
}

struct VehicleData: Codable {
    let id: String
    let attributes: VehicleAttributes
}

struct VehicleAttributes: Codable {
    let currentStopSequence: Int?

    enum CodingKeys: String, CodingKey {
        case currentStopSequence = "current_stop_sequence"
    }
}
