//
//  FirebaseMonitoring.swift
//  MBTA
//
//  Replaces SupabaseMonitoring — logs MBTA API calls to Firebase Firestore.
//

import Foundation
import FirebaseFirestore

/// Backend monitoring — logs API calls to Firestore (one-way, fire-and-forget)
final class FirebaseMonitoring {
    static let shared = FirebaseMonitoring()

    private let db = Firestore.firestore()

    /// Device ID stored in Keychain so it persists across app reinstalls.
    /// Exposed as `publicDeviceID` for use by other components (e.g., FCM registration).
    lazy var publicDeviceID: String = { deviceID }()
    
    private lazy var deviceID: String = {
        let service = "com.mbta.monitoring"
        let account = "deviceID"

        // Try reading from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let existing = String(data: data, encoding: .utf8) {
            return existing
        }

        // Migrate from UserDefaults if present
        let newID: String
        if let legacy = UserDefaults.standard.string(forKey: "deviceID") {
            newID = legacy
            UserDefaults.standard.removeObject(forKey: "deviceID")
        } else {
            newID = UUID().uuidString
        }

        // Save to Keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(newID.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        
        // Also save to app group so the widget extension can read it
        UserDefaults(suiteName: "group.Widgets.MBTA")?.set(newID, forKey: "deviceID")

        return newID
    }()

    /// ET date key formatter (YYYY-MM-DD)
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    private init() {}

    /// Log MBTA API call to Firestore (daily_stats only — no per-call documents)
    func logAPICall(endpoint: String, statusCode: Int?, responseTimeMs: Int? = nil, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil, source: String = "app") {
        incrementDailyStats()
    }

    /// Increments total_api_calls for today (1 write, 0 reads).
    private func incrementDailyStats() {
        let dateKey = dateFormatter.string(from: Date())
        let statsRef = db.collection("daily_stats").document(dateKey)

        statsRef.setData([
            "date": dateKey,
            "total_api_calls": FieldValue.increment(Int64(1))
        ], merge: true)
    }
}
