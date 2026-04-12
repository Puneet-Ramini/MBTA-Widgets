//
//  SupabaseService.swift
//  MBTA
//
//  Created on 4/8/26.
//

import Foundation
#if canImport(Supabase)
import Supabase
#endif

/// One-way analytics service: app → Supabase (no data loaded back)
final class SupabaseService {
    static let shared = SupabaseService()
    
    #if canImport(Supabase)
    private let client: SupabaseClient
    private var isAuthenticated = false
    #endif
    
    private init() {
        #if canImport(Supabase)
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.publishableKey
        )
        
        // Auto sign-in anonymously in background
        Task {
            try? await signInAnonymously()
        }
        #endif
    }
    
    // MARK: - Authentication (Internal - Automatic)
    
    private func signInAnonymously() async throws {
        #if canImport(Supabase)
        guard !isAuthenticated else { return }
        _ = try await client.auth.signInAnonymously()
        isAuthenticated = true
        #endif
    }
    
    private func getUserID() async -> String? {
        #if canImport(Supabase)
        return try? await client.auth.session.user.id.uuidString
        #else
        return nil
        #endif
    }
    
    // MARK: - Analytics Logging (One-Way)
    
    /// Log when user saves a favorite (for analytics)
    func logFavoriteUsage(routeID: String, routeName: String, mode: String, stopID: String) async {
        #if canImport(Supabase)
        struct FavoriteLog: Encodable {
            let user_id: String?
            let route_id: String
            let route_name: String
            let mode: String
            let stop_id: String
            let timestamp: Date
        }
        
        let userID = await getUserID()
        let log = FavoriteLog(
            user_id: userID,
            route_id: routeID,
            route_name: routeName,
            mode: mode,
            stop_id: stopID,
            timestamp: Date()
        )
        
        try? await client.database
            .from("favorite_analytics")
            .insert(log)
            .execute()
        #endif
    }
    
    /// Log MBTA API usage (for monitoring)
    func logAPIUsage(endpoint: String, statusCode: Int?) async {
        #if canImport(Supabase)
        struct APILog: Encodable {
            let user_id: String?
            let endpoint: String
            let status_code: Int?
            let timestamp: Date
        }
        
        let userID = await getUserID()
        let log = APILog(
            user_id: userID,
            endpoint: endpoint,
            status_code: statusCode,
            timestamp: Date()
        )
        
        try? await client.database
            .from("api_logs")
            .insert(log)
            .execute()
        #endif
    }
}
