//
//  ContentView.swift
//  MBTA
//
//  Created by Puneet Ramini on 3/14/26.
//

import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

struct ContentView: View {
    @StateObject private var viewModel = ArrivalsViewModel()
    @State private var isShowingFavoritePicker = false
    @State private var isShowingWidgetCustomization = false
    @State private var isShowingAbout = false
    @Namespace private var glassNamespace
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                // Modern gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.96, blue: 0.98),
                        Color(red: 0.92, green: 0.94, blue: 0.97)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header with better typography
                        Text("MBTA Schedules")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.primary, .primary.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .padding(.top, -8)

                        quickRoutesSection
                        modeSection
                        routeSection
                        directionSection
                        stopSelectorSection
                        statusSection
                        resultsSection
                        widgetButton
                            .padding(.bottom, 8)
                        
                        supportButton
                            .padding(.bottom, 8)
                        
                        aboutButton
                            .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .refreshable {
                    await viewModel.loadArrivals()
                }
            }
            .onChange(of: viewModel.selectedStopID) { _, _ in
                viewModel.saveWidgetSelection()
                guard viewModel.selectedStopID != nil else {
                    return
                }

                Task {
                    await viewModel.loadArrivals()
                }
            }
            .confirmationDialog("Save to Favorite", isPresented: $isShowingFavoritePicker, titleVisibility: .visible) {
                ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                    Button(favorite?.buttonTitle ?? "Favorite \(index + 1)") {
                        viewModel.saveFavorite(at: index)
                    }
                }
            } message: {
                Text("Choose which quick button should store this bus, direction, and stop.")
            }
            .navigationDestination(isPresented: $isShowingWidgetCustomization) {
                WidgetCustomizationView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $isShowingAbout) {
                AboutView()
            }
            .onOpenURL { url in
                // Handle widget deep link
                if url.scheme == "mbta-widget", url.host == "open" {
                    Task {
                        await viewModel.loadFromWidget(url: url)
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Re-fetch arrivals when app returns to foreground
                    viewModel.handleReturnToForeground()
                }
            }
        }
    }

    private var quickRoutesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Access")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        Button {
                            Task {
                                await viewModel.handleQuickRouteTap(at: index)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if let favorite = favorite {
                                    Image(systemName: modeIcon(for: favorite.mode))
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                
                                Text(quickRouteLabel(for: favorite, index: index))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(isQuickRouteSelected(favorite) ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background {
                                if isQuickRouteSelected(favorite) {
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                } else {
                                    Color.white.opacity(0.7)
                                }
                            }
                            .clipShape(Capsule())
                            .shadow(color: isQuickRouteSelected(favorite) ? .blue.opacity(0.3) : .black.opacity(0.06), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        isShowingFavoritePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Add")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.7))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transport Mode")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Menu {
                ForEach(TransportMode.allCases) { mode in
                    Button {
                        viewModel.selectedMode = mode
                        viewModel.handleModeChange()
                    } label: {
                        HStack {
                            Image(systemName: modeIcon(for: mode))
                            Text(mode.rawValue)
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: modeIcon(for: viewModel.selectedMode))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text(viewModel.selectedMode.rawValue)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
                }
            }
        }
    }

    @ViewBuilder
    private var routeSection: some View {
        if viewModel.selectedMode == .bus {
            busInputSection
        } else {
            presetLineSection
        }
    }

    private var busInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.fieldTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField(viewModel.routePlaceholder, text: $viewModel.routeInput)
                .font(.system(size: 16, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
                }
                .onSubmit {
                    Task {
                        await viewModel.loadRoute()
                    }
                }
                .overlay(alignment: .trailing) {
                    if viewModel.isLoadingRoute {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.blue)
                            .padding(.trailing, 16)
                    }
                }
        }
    }

    private var presetLineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.fieldTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Menu {
                ForEach(viewModel.presetLines) { line in
                    Button {
                        viewModel.selectPresetLine(line)
                        if line.query != "Green" {
                            Task {
                                await viewModel.loadRoute()
                            }
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(lineColor(for: line.colorName))
                                .frame(width: 10, height: 10)
                            Text(line.title)
                        }
                    }
                }
            } label: {
                HStack {
                    HStack(spacing: 10) {
                        if let selectedLine = selectedPresetLine {
                            Circle()
                                .fill(lineColor(for: selectedLine.colorName))
                                .frame(width: 10, height: 10)
                        }

                        Text(selectedPresetLine?.title ?? viewModel.routePlaceholder)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(selectedPresetLine == nil ? .secondary : .primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
                }
                .overlay(alignment: .trailing) {
                    if viewModel.isLoadingRoute {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.blue)
                            .padding(.trailing, 16)
                    }
                }
            }

            if selectedPresetLine?.query == "Green" {
                HStack(spacing: 10) {
                    ForEach(viewModel.greenLineBranches) { branch in
                        Button(branch.title) {
                            viewModel.selectGreenBranch(branch)
                            Task {
                                await viewModel.loadRoute()
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.selectedPresetLineQuery == branch.query ? .white : .green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            viewModel.selectedPresetLineQuery == branch.query
                            ? LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.green.opacity(0.1), Color.green.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(
                            color: viewModel.selectedPresetLineQuery == branch.query ? .green.opacity(0.3) : .clear,
                            radius: 8,
                            y: 4
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var directionSection: some View {
        if !viewModel.directions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Direction")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Picker("Direction", selection: $viewModel.selectedDirectionID) {
                    ForEach(viewModel.directions) { direction in
                        Text(directionSegmentTitle(for: direction)).tag(Optional(direction.id))
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedDirectionID) { _, newValue in
                    guard let directionID = newValue else {
                        return
                    }

                    Task {
                        await viewModel.selectDirection(directionID)
                    }
                }
                .disabled(viewModel.isLoadingStops)
            }
        }
    }

    private var stopSelectorSection: some View {
        Menu {
            ForEach(viewModel.stops) { stop in
                Button(stop.name) {
                    viewModel.selectedStopID = stop.id
                    viewModel.saveWidgetSelection()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(viewModel.selectedStop == nil ? .secondary : .blue)
                    
                    Text(viewModel.selectedStop?.name ?? "Select a \(viewModel.stopTitle.lowercased())")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(viewModel.selectedStop == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
                }
            }
        }
        .disabled(viewModel.selectedDirectionID == nil || viewModel.isLoadingStops || viewModel.stops.isEmpty)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let message = viewModel.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if viewModel.arrivals.isEmpty && !viewModel.isLoadingArrivals {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: modeIconForResults)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)

                    Text(resultsTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        Task {
                            await viewModel.loadArrivals()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(8)
                            .background {
                                Circle()
                                    .fill(.white.opacity(0.9))
                                    .shadow(color: .blue.opacity(0.2), radius: 6, y: 3)
                            }
                    }
                    .disabled(viewModel.isLoadingArrivals)
                    .rotationEffect(.degrees(viewModel.isLoadingArrivals ? 360 : 0))
                    .animation(
                        viewModel.isLoadingArrivals ? 
                            .linear(duration: 1).repeatForever(autoreverses: false) : 
                            .default,
                        value: viewModel.isLoadingArrivals
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    ForEach(displayedArrivals) { arrival in
                        VStack(spacing: 6) {
                            VStack(spacing: 4) {
                                Text(arrival.minutesAway.map { "\($0)" } ?? "--")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: arrival.minutesAway != nil ? [.blue, .blue.opacity(0.8)] : [.gray, .gray.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                Text("min")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                            }

                            VStack(spacing: 2) {
                                if let stopsText = stopsAwayText(for: arrival.stopsAway) {
                                    Text(stopsText)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text(" ")
                                        .font(.system(size: 11, weight: .medium))
                                }

                                Text(arrivalTimeText(for: arrival))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                
                if !viewModel.arrivals.isEmpty {
                    Button {
                        if viewModel.currentActivity != nil {
                            viewModel.stopLiveActivity()
                        } else {
                            viewModel.startLiveActivity()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            // Realistic Dynamic Island pill shape preview
                            ZStack {
                                // Main pill background
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 95, height: 22)
                                
                                HStack {
                                    // Route badge on left - now uses proper route colors
                                    let routeName = viewModel.selectedRoute?.id ?? "39"
                                    Text(routeName.displayRouteName)
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(routeName.routeTextColor)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(routeName.routeBadgeColor)
                                        )
                                        .padding(.leading, 4)
                                    
                                    Spacer()
                                    
                                    // Countdown on right
                                    if let minutesAway = viewModel.arrivals.first?.minutesAway {
                                        HStack(spacing: 2) {
                                            Text("\(minutesAway)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white)
                                            Text("m")
                                                .font(.system(size: 7, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.9))
                                        }
                                        .padding(.trailing, 6)
                                    }
                                }
                                .frame(width: 95)
                                
                                // Camera and Face ID sensor in middle
                                HStack(spacing: 6) {
                                    // Face ID sensor (left)
                                    Circle()
                                        .fill(.black.opacity(0.95))
                                        .frame(width: 3, height: 3)
                                        .overlay(
                                            Circle()
                                                .stroke(.white.opacity(0.1), lineWidth: 0.3)
                                        )
                                    
                                    // Camera lens (right, slightly larger)
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: [.gray.opacity(0.3), .black.opacity(0.8)],
                                                center: .center,
                                                startRadius: 0.5,
                                                endRadius: 2.5
                                            )
                                        )
                                        .frame(width: 4, height: 4)
                                        .overlay(
                                            Circle()
                                                .stroke(.white.opacity(0.15), lineWidth: 0.3)
                                        )
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.currentActivity != nil ? "Hide from Island" : "Show on Island")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text(viewModel.currentActivity != nil ? "Remove from screen" : "Live countdown on screen")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Image(systemName: viewModel.currentActivity != nil ? "xmark.circle.fill" : "arrow.right.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(viewModel.currentActivity != nil ? .red : .blue)
                        }
                        .padding(14)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
                        }
                    }
                }
            }
        }
    }

    private var widgetButton: some View {
        Button {
            isShowingWidgetCustomization = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)

                Text("Customize Widget")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
            }
        }
    }
    
    private var supportButton: some View {
        Button {
            if let url = URL(string: "https://www.buymeacoffee.com/puneetramini") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                Text("🚇")
                    .font(.system(size: 18))

                Text("Buy me a subway ride")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
            }
        }
    }
    
    private var aboutButton: some View {
        Button {
            isShowingAbout = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.purple)

                Text("About & Feedback")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
            }
        }
    }

    private func quickRouteLabel(for favorite: SavedFavorite?, index: Int) -> String {
        guard let favorite else {
            return "Empty"
        }

        // Shorten display for compact view
        var displayRoute = favorite.routeID
        
        // For green line branches, show just the letter
        if displayRoute.hasPrefix("Green-") {
            displayRoute = displayRoute.replacingOccurrences(of: "Green-", with: "")
        }
        
        return "\(displayRoute) \(directionSymbol(for: favorite.directionID))"
    }

    private func isQuickRouteSelected(_ favorite: SavedFavorite?) -> Bool {
        guard let favorite,
              favorite.routeID == viewModel.selectedRoute?.id,
              favorite.directionID == viewModel.selectedDirectionID,
              favorite.stopID == viewModel.selectedStopID else {
            return false
        }

        return true
    }

    private func directionSegmentTitle(for direction: RouteDirection) -> String {
        if !direction.destination.isEmpty {
            return shortDestination(direction.destination)
        }

        return direction.name
    }

    private func directionSymbol(for directionID: Int) -> String {
        switch directionID {
        case 0:
            return ">"
        case 1:
            return "<"
        default:
            return ">"
        }
    }
    
    private func modeIcon(for mode: TransportMode) -> String {
        switch mode {
        case .bus:
            return "bus.fill"
        case .subway:
            return "tram.fill"
        case .commuterRail:
            return "train.side.front.car"
        }
    }
    
    private var modeIconForResults: String {
        modeIcon(for: viewModel.selectedMode)
    }

    private var resultsTitle: String {
        let routeName = viewModel.selectedRoute?.displayName ?? viewModel.routeInput
        let destination = selectedDirectionDestination

        if destination.isEmpty {
            return titlePrefix + routeName
        }

        return titlePrefix + "\(routeName) → \(shortDestination(destination))"
    }

    private var selectedDirectionDestination: String {
        guard let directionID = viewModel.selectedDirectionID,
              let direction = viewModel.directions.first(where: { $0.id == directionID }) else {
            return ""
        }

        return direction.destination
    }

    private func shortDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: " Station", with: "")
            .replacingOccurrences(of: " station", with: "")
    }

    private var displayedArrivals: [BusArrival] {
        let placeholders = Array(repeating: placeholderArrival, count: max(3 - viewModel.arrivals.count, 0))
        return Array(viewModel.arrivals.prefix(3)) + placeholders
    }

    private var selectedPresetLine: PresetLine? {
        if let query = viewModel.selectedPresetLineQuery {
            if viewModel.greenLineBranches.contains(where: { $0.query == query }) {
                return PresetLine(title: "Green Line", query: "Green", colorName: "green")
            }

            return viewModel.presetLines.first(where: { $0.query == query })
        }

        return nil
    }

    private var placeholderArrival: BusArrival {
        BusArrival(
            id: UUID().uuidString,
            routeId: "",
            routeName: "",
            stopId: "",
            stopName: "",
            arrivalTime: nil,
            departureTime: nil,
            minutesAway: nil,
            stopsAway: nil,
            directionId: nil,
            status: nil
        )
    }

    private var titlePrefix: String {
        switch viewModel.selectedMode {
        case .bus:
            return "Route "
        case .subway, .commuterRail:
            return ""
        }
    }

    private func stopsAwayText(for stopsAway: Int?) -> String? {
        guard viewModel.selectedMode.showsStopsAway else {
            return nil
        }

        guard let stopsAway else {
            return nil
        }

        if stopsAway == 1 {
            return "1 stop away"
        }

        return "\(stopsAway) stops away"
    }

    private func arrivalTimeText(for arrival: BusArrival) -> String {
        guard let date = arrival.arrivalTime ?? arrival.departureTime else {
            return "Arrives --"
        }

        return "Arrives \(formattedTime(date))"
    }

    private func lineColor(for colorName: String) -> Color {
        switch colorName {
        case "red":
            return .red
        case "orange":
            return .orange
        case "blue":
            return .blue
        case "green":
            return .green
        case "purple":
            return .purple
        default:
            return .gray
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date).lowercased()
    }
}

private struct WidgetCustomizationView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @State private var editingDefault = false
    @State private var expandedOverrideID: String? = nil
    @State private var isShowingInstructions = false
    @State private var mediumWidgetFavoriteIndex: Int? = nil
    @State private var smallWidget1FavoriteIndex: Int? = nil
    @State private var smallWidget2FavoriteIndex: Int? = nil

    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.92, green: 0.94, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    defaultWidgetSection
                    timeOverrideSection
                    widgetAssignmentSection
                    instructionsSection
                    betaSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Customize Widget")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadWidgetAssignments()
        }
    }
    
    private func loadWidgetAssignments() {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA") else { return }
        
        mediumWidgetFavoriteIndex = defaults.object(forKey: "mediumWidgetFavoriteIndex") as? Int
        smallWidget1FavoriteIndex = defaults.object(forKey: "smallWidget1FavoriteIndex") as? Int
        smallWidget2FavoriteIndex = defaults.object(forKey: "smallWidget2FavoriteIndex") as? Int
    }
    
    private func saveWidgetAssignments() {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA") else { return }
        
        if let index = mediumWidgetFavoriteIndex {
            defaults.set(index, forKey: "mediumWidgetFavoriteIndex")
        } else {
            defaults.removeObject(forKey: "mediumWidgetFavoriteIndex")
        }
        
        if let index = smallWidget1FavoriteIndex {
            defaults.set(index, forKey: "smallWidget1FavoriteIndex")
        } else {
            defaults.removeObject(forKey: "smallWidget1FavoriteIndex")
        }
        
        if let index = smallWidget2FavoriteIndex {
            defaults.set(index, forKey: "smallWidget2FavoriteIndex")
        } else {
            defaults.removeObject(forKey: "smallWidget2FavoriteIndex")
        }
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private var defaultWidgetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Widget")
                        .font(.system(size: 20, weight: .bold))
                    
                    Text("All Day")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()

                Button(editingDefault ? "Done" : "Edit") {
                    withAnimation(.spring(response: 0.3)) {
                        editingDefault.toggle()
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.blue)
            }

            Text("This route shows all day unless a time override is active.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)

            Text(favoriteSummary(viewModel.widgetDefaultFavorite))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(viewModel.widgetDefaultFavorite == nil ? .secondary : .primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                }

            if editingDefault {
                favoriteSelectionList { favorite in
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.updateWidgetDefaultFavorite(favorite)
                        editingDefault = false
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.06), radius: 15, y: 8)
        }
    }

    private var timeOverrideSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time Overrides")
                    .font(.system(size: 20, weight: .bold))
                
                Text("Schedule Specific")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            Text("When the current time falls inside one of these ranges, the widget shows that route instead of the default route.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)

            ForEach(viewModel.widgetOverrides) { override in
                overrideCard(override)
            }

            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.addWidgetOverride()
                    expandedOverrideID = viewModel.widgetOverrides.last?.id
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Add Time Override")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.06), radius: 15, y: 8)
        }
    }

    private func overrideCard(_ override: WidgetScheduleOverride) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(favoriteSummary(override.favorite))
                        .font(.system(size: 16, weight: .semibold))

                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                        
                        Text("\(timeText(hour: override.startHour, minute: override.startMinute)) – \(timeText(hour: override.endHour, minute: override.endMinute))")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(expandedOverrideID == override.id ? "Done" : "Edit") {
                        withAnimation(.spring(response: 0.3)) {
                            expandedOverrideID = expandedOverrideID == override.id ? nil : override.id
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.blue)

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.deleteWidgetOverride(id: override.id)
                            if expandedOverrideID == override.id {
                                expandedOverrideID = nil
                            }
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.red)
                    }
                }
            }

            if expandedOverrideID == override.id {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                    
                    favoriteSelectionList { favorite in
                        viewModel.updateWidgetOverrideFavorite(id: override.id, favorite: favorite)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Start Time")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        DatePicker(
                            "Start Time",
                            selection: startTimeBinding(for: override),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.8))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("End Time")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        DatePicker(
                            "End Time",
                            selection: endTimeBinding(for: override),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.8))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isShowingInstructions.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                    
                    Text("How to Add a Widget")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isShowingInstructions ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isShowingInstructions {
                VStack(alignment: .leading, spacing: 10) {
                    instructionStep(number: 1, text: "Long press anywhere on your home screen")
                    instructionStep(number: 2, text: "Tap Edit")
                    instructionStep(number: 3, text: "Tap Add Widget")
                    instructionStep(number: 4, text: "Search MBTA Widget")
                    instructionStep(number: 5, text: "Select the second long tile widget")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .font(.subheadline)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.06), radius: 15, y: 8)
        }
    }
    
    private var widgetAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Widget Assignments")
                    .font(.system(size: 20, weight: .bold))
                
                Text("Link Widgets to Favorites")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            
            Text("Choose which quick access favorite each widget should display.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            
            // Medium Widget Assignment
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "rectangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    Text("Medium Widget")
                        .font(.system(size: 16, weight: .semibold))
                }
                
                Menu {
                    Button("None") {
                        mediumWidgetFavoriteIndex = nil
                        saveWidgetAssignments()
                    }
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        if favorite != nil {
                            Button(favoriteSummary(favorite) ?? "Favorite \(index + 1)") {
                                mediumWidgetFavoriteIndex = index
                                saveWidgetAssignments()
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedFavoriteLabel(mediumWidgetFavoriteIndex))
                            .font(.system(size: 15))
                            .foregroundColor(mediumWidgetFavoriteIndex == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.9))
                    }
                }
            }
            
            // Small Widget 1 Assignment
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "square.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text("Small Widget 1")
                        .font(.system(size: 16, weight: .semibold))
                }
                
                Menu {
                    Button("None") {
                        smallWidget1FavoriteIndex = nil
                        saveWidgetAssignments()
                    }
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        if favorite != nil {
                            Button(favoriteSummary(favorite) ?? "Favorite \(index + 1)") {
                                smallWidget1FavoriteIndex = index
                                saveWidgetAssignments()
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedFavoriteLabel(smallWidget1FavoriteIndex))
                            .font(.system(size: 15))
                            .foregroundColor(smallWidget1FavoriteIndex == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.9))
                    }
                }
            }
            
            // Small Widget 2 Assignment
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "square.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text("Small Widget 2")
                        .font(.system(size: 16, weight: .semibold))
                }
                
                Menu {
                    Button("None") {
                        smallWidget2FavoriteIndex = nil
                        saveWidgetAssignments()
                    }
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        if favorite != nil {
                            Button(favoriteSummary(favorite) ?? "Favorite \(index + 1)") {
                                smallWidget2FavoriteIndex = index
                                saveWidgetAssignments()
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedFavoriteLabel(smallWidget2FavoriteIndex))
                            .font(.system(size: 15))
                            .foregroundColor(smallWidget2FavoriteIndex == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.9))
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.06), radius: 15, y: 8)
        }
    }
    
    private func selectedFavoriteLabel(_ index: Int?) -> String {
        guard let index = index,
              viewModel.quickFavorites.indices.contains(index),
              let favorite = viewModel.quickFavorites[index] else {
            return "Select favorite"
        }
        return favoriteSummary(favorite) ?? "Favorite \(index + 1)"
    }

    private var betaSection: some View {
        Text("This is a beta version and we’d love to hear your feedback or feature ideas.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.06), radius: 15, y: 8)
            }
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.primary)
        }
    }

    private func favoriteSelectionList(action: @escaping (SavedFavorite?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { _, favorite in
                Button {
                    action(favorite)
                } label: {
                    HStack {
                        Text(favoriteSummary(favorite))
                            .foregroundColor(favorite == nil ? .secondary : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(favorite == nil)
            }
        }
    }

    private func favoriteSummary(_ favorite: SavedFavorite?) -> String {
        guard let favorite else {
            return "Choose a saved favorite"
        }

        let destination = favorite.directionDestination.isEmpty ? favorite.directionName : favorite.directionDestination
        return "\(favorite.routeName) • \(destination) • \(favorite.stopName)"
    }

    private func startTimeBinding(for override: WidgetScheduleOverride) -> Binding<Date> {
        Binding(
            get: { date(hour: override.startHour, minute: override.startMinute) },
            set: { viewModel.updateWidgetOverrideStart(id: override.id, date: $0) }
        )
    }

    private func endTimeBinding(for override: WidgetScheduleOverride) -> Binding<Date> {
        Binding(
            get: { date(hour: override.endHour, minute: override.endMinute) },
            set: { viewModel.updateWidgetOverrideEnd(id: override.id, date: $0) }
        )
    }

    private func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func timeText(hour: Int, minute: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date(hour: hour, minute: minute))
    }
}

private struct AboutView: View {
    @State private var isShowingWhatItDoes = false
    @State private var isShowingAboutApp = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.92, green: 0.94, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // What the app does button
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                isShowingWhatItDoes.toggle()
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "list.bullet.clipboard")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.blue)
                                
                                Text("What the app does")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .rotationEffect(.degrees(isShowingWhatItDoes ? 90 : 0))
                            }
                            .padding(18)
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.8))
                                    .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if isShowingWhatItDoes {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• Real-time MBTA arrivals for buses, trains, and subway lines")
                                Text("• Home Screen widgets for quick access")
                                Text("• Lock Screen and Live Activity support with Dynamic Island updates")
                                Text("• Live previews so you can see exactly how your widget will look")
                                Text("• Save your favorite routes and stops")
                                Text("• Time-based widgets that change throughout the day")
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            
                            Text("Why it exists:")
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.top, 8)
                            
                            Text("This app is designed for commuters who want fast, reliable information with zero friction. No clutter, no extra steps — just the data you need.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            
                            Text("Data source:")
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.top, 8)
                            
                            Text("All transit data is provided by the official MBTA public API.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(isShowingWhatItDoes ? 18 : 0)
                    .background {
                        if isShowingWhatItDoes {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    
                    // About this app button
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                isShowingAboutApp.toggle()
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.green)
                                
                                Text("About this app")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .rotationEffect(.degrees(isShowingAboutApp ? 90 : 0))
                            }
                            .padding(18)
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.8))
                                    .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if isShowingAboutApp {
                            Text("MBTA Widgets is built to make your daily commute easier by showing real-time bus and train arrivals directly on your iPhone without needing to open an app. Just glance at your Home Screen, Lock Screen, or Dynamic Island and instantly know when your next ride is coming.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(isShowingAboutApp ? 18 : 0)
                    .background {
                        if isShowingAboutApp {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    
                    Button {
                        if let url = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSetMU7XgiDaOgMJXtlMQVteH796sDNcNeviN-cikIC2CuRFAA/viewform?usp=header") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.blue)

                            Text("Share Feedback")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(18)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                        }
                    }
                    
                    NavigationLink(destination: PrivacyPolicyView()) {
                        HStack(spacing: 14) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.purple)

                            Text("Privacy Policy")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(18)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                        }
                    }
                    
                    Button {
                        if let url = URL(string: "https://www.buymeacoffee.com/puneetramini") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Text("🚇")
                                .font(.system(size: 18))

                            Text("Buy me a subway ride")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(18)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.92, green: 0.94, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Effective Date: 04/11/2026")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text("MBTA Widgets respects your privacy. This Privacy Policy explains how we collect, use, and protect information when you use the app.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                    
                    privacySection(
                        title: "1. Information We Collect",
                        content: "We collect limited, non-personal, anonymous data to improve app performance and reliability.\n\nThis includes:\n• A randomly generated anonymous device identifier (UUID)\n• MBTA usage data (such as routes, stops, and directions viewed)\n• API performance data (response times, success/failure rates)\n• App usage timestamps\n• Widget refresh activity"
                    )
                    
                    privacySection(
                        title: "2. Information We Do NOT Collect",
                        content: "We do not collect:\n• Name, email, or phone number\n• Location data\n• IP address\n• Payment information\n• Contacts, photos, or files\n• Any data that directly identifies you"
                    )
                    
                    privacySection(
                        title: "3. How We Use Information",
                        content: "We use collected data to:\n• Monitor MBTA API performance and reliability\n• Identify and fix bugs\n• Improve app speed and stability\n• Understand general usage patterns (e.g., commonly used routes)"
                    )
                    
                    privacySection(
                        title: "4. Data Storage and Processing",
                        content: "• Data is stored securely using Supabase (cloud database provider)\n• The device identifier is anonymous and cannot be linked to your identity\n• Data is not sold, rented, or shared for marketing purposes\n• Data is processed solely to operate and improve the app"
                    )
                    
                    privacySection(
                        title: "5. Legal Basis for Processing",
                        content: "We process anonymous usage data based on our legitimate interest in improving app functionality, performance, and user experience."
                    )
                    
                    privacySection(
                        title: "6. User Rights",
                        content: "• No account is required to use the app\n• Data collection is anonymous\n• You can stop all data collection by uninstalling the app\n• Because data is anonymous, we cannot reasonably link it to an individual user"
                    )
                    
                    privacySection(
                        title: "7. Data Retention",
                        content: "• Anonymous usage data is retained for analytics and performance monitoring\n• No personally identifiable data is stored"
                    )
                    
                    privacySection(
                        title: "8. Security",
                        content: "We use industry-standard security measures to protect stored data from unauthorized access, misuse, or disclosure."
                    )
                    
                    privacySection(
                        title: "9. Third-Party Services",
                        content: "We use the following external services:\n\n• MBTA API (https://api-v3.mbta.com)\nProvides real-time transit data, including arrival predictions, routes, and stop information\n\n• Supabase\nUsed for secure data storage and analytics\n\n• Google Forms\nUsed for optional user feedback submission\n\n• Buy Me a Coffee\nUsed for optional user support and donations"
                    )
                    
                    privacySection(
                        title: "10. Children's Privacy",
                        content: "This app is not directed to children under the age of 13. We do not knowingly collect any personal data from children."
                    )
                    
                    privacySection(
                        title: "11. Changes to This Policy",
                        content: "We may update this Privacy Policy from time to time. Updates will be reflected by revising the effective date."
                    )
                    
                    privacySection(
                        title: "12. Contact",
                        content: "If you have any questions about this Privacy Policy, contact:\nRamini.p@northeastern.edu"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func privacySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            
            Text(content)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.8))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }
}

// MARK: - String Extensions for Route Colors
private extension String {
    var routeBadgeColor: Color {
        let route = self.uppercased()
        
        // Bus - Yellow
        if route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT") {
            return .yellow
        }
        
        // Subway lines
        if route.contains("RED") {
            return Color(red: 218/255, green: 41/255, blue: 28/255) // MBTA Red
        } else if route.contains("ORANGE") {
            return Color(red: 237/255, green: 139/255, blue: 0/255) // MBTA Orange
        } else if route.contains("BLUE") {
            return Color(red: 0/255, green: 115/255, blue: 207/255) // MBTA Blue
        } else if route.contains("GREEN") || route == "B" || route == "C" || route == "D" || route == "E" {
            return Color(red: 0/255, green: 132/255, blue: 61/255) // MBTA Green
        } else if route.contains("MATTAPAN") {
            return Color(red: 218/255, green: 41/255, blue: 28/255)
        }
        
        return .gray
    }
    
    var routeTextColor: Color {
        let route = self.uppercased()
        
        // Bus routes - black text on yellow
        if route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT") {
            return .black
        }
        
        // All subway lines - white text
        return .white
    }
    
    var displayRouteName: String {
        let route = self.uppercased()
        
        // Subway lines show abbreviation
        if route.contains("RED") {
            return "RL"
        } else if route.contains("ORANGE") {
            return "OL"
        } else if route.contains("BLUE") {
            return "BL"
        } else if route.contains("GREEN") && !route.contains("-") {
            return "GL"
        } else if route.contains("GREEN-B") || route == "B" {
            return "B"
        } else if route.contains("GREEN-C") || route == "C" {
            return "C"
        } else if route.contains("GREEN-D") || route == "D" {
            return "D"
        } else if route.contains("GREEN-E") || route == "E" {
            return "E"
        }
        
        return self
    }
}

#Preview {
    ContentView()
}
