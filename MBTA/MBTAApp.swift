//
//  MBTAApp.swift
//  MBTA
//
//  Created by Puneet Ramini on 3/14/26.
//

import SwiftUI
import FirebaseCore
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // Request notification permission (needed for Live Activity push updates)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
        }
        application.registerForRemoteNotifications()
        
        return true
    }
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("APNs device token: \(deviceToken.map { String(format: "%02x", $0) }.joined())")
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}

@main
struct MBTAApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var updateChecker = AppUpdateChecker.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .onAppear {
                    updateChecker.checkIfNeeded()
                }
                .overlay {
                    if updateChecker.updateRequired {
                        UpdatePromptView()
                    }
                }
        }
    }
}

/// Overlay shown when a newer version is available on the App Store.
private struct UpdatePromptView: View {
    @ObservedObject var checker = AppUpdateChecker.shared
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("A new version is available")
                    .font(.system(size: 20, weight: .bold))
                
                Text("We've made improvements, fixed bugs, and updated a few things to make the app better. Please update when you can.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    AppUpdateChecker.shared.openAppStore()
                } label: {
                    Text("Update Now")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                Button {
                    checker.dismiss()
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
            }
            .padding(.horizontal, 32)
        }
    }
}
