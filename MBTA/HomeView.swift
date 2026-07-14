//
//  HomeView.swift
//  MBTA
//
//  Redesigned Home screen matching the dark-themed mockup.
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @State private var isEditingShortcuts = false
    @State private var navigateToSearch = false
    @State private var navigateToWidgets = false
    
    /// Callback to switch to Search tab and load a favorite
    var onOpenFavorite: ((SavedFavorite) -> Void)?
    /// Callback to switch to Search tab (explore routes)
    var onExploreRoutes: (() -> Void)?
    /// Callback to switch to Widgets tab
    var onOpenWidgets: (() -> Void)?
    /// Callback to switch to Alerts tab
    var onOpenAlerts: (() -> Void)?
    
    // MARK: - Pink accent color matching the mockup
    private let accentPink = Color(red: 232/255, green: 54/255, blue: 101/255)
    
    // MARK: - Card background matching dark theme
    private let cardBackground = Color(white: 0.12)
    private let cardBorder = Color(white: 0.20)
    
    private var savedFavoriteCount: Int {
        viewModel.quickFavorites.compactMap { $0 }.count
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                liveNowLabel
                exploreRoutesCard
                shortcutsSection
                widgetCTACard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 100) // space for tab bar
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            Task {
                await viewModel.loadShortcutArrivals()
            }
            // Load alerts so the bell badge is up-to-date
            if viewModel.allAlerts.isEmpty {
                Task { await viewModel.loadAlerts() }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(alignment: .top) {
            // Title: "MBTA" white, "Widgets" pink
            HStack(spacing: 8) {
                Text("MBTA")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("Widgets")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(accentPink)
            }
            
            Spacer()
            
            // Notification bell — pink dot only when favorite routes have alerts
            Button {
                onOpenAlerts?()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                    
                    if viewModel.favoriteAlertCount > 0 {
                        Circle()
                            .fill(accentPink)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .padding(.top, 6)
        }
    }
    
    // MARK: - Live Now Label
    
    private var liveNowLabel: some View {
        HStack(spacing: 8) {
            Text("Live Now")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            
            Circle()
                .fill(accentPink)
                .frame(width: 8, height: 8)
        }
    }
    
    // MARK: - Explore Routes Card
    
    private var exploreRoutesCard: some View {
        Button {
            onExploreRoutes?()
        } label: {
            ZStack(alignment: .leading) {
                // Background image shifted right so map is visible on right half
                GeometryReader { geo in
                    Image("RouteMapBackground")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(x: geo.size.width * 0.25) // push image to the right
                        .clipped()
                }
                
                // Dark gradient overlay for readability — heavier on left for text
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.92), location: 0),
                        .init(color: Color.black.opacity(0.6), location: 0.45),
                        .init(color: Color.black.opacity(0.2), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                
                // Content
                VStack(alignment: .leading, spacing: 12) {
                    Spacer()
                    
                    Text("Explore routes")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Find routes, stops,\nand stations")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .lineSpacing(2)
                    
                    Spacer()
                    
                    // Search-style button inside card
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(accentPink)
                        
                        Text("Explore routes")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .padding(20)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - My Shortcuts Section
    
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("My Shortcuts")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(isEditingShortcuts ? "Done" : "Edit") {
                    withAnimation(.spring(response: 0.3)) {
                        isEditingShortcuts.toggle()
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accentPink)
            }
            
            // Fixed 4-column grid — always 4 tiles per row, uniform size
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: 4
            )
            
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                    if let favorite = favorite {
                        shortcutCard(favorite: favorite, index: index)
                    }
                }
                
                // Add Shortcut card (only show if fewer than 4 favorites)
                if savedFavoriteCount < 4 {
                    addShortcutCard
                }
            }
        }
    }
    
    private func shortcutCard(favorite: SavedFavorite, index: Int) -> some View {
        Button {
            if isEditingShortcuts {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.removeFavorite(at: index)
                }
            } else {
                onOpenFavorite?(favorite)
            }
        } label: {
            let arrivals = viewModel.shortcutArrivals[favorite.id] ?? []
            
            VStack(alignment: .leading, spacing: 6) {
                // Route badge
                routeBadge(for: favorite)
                
                // Destination
                Text(shortcutDestination(for: favorite))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                
                Spacer(minLength: 0)
                
                // Primary arrival time — single line always
                Text(arrivals.first.flatMap({ $0.minutesAway }).map({ "\($0) min" }) ?? "-- min")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(arrivals.first?.minutesAway != nil ? .white : .white.opacity(0.4))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
                // Secondary arrival time
                Text(arrivals.dropFirst().first.flatMap({ $0.minutesAway }).map({ "\($0) min" }) ?? " ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 130)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isEditingShortcuts {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 18))
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func routeBadge(for favorite: SavedFavorite) -> some View {
        let routeID = favorite.routeID
        let bgColor = routeBadgeColor(for: routeID)
        let textColor = routeTextColor(for: routeID)
        let displayName = routeBadgeDisplayName(for: routeID, favorite: favorite)
        
        return Text(displayName)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(textColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(bgColor)
            )
    }
    
    private var addShortcutCard: some View {
        Button {
            onExploreRoutes?()
        } label: {
            VStack(spacing: 8) {
                Spacer()
                
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
                
                Text("Add\nShortcut")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(cardBorder, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Widget CTA Card
    
    private var widgetCTACard: some View {
        Button {
            onOpenWidgets?()
        } label: {
            HStack(spacing: 14) {
                // Grid icon matching mockup
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(accentPink)
                    .frame(width: 44, height: 44)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create Home Screen widgets")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Add your favorite routes and stops to your Home Screen")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private func shortcutDestination(for favorite: SavedFavorite) -> String {
        let dest = favorite.directionDestination
            .replacingOccurrences(of: " Station", with: "")
            .replacingOccurrences(of: " Square", with: " Sq")
        if !dest.isEmpty { return dest }
        return favorite.stopName
            .replacingOccurrences(of: " Station", with: "")
            .replacingOccurrences(of: " Square", with: " Sq")
    }
    
    /// Badge text: bus → route number, subway/rail → short destination
    private func routeBadgeDisplayName(for routeID: String, favorite: SavedFavorite) -> String {
        let route = routeID.uppercased()
        
        // Bus — show the route number/name (e.g. "CT2", "66", "39")
        if route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT") {
            return favorite.routeName
        }
        
        // Green Line branches — just the letter
        if route.contains("GREEN-B") { return "B" }
        if route.contains("GREEN-C") { return "C" }
        if route.contains("GREEN-D") { return "D" }
        if route.contains("GREEN-E") { return "E" }
        
        // Subway / Commuter Rail — show short destination
        let dest = favorite.directionDestination
            .replacingOccurrences(of: " Station", with: "")
            .replacingOccurrences(of: " Square", with: " Sq")
        if !dest.isEmpty { return dest }
        
        return favorite.routeName
    }
    
    private func routeBadgeColor(for routeID: String) -> Color {
        let route = routeID.uppercased()
        
        // Bus — yellow
        if route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT") {
            return Color(red: 255/255, green: 200/255, blue: 0/255)
        }
        if route.contains("RED") || route.contains("MATTAPAN") {
            return Color(red: 218/255, green: 41/255, blue: 28/255)
        }
        if route.contains("ORANGE") {
            return Color(red: 237/255, green: 139/255, blue: 0/255)
        }
        if route.contains("BLUE") {
            return Color(red: 0/255, green: 115/255, blue: 207/255)
        }
        if route.contains("GREEN") {
            return Color(red: 0/255, green: 132/255, blue: 61/255)
        }
        if route.starts(with: "CR-") {
            return .purple
        }
        return Color(red: 255/255, green: 200/255, blue: 0/255) // default yellow
    }
    
    private func routeTextColor(for routeID: String) -> Color {
        let route = routeID.uppercased()
        // Bus — black text on yellow
        if route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT") {
            return .black
        }
        return .white
    }
}

#Preview {
    HomeView(viewModel: ArrivalsViewModel())
        .preferredColorScheme(.dark)
}
