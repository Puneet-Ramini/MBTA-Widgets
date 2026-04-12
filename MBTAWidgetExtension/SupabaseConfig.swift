//
//  SupabaseConfig.swift
//  MBTA
//
//  Created on 4/8/26.
//

import Foundation

/// Configuration for Supabase client
enum SupabaseConfig {
    private static let projectURLKey = "SupabaseProjectURL"
    private static let publishableKeyKey = "SupabasePublishableKey"
    
    /// Returns the configured Supabase URL
    static var url: URL {
        guard
            let projectURL = Bundle.main.object(forInfoDictionaryKey: projectURLKey) as? String,
            !projectURL.isEmpty,
            let url = URL(string: projectURL)
        else {
            fatalError("Missing or invalid \(projectURLKey) in Info.plist")
        }
        return url
    }

    static var publishableKey: String {
        guard
            let publishableKey = Bundle.main.object(forInfoDictionaryKey: publishableKeyKey) as? String,
            !publishableKey.isEmpty,
            !publishableKey.contains("$(")
        else {
            fatalError("Missing \(publishableKeyKey) in Info.plist")
        }

        return publishableKey
    }
}
