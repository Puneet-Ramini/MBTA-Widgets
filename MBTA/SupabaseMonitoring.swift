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
    
    /// Test Supabase connection - call this manually to debug
    func testConnection() {
        Task {
            print("🧪 Testing Supabase connection...")
            print("🧪 Device ID: \(deviceID)")
            print("🧪 URL: \(supabaseURL)/rest/v1/api_logs")
            
            logAPICall(
                endpoint: "test_connection",
                statusCode: 200,
                responseTimeMs: 0,
                routeName: "TEST",
                directionName: "TEST",
                stopName: "TEST",
                source: "debug"
            )
        }
    }
    
    /// Log MBTA API call using direct HTTP POST
    func logAPICall(endpoint: String, statusCode: Int?, responseTimeMs: Int? = nil, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil, source: String = "app") {
        Task {
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
            
            guard let url = URL(string: "\(supabaseURL)/rest/v1/api_logs"),
                  let jsonData = try? JSONEncoder().encode(log) else {
                print("❌ Supabase: Failed to create URL or encode JSON")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue(supabaseKey, forHTTPHeaderField: "apikey")
            request.addValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = jsonData
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if (200...299).contains(httpResponse.statusCode) {
                        print("✅ Supabase: Logged \(endpoint) - device: \(deviceID)")
                    } else {
                        print("❌ Supabase: HTTP \(httpResponse.statusCode) for \(endpoint)")
                    }
                }
            } catch {
                print("❌ Supabase error: \(error.localizedDescription)")
            }
        }
    }
}
