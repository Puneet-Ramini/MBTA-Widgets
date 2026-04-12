//
//  SupabaseService.swift
//  MBTA
//
//  Created on 4/8/26.
//

import Foundation
import Combine
#if canImport(Supabase)
import Supabase
import Auth
#endif

// MARK: - Shared Models

struct SavedFavorite: Codable, Identifiable {
    let mode: TransportMode
    let routeID: String
    let routeName: String
    let directionID: Int
    let directionName: String
    let directionDestination: String
    let stopID: String
    let stopName: String

    var id: String {
        "\(routeID)-\(directionID)-\(stopID)"
    }

    var buttonTitle: String {
        routeID
    }

    init(
        mode: TransportMode,
        routeID: String,
        routeName: String,
        directionID: Int,
        directionName: String,
        directionDestination: String,
        stopID: String,
        stopName: String
    ) {
        self.mode = mode
        self.routeID = routeID
        self.routeName = routeName
        self.directionID = directionID
        self.directionName = directionName
        self.directionDestination = directionDestination
        self.stopID = stopID
        self.stopName = stopName
    }
}

enum TransportMode: String, Codable {
    case bus = "Bus"
    case subway = "Subway"
    case commuterRail = "Commuter Rail"
}

/// Service layer for interacting with Supabase backend
@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    #if canImport(Supabase)
    // Supabase client instance
    let client: SupabaseClient
    #endif
    
    // Published properties for auth state
    #if canImport(Supabase)
    @Published var currentUser: User?
    #else
    @Published var currentUser: String?
    #endif
    @Published var isAuthenticated = false
    
    private init() {
        #if canImport(Supabase)
        // Initialize Supabase client
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.publishableKey
        )
        
        // Check initial auth state
        Task {
            await checkAuthState()
        }
        #endif
    }
    
    // MARK: - Authentication
    
    /// Check current authentication state
    func checkAuthState() async {
        #if canImport(Supabase)
        do {
            let session = try await client.auth.session
            self.currentUser = session.user
            self.isAuthenticated = true
        } catch {
            self.currentUser = nil
            self.isAuthenticated = false
        }
        #endif
    }
    
    /// Sign in anonymously (good for getting started)
    func signInAnonymously() async throws {
        #if canImport(Supabase)
        let session = try await client.auth.signInAnonymously()
        self.currentUser = session.user
        self.isAuthenticated = true
        #endif
    }
    
    /// Sign in with email
    func signIn(email: String, password: String) async throws {
        #if canImport(Supabase)
        let session = try await client.auth.signIn(email: email, password: password)
        self.currentUser = session.user
        self.isAuthenticated = true
        #endif
    }
    
    /// Sign up with email
    func signUp(email: String, password: String) async throws {
        #if canImport(Supabase)
        let response = try await client.auth.signUp(email: email, password: password)
        self.currentUser = response.user
        self.isAuthenticated = true
        #endif
    }
    
    /// Sign out
    func signOut() async throws {
        #if canImport(Supabase)
        try await client.auth.signOut()
        self.currentUser = nil
        self.isAuthenticated = false
        #endif
    }
    
    // MARK: - Database Operations
    
    /// Save a favorite to Supabase
    /// You'll need to create a "favorites" table in your Supabase dashboard
    func saveFavorite(_ favorite: SavedFavorite) async throws {
        #if canImport(Supabase)
        struct FavoriteRecord: Encodable {
            let user_id: String?
            let mode: String
            let route_id: String
            let route_name: String
            let direction_id: Int
            let direction_name: String
            let direction_destination: String
            let stop_id: String
            let stop_name: String
            let created_at: Date
        }
        
        let record = FavoriteRecord(
            user_id: currentUser?.id.uuidString,
            mode: favorite.mode.rawValue,
            route_id: favorite.routeID,
            route_name: favorite.routeName,
            direction_id: favorite.directionID,
            direction_name: favorite.directionName,
            direction_destination: favorite.directionDestination,
            stop_id: favorite.stopID,
            stop_name: favorite.stopName,
            created_at: Date()
        )
        
        try await client.database
            .from("favorites")
            .insert(record)
            .execute()
        #endif
    }
    
    /// Fetch all favorites for the current user
    func fetchFavorites() async throws -> [SavedFavorite] {
        #if canImport(Supabase)
        struct FavoriteRecord: Decodable {
            let id: Int
            let user_id: String?
            let mode: String
            let route_id: String
            let route_name: String
            let direction_id: Int
            let direction_name: String
            let direction_destination: String
            let stop_id: String
            let stop_name: String
            let created_at: Date
        }
        
        let records: [FavoriteRecord] = try await client.database
            .from("favorites")
            .select()
            .execute()
            .value
        
        return records.compactMap { record in
            guard let mode = TransportMode(rawValue: record.mode) else {
                return nil
            }
            
            return SavedFavorite(
                mode: mode,
                routeID: record.route_id,
                routeName: record.route_name,
                directionID: record.direction_id,
                directionName: record.direction_name,
                directionDestination: record.direction_destination,
                stopID: record.stop_id,
                stopName: record.stop_name
            )
        }
        #else
        return []
        #endif
    }
    
    /// Delete a favorite from Supabase
    func deleteFavorite(routeID: String, stopID: String) async throws {
        #if canImport(Supabase)
        try await client.database
            .from("favorites")
            .delete()
            .eq("route_id", value: routeID)
            .eq("stop_id", value: stopID)
            .execute()
        #endif
    }
    
    // MARK: - API Usage Tracking
    
    /// Log API usage to Supabase for analytics
    /// You'll need to create an "api_logs" table in your Supabase dashboard
    func logAPIUsage(endpoint: String, source: String, statusCode: Int?) async throws {
        #if canImport(Supabase)
        struct APILogRecord: Encodable {
            let user_id: String?
            let endpoint: String
            let source: String
            let status_code: Int?
            let timestamp: Date
        }
        
        let record = APILogRecord(
            user_id: currentUser?.id.uuidString,
            endpoint: endpoint,
            source: source,
            status_code: statusCode,
            timestamp: Date()
        )
        
        try await client.database
            .from("api_logs")
            .insert(record)
            .execute()
        #endif
    }
    
    // MARK: - Real-time Subscriptions (Optional)
    
    /// Subscribe to changes in favorites table
    func subscribeFavoritesChanges(onChange: @escaping ([SavedFavorite]) -> Void) async throws {
        #if canImport(Supabase)
        // This would use Supabase Realtime to listen for changes
        // Implementation depends on your specific needs
        #endif
    }
}
