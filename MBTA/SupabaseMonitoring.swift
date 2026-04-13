//
//  SupabaseMonitoring.swift
//  MBTA
//
//  Created on 4/8/26.
//

import Foundation

/// Backend monitoring - logs API calls to Supabase using direct HTTP (no SDK needed)
final class SupabaseMonitoring {
    static let shared = SupabaseMonitoring()
    
    private let supabaseURL = SupabaseConfig.url.absoluteString
    private let supabaseKey = SupabaseConfig.publishableKey
    
    private var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: "deviceID") {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "deviceID")
        return newID
    }
    
    private init() {}
    
    /// Log MBTA API call using direct HTTP POST
    func logAPICall(endpoint: String, statusCode: Int?, responseTimeMs: Int? = nil, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil, source: String = "app") {
        // Fire and forget - use detached task that won't be cancelled
        Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                try await self.sendLog(
                    endpoint: endpoint,
                    statusCode: statusCode,
                    responseTimeMs: responseTimeMs,
                    routeName: routeName,
                    directionName: directionName,
                    stopName: stopName,
                    source: source
                )
            } catch {
                print("Supabase log failed for \(endpoint): \(error.localizedDescription)")
            }
        }
    }

    private func sendLog(endpoint: String, statusCode: Int?, responseTimeMs: Int?, routeName: String?, directionName: String?, stopName: String?, source: String) async throws {
        struct APILog: Codable {
            let endpoint: String
            let status_code: Int?
            let response_time_ms: Int?
            let route_name: String?
            let direction_name: String?
            let stop_name: String?
            let source: String
            let timestamp: String
            let device_id: String
        }

        let publishableKey = supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publishableKey.isEmpty, !publishableKey.contains("PLACEHOLDER") else {
            throw MonitoringError.invalidConfiguration("SupabasePublishableKey in Info.plist is still a placeholder")
        }

        let deviceID = await MainActor.run { self.deviceID }
        let log = APILog(
            endpoint: endpoint,
            status_code: statusCode,
            response_time_ms: responseTimeMs,
            route_name: routeName,
            direction_name: directionName,
            stop_name: stopName,
            source: source,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            device_id: deviceID
        )

        guard let url = URL(string: "\(supabaseURL)/rest/v1/api_logs") else {
            throw MonitoringError.invalidConfiguration("SupabaseProjectURL is invalid")
        }

        let jsonData = try JSONEncoder().encode(log)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(publishableKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonitoringError.invalidResponse(statusCode: nil, body: "Non-HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty body>"
            throw MonitoringError.invalidResponse(statusCode: httpResponse.statusCode, body: body)
        }
    }

    private enum MonitoringError: LocalizedError {
        case invalidConfiguration(String)
        case invalidResponse(statusCode: Int?, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message):
                return message
            case .invalidResponse(let statusCode, let body):
                if let statusCode {
                    return "HTTP \(statusCode): \(body)"
                }

                return body
            }
        }
    }
}
