import Foundation

struct APIUsageEvent: Codable {
    let timestamp: Date
    let endpoint: String
    let source: String
    let statusCode: Int?
}

struct APIUsageSnapshot: Codable {
    var totalRequests: Int
    var successRequests: Int
    var failedRequests: Int
    var endpointCounts: [String: Int]
    var sourceCounts: [String: Int]
    var dailyCounts: [String: Int]
    var hourlyCounts: [String: Int]
    var minuteCounts: [String: Int]
    var recentRequests: [APIUsageEvent]
    var lastUpdated: Date

    static let empty = APIUsageSnapshot(
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

enum APIUsageStore {
    private static let snapshotKey = "apiUsageSnapshot"
    private static let appGroupID = "group.Widgets.MBTA"
    private static let limit = 2000
    private static let calendar = Calendar(identifier: .gregorian)

    static func record(url: URL, statusCode: Int?, source: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
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
            APIUsageEvent(timestamp: now, endpoint: endpoint, source: source, statusCode: statusCode),
            at: 0
        )
        snapshot.recentRequests = Array(snapshot.recentRequests.prefix(100))
        snapshot.lastUpdated = now

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: snapshotKey)
        defaults.set(limit, forKey: "apiUsageLimit")
    }

    private static func loadSnapshot(from defaults: UserDefaults) -> APIUsageSnapshot {
        guard let data = defaults.data(forKey: snapshotKey) else {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(APIUsageSnapshot.self, from: data)) ?? .empty
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
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH"
        return formatter
    }()

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
