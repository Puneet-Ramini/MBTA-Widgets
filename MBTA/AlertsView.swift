//
//  AlertsView.swift
//  MBTA
//
//  Alerts tab: favorites alerts at top, then all alerts grouped by mode.
//

import SwiftUI

struct AlertsView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @State private var expandedRouteID: String? = nil
    @State private var expandedAlertID: String? = nil
    
    private let accentPink = Color(red: 232/255, green: 54/255, blue: 101/255)
    private let cardBackground = Color(white: 0.12)
    private let cardBorder = Color(white: 0.20)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text("Alerts")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)
                
                // My Routes section
                myRoutesSection
                
                // All alerts grouped by mode
                if viewModel.isLoadingAlerts && viewModel.allAlerts.isEmpty {
                    loadingView
                } else if viewModel.allAlerts.isEmpty {
                    emptyView
                } else {
                    modeSection(title: "Bus", mode: .bus)
                    modeSection(title: "Subway", mode: .subway)
                    modeSection(title: "Commuter Rail", mode: .commuterRail)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Color.black.ignoresSafeArea())
        .refreshable {
            await viewModel.loadAlerts()
        }
        .onAppear {
            if viewModel.allAlerts.isEmpty {
                Task { await viewModel.loadAlerts() }
            }
        }
    }
    
    // MARK: - My Routes Section
    
    private var myRoutesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(accentPink)
                Text("My Routes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            let favoriteAlerts = alertsForFavorites()
            
            if favoriteAlerts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                    
                    Text(hasFavorites
                         ? "No active alerts for your saved routes"
                         : "Save shortcuts to see relevant alerts here")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(cardBorder, lineWidth: 1)
                        )
                )
            } else {
                ForEach(favoriteAlerts) { alert in
                    alertCard(alert)
                }
            }
        }
    }
    
    // MARK: - Mode Section
    
    @ViewBuilder
    private func modeSection(title: String, mode: TransportMode) -> some View {
        let routeGroups = alertsGroupedByRoute(for: mode)
        
        if !routeGroups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack(spacing: 8) {
                    Image(systemName: modeIcon(for: mode))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(modeColor(for: mode))
                    
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(routeGroups.count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.white.opacity(0.1))
                        )
                }
                
                // Route tiles
                ForEach(routeGroups, id: \.routeID) { group in
                    routeTile(group: group)
                }
            }
        }
    }
    
    // MARK: - Route Tile (tap to expand)
    
    private func routeTile(group: RouteAlertGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Route header — always visible
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expandedRouteID = expandedRouteID == group.routeID ? nil : group.routeID
                }
            } label: {
                HStack(spacing: 12) {
                    // Route badge
                    Text(group.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(group.textColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(group.badgeColor)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.routeName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text("\(group.alerts.count) alert\(group.alerts.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                        .rotationEffect(.degrees(expandedRouteID == group.routeID ? 90 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            
            // Expanded alert list
            if expandedRouteID == group.routeID {
                VStack(spacing: 8) {
                    ForEach(group.alerts) { alert in
                        alertCard(alert)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Alert Card
    
    private func alertCard(_ alert: MBTAAlert) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Effect pill + header
            HStack(alignment: .top, spacing: 8) {
                Text(effectLabel(alert.effect))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(effectColor(alert.effect))
                    )
                
                Text(alert.header)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(expandedAlertID == alert.id ? nil : 2)
                    .fixedSize(horizontal: false, vertical: expandedAlertID == alert.id)
            }
            
            // Tap to expand description
            if expandedAlertID == alert.id, !alert.description.isEmpty {
                Text(alert.description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                expandedAlertID = expandedAlertID == alert.id ? nil : alert.id
            }
        }
    }
    
    // MARK: - Loading / Empty
    
    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text("Loading alerts...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)
            
            Text("No active alerts")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            Text("All MBTA services are running normally")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Data Helpers
    
    private var hasFavorites: Bool {
        viewModel.quickFavorites.compactMap { $0 }.count > 0
    }
    
    private func alertsForFavorites() -> [MBTAAlert] {
        let favoriteRouteIDs = Set(viewModel.quickFavorites.compactMap { $0?.routeID })
        guard !favoriteRouteIDs.isEmpty else { return [] }
        return viewModel.allAlerts.filter { alert in
            alert.routeIDs.contains(where: { favoriteRouteIDs.contains($0) })
        }
    }
    
    private struct RouteAlertGroup {
        let routeID: String
        let routeName: String
        let displayName: String
        let badgeColor: Color
        let textColor: Color
        let alerts: [MBTAAlert]
    }
    
    private func alertsGroupedByRoute(for mode: TransportMode) -> [RouteAlertGroup] {
        // Collect all unique route IDs from alerts
        var routeAlertMap: [String: [MBTAAlert]] = [:]
        
        for alert in viewModel.allAlerts {
            for routeID in alert.routeIDs {
                if routeMatchesMode(routeID: routeID, mode: mode) {
                    routeAlertMap[routeID, default: []].append(alert)
                }
            }
        }
        
        return routeAlertMap.map { routeID, alerts in
            RouteAlertGroup(
                routeID: routeID,
                routeName: routeDisplayName(for: routeID),
                displayName: routeBadgeText(for: routeID),
                badgeColor: routeBadgeColor(for: routeID),
                textColor: routeTextColor(for: routeID),
                alerts: alerts
            )
        }
        .sorted { $0.routeName < $1.routeName }
    }
    
    private func routeMatchesMode(routeID: String, mode: TransportMode) -> Bool {
        let id = routeID.uppercased()
        switch mode {
        case .bus:
            return !id.starts(with: "CR-")
                && !id.contains("RED") && !id.contains("ORANGE")
                && !id.contains("BLUE") && !id.contains("GREEN")
                && !id.contains("MATTAPAN")
        case .subway:
            return id.contains("RED") || id.contains("ORANGE")
                || id.contains("BLUE") || id.contains("GREEN")
                || id.contains("MATTAPAN")
        case .commuterRail:
            return id.starts(with: "CR-")
        }
    }
    
    // MARK: - Display Helpers
    
    private func routeDisplayName(for routeID: String) -> String {
        let id = routeID.uppercased()
        if id.contains("RED") { return "Red Line" }
        if id.contains("ORANGE") { return "Orange Line" }
        if id.contains("BLUE") { return "Blue Line" }
        if id.contains("GREEN-B") { return "Green Line B" }
        if id.contains("GREEN-C") { return "Green Line C" }
        if id.contains("GREEN-D") { return "Green Line D" }
        if id.contains("GREEN-E") { return "Green Line E" }
        if id.contains("MATTAPAN") { return "Mattapan Line" }
        if id.starts(with: "CR-") {
            return routeID.replacingOccurrences(of: "CR-", with: "").replacingOccurrences(of: "-", with: "/")
        }
        return routeID
    }
    
    private func routeBadgeText(for routeID: String) -> String {
        let id = routeID.uppercased()
        if id.contains("GREEN-B") { return "B" }
        if id.contains("GREEN-C") { return "C" }
        if id.contains("GREEN-D") { return "D" }
        if id.contains("GREEN-E") { return "E" }
        if id.contains("RED") { return "RL" }
        if id.contains("ORANGE") { return "OL" }
        if id.contains("BLUE") { return "BL" }
        if id.contains("MATTAPAN") { return "M" }
        if id.starts(with: "CR-") { return "CR" }
        return routeID // Bus: show number
    }
    
    private func routeBadgeColor(for routeID: String) -> Color {
        let id = routeID.uppercased()
        if id.contains("RED") || id.contains("MATTAPAN") {
            return Color(red: 218/255, green: 41/255, blue: 28/255)
        }
        if id.contains("ORANGE") {
            return Color(red: 237/255, green: 139/255, blue: 0/255)
        }
        if id.contains("BLUE") {
            return Color(red: 0/255, green: 115/255, blue: 207/255)
        }
        if id.contains("GREEN") {
            return Color(red: 0/255, green: 132/255, blue: 61/255)
        }
        if id.starts(with: "CR-") { return .purple }
        // Bus — yellow
        return Color(red: 255/255, green: 200/255, blue: 0/255)
    }
    
    private func routeTextColor(for routeID: String) -> Color {
        let id = routeID.uppercased()
        if id.allSatisfy({ $0.isNumber }) || id.starts(with: "SL") || id.starts(with: "CT") {
            return .black
        }
        return .white
    }
    
    private func effectLabel(_ effect: String) -> String {
        switch effect.uppercased() {
        case "DELAY": return "DELAY"
        case "DETOUR": return "DETOUR"
        case "SUSPENSION": return "SUSPENDED"
        case "SHUTTLE": return "SHUTTLE"
        case "STATION_CLOSURE": return "CLOSED"
        case "STOP_CLOSURE": return "CLOSED"
        case "STATION_ISSUE": return "ISSUE"
        case "TRACK_CHANGE": return "TRACK"
        case "SCHEDULE_CHANGE": return "SCHEDULE"
        case "STOP_MOVE", "STOP_MOVED": return "MOVED"
        default: return effect.replacingOccurrences(of: "_", with: " ")
        }
    }
    
    private func effectColor(_ effect: String) -> Color {
        switch effect.uppercased() {
        case "DELAY": return Color(red: 237/255, green: 139/255, blue: 0/255) // orange
        case "SUSPENSION": return Color(red: 218/255, green: 41/255, blue: 28/255) // red
        case "SHUTTLE": return Color(red: 218/255, green: 41/255, blue: 28/255)
        case "STATION_CLOSURE", "STOP_CLOSURE": return Color(red: 218/255, green: 41/255, blue: 28/255)
        case "DETOUR": return Color(red: 180/255, green: 130/255, blue: 0/255) // amber
        default: return Color(white: 0.35)
        }
    }
    
    private func modeIcon(for mode: TransportMode) -> String {
        switch mode {
        case .bus: return "bus.fill"
        case .subway: return "tram.fill"
        case .commuterRail: return "train.side.front.car"
        }
    }
    
    private func modeColor(for mode: TransportMode) -> Color {
        switch mode {
        case .bus: return Color(red: 255/255, green: 200/255, blue: 0/255)
        case .subway: return accentPink
        case .commuterRail: return .purple
        }
    }
}
