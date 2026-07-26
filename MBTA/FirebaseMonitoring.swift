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

    /// Log MBTA API call to Firestore
    func logAPICall(endpoint: String, statusCode: Int?, responseTimeMs: Int? = nil, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil, source: String = "app") {
        let device = deviceID
        let data: [String: Any] = [
            "endpoint": endpoint,
            "status_code": statusCode as Any,
            "response_time_ms": responseTimeMs as Any,
            "route_name": routeName as Any,
            "direction_name": directionName as Any,
            "stop_name": stopName as Any,
            "source": source,
            "timestamp": Timestamp(date: Date()),
            "device_id": device
        ]

        db.collection("api_logs").addDocument(data: data) { error in
            if let error {
                print("Firestore log failed for \(endpoint): \(error.localizedDescription)")
            }
        }

        // Update daily_stats summary
        incrementDailyStats(deviceId: device)
    }

    /// Increments total_api_calls for today.
    /// On the first call from this device_id today, also increments unique_users.
    private func incrementDailyStats(deviceId: String) {
        let dateKey = dateFormatter.string(from: Date())
        let statsRef = db.collection("daily_stats").document(dateKey)
        let userRef = db.collection("daily_users").document(dateKey)
            .collection("users").document(deviceId)

        // Increment total_api_calls (merge-safe, no read required)
        statsRef.setData([
            "date": dateKey,
            "total_api_calls": FieldValue.increment(Int64(1))
        ], merge: true)

        // Transaction: create user doc if missing, increment unique_users only once
        db.runTransaction({ tx, errorPointer in
            do {
                let snap = try tx.getDocument(userRef)
                if !snap.exists {
                    tx.setData(["first_seen": Timestamp(date: Date())], forDocument: userRef)
                    tx.setData(["unique_users": FieldValue.increment(Int64(1))], forDocument: statsRef, merge: true)
                }
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }, completion: { _, error in
            if let error {
                print("Daily stats transaction failed: \(error.localizedDescription)")
            }
        })
    }
}
