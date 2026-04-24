import SwiftUI
import Combine

/// Checks the App Store for a newer version and exposes the result as a published property.
@MainActor
final class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker()
    
    @Published var updateRequired = false
    @Published var latestVersion: String?
    
    private let appStoreID = "6761027252"
    private let cacheKey = "lastUpdateCheckDate"
    private let cacheInterval: TimeInterval = 3600 // 1 hour between checks
    
    private init() {}
    
    /// Call on app launch. Skips the network call if checked recently.
    func checkIfNeeded() {
        if let lastCheck = UserDefaults.standard.object(forKey: cacheKey) as? Date,
           Date().timeIntervalSince(lastCheck) < cacheInterval {
            return
        }
        
        Task {
            await check()
        }
    }
    
    private func check() async {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreID)&country=us") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            
            guard let storeVersion = response.results.first?.version else { return }
            
            UserDefaults.standard.set(Date(), forKey: cacheKey)
            latestVersion = storeVersion
            
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            
            if isVersion(currentVersion, olderThan: storeVersion) {
                updateRequired = true
            }
        } catch {
            // Silently fail — don't block the app if the check fails
        }
    }
    
    /// Semantic version comparison: returns true if `installed` < `store`.
    private func isVersion(_ installed: String, olderThan store: String) -> Bool {
        let installedParts = installed.split(separator: ".").compactMap { Int($0) }
        let storeParts = store.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(installedParts.count, storeParts.count)
        for i in 0..<maxCount {
            let a = i < installedParts.count ? installedParts[i] : 0
            let b = i < storeParts.count ? storeParts[i] : 0
            if a < b { return true }
            if a > b { return false }
        }
        return false
    }
    
    /// Dismisses the update prompt for this session.
    func dismiss() {
        updateRequired = false
    }
    
    /// Opens the App Store page for this app.
    func openAppStore() {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)") else { return }
        UIApplication.shared.open(url)
    }
}

private struct AppStoreLookupResponse: Codable {
    let resultCount: Int
    let results: [AppStoreResult]
}

private struct AppStoreResult: Codable {
    let version: String
}
