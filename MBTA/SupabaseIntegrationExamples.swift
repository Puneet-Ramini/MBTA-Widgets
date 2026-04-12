//
//  SupabaseIntegrationExamples.swift
//  MBTA
//
//  Created on 4/8/26.
//

import Foundation

/*
 This file contains example code showing how to integrate Supabase
 with your existing ArrivalsViewModel and data layer.
 
 Copy these examples into your actual code files when ready.
 */

// MARK: - Example 1: Auto-sync favorites to cloud when saved

/*
 Add this to ArrivalsViewModel.swift in the saveFavorite(at:) method:
 
 func saveFavorite(at index: Int) {
     guard let route = selectedRoute,
           let directionID = selectedDirectionID,
           let stopID = selectedStopID,
           let stopName = selectedStop?.name else {
         return
     }
     
     let favorite = SavedFavorite(
         mode: selectedMode,
         routeID: route.id,
         routeName: route.shortName ?? route.id,
         directionID: directionID,
         directionName: route.directionName(for: directionID),
         directionDestination: route.directionDestination(for: directionID),
         stopID: stopID,
         stopName: stopName
     )
     
     // Save locally (existing code)
     quickFavorites[index] = favorite
     saveQuickFavorites()
     
     // NEW: Sync to Supabase cloud
     Task {
         do {
             try await SupabaseService.shared.saveFavorite(favorite)
             print("✅ Favorite synced to cloud")
         } catch {
             print("⚠️ Failed to sync favorite to cloud: \(error)")
             // Not critical - we still have local storage
         }
     }
 }
 */

// MARK: - Example 2: Load favorites from cloud on app launch

/*
 Add this to ArrivalsViewModel.swift as a new method:
 
 @MainActor
 func syncFavoritesFromCloud() async {
     // Only sync if user is authenticated
     guard SupabaseService.shared.isAuthenticated else {
         print("User not authenticated, skipping cloud sync")
         return
     }
     
     do {
         let cloudFavorites = try await SupabaseService.shared.fetchFavorites()
         
         if cloudFavorites.isEmpty {
             print("No cloud favorites found")
             return
         }
         
         // Strategy 1: Replace local with cloud (simple)
         // quickFavorites = [
         //     cloudFavorites.first,
         //     cloudFavorites.count > 1 ? cloudFavorites[1] : nil
         // ]
         
         // Strategy 2: Merge cloud and local (smarter)
         // Only update if cloud has favorites and local doesn't
         if quickFavorites[0] == nil && !cloudFavorites.isEmpty {
             quickFavorites[0] = cloudFavorites[0]
         }
         if quickFavorites[1] == nil && cloudFavorites.count > 1 {
             quickFavorites[1] = cloudFavorites[1]
         }
         
         saveQuickFavorites()
         print("✅ Synced \(cloudFavorites.count) favorites from cloud")
     } catch {
         print("⚠️ Failed to load cloud favorites: \(error)")
         // Not critical - continue with local favorites
     }
 }
 
 Then call this in the init() or onAppear:
 
 init() {
     loadQuickFavorites()
     
     Task {
         await syncFavoritesFromCloud()
     }
 }
 */

// MARK: - Example 3: Log API usage to Supabase

/*
 Modify MBTAService.swift to log API calls to Supabase:
 
 In the fetch<T: Decodable> method, after recording to local APIUsageStore:
 
 private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
     var didRecord = false

     do {
         let (data, response) = try await URLSession.shared.data(from: url)
         let statusCode = (response as? HTTPURLResponse)?.statusCode
         
         // Existing local logging
         APIUsageStore.record(url: url, statusCode: statusCode, source: "app")
         didRecord = true
         
         // NEW: Also log to Supabase (async, don't wait for it)
         Task {
             let endpoint = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
             try? await SupabaseService.shared.logAPIUsage(
                 endpoint: endpoint,
                 source: "app",
                 statusCode: statusCode
             )
         }

         guard let httpResponse = response as? HTTPURLResponse, 
               (200...299).contains(httpResponse.statusCode) else {
             throw URLError(.badServerResponse)
         }

         let decoder = JSONDecoder()
         decoder.dateDecodingStrategy = .iso8601
         return try decoder.decode(T.self, from: data)
     } catch {
         if !didRecord {
             APIUsageStore.record(url: url, statusCode: nil, source: "app")
             
             // NEW: Log errors too
             Task {
                 let endpoint = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                 try? await SupabaseService.shared.logAPIUsage(
                     endpoint: endpoint,
                     source: "app",
                     statusCode: nil
                 )
             }
         }
         throw error
     }
 }
 */

// MARK: - Example 4: Anonymous sign-in on app launch

/*
 Add this to MBTAApp.swift to automatically authenticate users:
 
 @main
 struct MBTAApp: App {
     @StateObject private var supabase = SupabaseService.shared
     
     var body: some Scene {
         WindowGroup {
             ContentView()
                 .preferredColorScheme(.light)
                 .task {
                     // Auto-authenticate on app launch
                     if !supabase.isAuthenticated {
                         try? await supabase.signInAnonymously()
                     }
                 }
         }
     }
 }
 */

// MARK: - Example 5: Create a user preferences model

/*
 You can store user preferences in Supabase too!
 
 First, create this table in Supabase:
 
 create table user_preferences (
   user_id uuid references auth.users primary key,
   preferred_mode text,
   theme text default 'light',
   notifications_enabled boolean default true,
   updated_at timestamp with time zone default timezone('utc'::text, now()) not null
 );

 alter table user_preferences enable row level security;

 create policy "Users can view their own preferences"
   on user_preferences for select
   using (auth.uid() = user_id);

 create policy "Users can update their own preferences"
   on user_preferences for all
   using (auth.uid() = user_id);
   
 Then add this to SupabaseService.swift:
 
 struct UserPreferences: Codable {
     let preferredMode: String?
     let theme: String
     let notificationsEnabled: Bool
 }
 
 func savePreferences(_ prefs: UserPreferences) async throws {
     struct PrefsRecord: Encodable {
         let user_id: String
         let preferred_mode: String?
         let theme: String
         let notifications_enabled: Bool
         let updated_at: Date
     }
     
     guard let userId = currentUser?.id.uuidString else {
         throw NSError(domain: "Auth", code: 401, userInfo: nil)
     }
     
     let record = PrefsRecord(
         user_id: userId,
         preferred_mode: prefs.preferredMode,
         theme: prefs.theme,
         notifications_enabled: prefs.notificationsEnabled,
         updated_at: Date()
     )
     
     try await client.database
         .from("user_preferences")
         .upsert(record)
         .execute()
 }
 
 func fetchPreferences() async throws -> UserPreferences? {
     struct PrefsRecord: Decodable {
         let preferred_mode: String?
         let theme: String
         let notifications_enabled: Bool
     }
     
     guard let userId = currentUser?.id.uuidString else {
         return nil
     }
     
     let records: [PrefsRecord] = try await client.database
         .from("user_preferences")
         .select()
         .eq("user_id", value: userId)
         .execute()
         .value
     
     guard let record = records.first else {
         return nil
     }
     
     return UserPreferences(
         preferredMode: record.preferred_mode,
         theme: record.theme,
         notificationsEnabled: record.notifications_enabled
     )
 }
 */

// MARK: - Example 6: Share favorites between users

/*
 Create a shared_favorites table:
 
 create table shared_favorites (
   id uuid primary key default uuid_generate_v4(),
   share_code text unique not null,
   created_by uuid references auth.users,
   mode text not null,
   route_id text not null,
   route_name text not null,
   direction_id integer not null,
   direction_name text not null,
   direction_destination text not null,
   stop_id text not null,
   stop_name text not null,
   created_at timestamp with time zone default timezone('utc'::text, now()) not null
 );

 alter table shared_favorites enable row level security;

 create policy "Anyone can view shared favorites"
   on shared_favorites for select
   using (true);

 create policy "Authenticated users can create shared favorites"
   on shared_favorites for insert
   with check (auth.uid() = created_by);
   
 Then add methods to SupabaseService.swift:
 
 func createSharedFavorite(_ favorite: SavedFavorite) async throws -> String {
     let shareCode = UUID().uuidString.prefix(8).uppercased()
     
     struct SharedRecord: Encodable {
         let share_code: String
         let created_by: String
         let mode: String
         let route_id: String
         let route_name: String
         let direction_id: Int
         let direction_name: String
         let direction_destination: String
         let stop_id: String
         let stop_name: String
     }
     
     guard let userId = currentUser?.id.uuidString else {
         throw NSError(domain: "Auth", code: 401)
     }
     
     let record = SharedRecord(
         share_code: String(shareCode),
         created_by: userId,
         mode: favorite.mode.rawValue,
         route_id: favorite.routeID,
         route_name: favorite.routeName,
         direction_id: favorite.directionID,
         direction_name: favorite.directionName,
         direction_destination: favorite.directionDestination,
         stop_id: favorite.stopID,
         stop_name: favorite.stopName
     )
     
     try await client.database
         .from("shared_favorites")
         .insert(record)
         .execute()
     
     return String(shareCode)
 }
 
 func loadSharedFavorite(shareCode: String) async throws -> SavedFavorite {
     struct SharedRecord: Decodable {
         let mode: String
         let route_id: String
         let route_name: String
         let direction_id: Int
         let direction_name: String
         let direction_destination: String
         let stop_id: String
         let stop_name: String
     }
     
     let records: [SharedRecord] = try await client.database
         .from("shared_favorites")
         .select()
         .eq("share_code", value: shareCode)
         .execute()
         .value
     
     guard let record = records.first,
           let mode = TransportMode(rawValue: record.mode) else {
         throw NSError(domain: "NotFound", code: 404)
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
 */
