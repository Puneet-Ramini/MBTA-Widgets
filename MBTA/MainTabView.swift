//
//  MainTabView.swift
//  MBTA
//
//  Root tab view with Home, Search, Widgets, Alerts, More tabs.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var viewModel = ArrivalsViewModel()
    @State private var selectedTab: Tab = .home
    @Environment(\.scenePhase) private var scenePhase
    
    private let accentPink = Color(red: 232/255, green: 54/255, blue: 101/255)
    
    enum Tab: String {
        case home, search, widgets, alerts, more
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        viewModel: viewModel,
                        onOpenFavorite: { favorite in
                            // Switch to Search tab and load the favorite
                            Task {
                                await viewModel.handleQuickRouteTap(
                                    at: viewModel.quickFavorites.firstIndex(where: {
                                        $0?.id == favorite.id
                                    }) ?? 0
                                )
                            }
                            selectedTab = .search
                        },
                        onExploreRoutes: {
                            selectedTab = .search
                        },
                        onOpenWidgets: {
                            selectedTab = .widgets
                        },
                        onOpenAlerts: {
                            selectedTab = .alerts
                        }
                    )
                    
                case .search:
                    ContentView(viewModel: viewModel)
                    
                case .widgets:
                    WidgetsView(viewModel: viewModel)
                    
                case .alerts:
                    AlertsView(viewModel: viewModel)
                    
                case .more:
                    MorePlaceholderView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom bottom tab bar
            customTabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.handleReturnToForeground()
                Task {
                    await viewModel.loadShortcutArrivals()
                }
            }
        }
        .onOpenURL { url in
            if url.scheme == "mbta-widget", url.host == "open" {
                selectedTab = .search
                Task {
                    await viewModel.loadFromWidget(url: url)
                }
            }
        }
    }
    
    // MARK: - Custom Tab Bar
    
    private var customTabBar: some View {
        HStack {
            tabBarItem(tab: .home, icon: "house.fill", label: "Home")
            Spacer()
            tabBarItem(tab: .search, icon: "magnifyingglass", label: "Search")
            Spacer()
            tabBarItem(tab: .widgets, icon: "square.grid.2x2", label: "Widgets")
            Spacer()
            tabBarItem(tab: .alerts, icon: "bell", label: "Alerts")
            Spacer()
            tabBarItem(tab: .more, icon: "ellipsis", label: "More")
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(
            Rectangle()
                .fill(Color(white: 0.08))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    private func tabBarItem(tab: Tab, icon: String, label: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(selectedTab == tab ? accentPink : Color.white.opacity(0.45))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Placeholder Views

private struct MorePlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color(white: 0.3))
                
                Text("More")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Coming soon")
                    .font(.system(size: 15))
                    .foregroundColor(Color(white: 0.5))
            }
        }
    }
}
