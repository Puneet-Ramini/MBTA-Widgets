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

// MARK: - Liquid Glass helper (iOS 26+)
extension View {
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                )
        }
    }
    
    @ViewBuilder
    func liquidGlassPill() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive())
        } else {
            self
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }
    }
}

// MARK: - Recent Search Model

struct RecentSearch: Codable, Identifiable, Equatable {
    let routeID: String
    let routeName: String
    let mode: TransportMode
    let directionID: Int
    let directionDestination: String
    let stopID: String
    let stopName: String

    var id: String { "\(routeID)-\(directionID)-\(stopID)" }
}

struct ContentView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @State private var isShowingFavoritePicker = false
    @State private var isShowingWidgetCustomization = false
    @State private var isShowingWidgetAssignment = false
    @State private var isShowingAbout = false
    @State private var isPickingPrediction = false
    @State private var selectedPredictionArrivalTime: Date? = nil
    @State private var showIslandHint = false
    @State private var isLanding = true
    @State private var recentSearches: [RecentSearch] = []
    @State private var isShowingBusRoutes = false
    @State private var isShowingSubwayLines = false
    @State private var isShowingCommuterRailLines = false
    @State private var isShowingRouteAlerts = false
    @Environment(\.scenePhase) private var scenePhase

    private var showRouteDetails: Bool {
        !isLanding && viewModel.selectedRoute != nil && !viewModel.directions.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background: gradient for route details, solid black otherwise
                if showRouteDetails {
                    LinearGradient(
                        stops: [
                            .init(color: routeAccentColor.opacity(0.35), location: 0),
                            .init(color: routeAccentColor.opacity(0.15), location: 0.35),
                            .init(color: Color.black, location: 0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                } else {
                    Color.black
                        .ignoresSafeArea()
                }
                
                ScrollView(showsIndicators: false) {
                    if isLanding {
                        landingContent
                    } else {
                        activeSearchContent
                    }
                }
                .refreshable {
                    guard !isPickingPrediction else { return }
                    await viewModel.loadArrivals()
                }
                .scrollDisabled(isPickingPrediction)
                .onAppear {
                    loadRecentSearches()
                    if viewModel.selectedRoute != nil || !viewModel.routeInput.isEmpty {
                        isLanding = false
                    }
                }
                .onChange(of: viewModel.routeInput) { _, newInput in
                    if !newInput.isEmpty {
                        isLanding = false
                    }
                }
                

            }
            .onChange(of: viewModel.selectedStopID) { _, _ in
                viewModel.saveWidgetSelection()
                selectedPredictionArrivalTime = nil
                isPickingPrediction = false
                guard viewModel.selectedStopID != nil else {
                    return
                }

                saveRecentSearch()

                Task {
                    await viewModel.loadArrivals()
                }
            }
            .onChange(of: viewModel.currentActivity == nil) { _, isNil in
                if isNil {
                    selectedPredictionArrivalTime = nil
                }
            }
            .confirmationDialog("Save to Favorite", isPresented: $isShowingFavoritePicker, titleVisibility: .visible) {
                ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                    Button(favorite?.buttonTitle ?? "Favorite \(index + 1)") {
                        viewModel.saveFavorite(at: index)
                    }
                }
            } message: {
                Text("Choose which quick button should store this route, direction, and stop.")
            }
            .navigationDestination(isPresented: $isShowingWidgetCustomization) {
                WidgetCustomizationView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $isShowingAbout) {
                AboutView()
            }
            .navigationDestination(isPresented: $isShowingBusRoutes) {
                BusRoutesView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $isShowingSubwayLines) {
                SubwayLinesView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $isShowingCommuterRailLines) {
                CommuterRailLinesView(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingWidgetAssignment) {
                WidgetAssignmentSheet(viewModel: viewModel)
                    .presentationDetents([.large])
                    .presentationBackground(Color.black)
                    .presentationCornerRadius(24)
            }
            .sheet(isPresented: $isShowingRouteAlerts) {
                NavigationStack {
                    List {
                        if routeAlerts.isEmpty {
                            Text("No active alerts for this route.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(routeAlerts) { alert in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(alert.header)
                                        .font(.system(size: 14, weight: .semibold))
                                    if !alert.description.isEmpty {
                                        Text(alert.description)
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .navigationTitle("Route Alerts")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isShowingRouteAlerts = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(Color(white: 0.08))
            }
            .onChange(of: viewModel.directions) { _, newDirections in
                // When directions load (route is ready), dismiss any mode selection views
                // and auto-select the first direction
                if !newDirections.isEmpty && viewModel.selectedRoute != nil {
                    isShowingBusRoutes = false
                    isShowingSubwayLines = false
                    isShowingCommuterRailLines = false
                    isLanding = false

                    // Auto-select first direction if none selected
                    if viewModel.selectedDirectionID == nil, let firstDir = newDirections.first {
                        viewModel.selectedDirectionID = firstDir.id
                        Task {
                            await viewModel.selectDirection(firstDir.id)
                        }
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

    // MARK: - Content Wrappers

    private var landingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            landingHeader
            modeCardsSection
            recentSearchesSection
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.bottom, 70)
    }

    @ViewBuilder
    private var activeSearchContent: some View {
        if viewModel.selectedRoute != nil && !viewModel.directions.isEmpty {
            routeDetailsContent
        } else {
            routeSelectionContent
        }
    }

    /// Step-by-step route selection (mode → route → direction → stop)
    private var routeSelectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            activeSearchHeader
            quickRoutesSection
            modeSection
            routeSection
            directionSection
            stopSelectorSection
            statusSection
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.bottom, 70)
    }

    /// Premium route details page shown after a route is selected
    private var routeDetailsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with back, favorite, refresh
            routeDetailsHeader
                .blur(radius: isPickingPrediction ? 6 : 0)
                .allowsHitTesting(!isPickingPrediction)

            // Route badge + destination title
            routeDetailsTitle
                .blur(radius: isPickingPrediction ? 6 : 0)
                .allowsHitTesting(!isPickingPrediction)

            // Direction swap card
            redesignedDirectionSection
                .blur(radius: isPickingPrediction ? 6 : 0)
                .allowsHitTesting(!isPickingPrediction)

            // Stop selector card
            redesignedStopSelector
                .blur(radius: isPickingPrediction ? 6 : 0)
                .allowsHitTesting(!isPickingPrediction)

            // Status / error
            statusSection
                .blur(radius: isPickingPrediction ? 6 : 0)
                .allowsHitTesting(!isPickingPrediction)

            // Upcoming arrivals
            redesignedResultsSection

            // Action cards
            redesignedActionCards
                .blur(radius: isPickingPrediction ? 6 : 0)
                .allowsHitTesting(!isPickingPrediction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 100)
    }

    // MARK: - Landing Header

    private var landingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Explore")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)

            Text("Choose a mode to get started")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.top, 4)
    }

    // MARK: - Active Search Header

    private var activeSearchHeader: some View {
        HStack {
            Text("Explore")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Button {
                haptic()
                withAnimation(.easeInOut(duration: 0.25)) {
                    isLanding = true
                }
                viewModel.handleModeChange()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, -8)
    }

    // MARK: - Route Details Header

    private var routeDetailsHeader: some View {
        HStack {
            // Back button
            Button {
                haptic()
                withAnimation(.easeInOut(duration: 0.25)) {
                    isLanding = true
                }
                viewModel.handleModeChange()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)

            Spacer()

            // Favorite button
            Button {
                haptic()
                isShowingFavoritePicker = true
            } label: {
                Image(systemName: isCurrentSelectionAlreadyFavorited ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isCurrentSelectionAlreadyFavorited ? .yellow : .white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(isCurrentSelectionAlreadyFavorited)

            // Alerts button
            Button {
                haptic()
                isShowingRouteAlerts = true
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .overlay(alignment: .topTrailing) {
                        if routeAlertCount > 0 {
                            Text("\(routeAlertCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(.red))
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Route Details Title

    private var routeDetailsTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Route badge pill
            HStack(spacing: 6) {
                let routeID = viewModel.selectedRoute?.id ?? ""
                let displayName = routeID.isBusRoute
                    ? (viewModel.selectedRoute?.displayName ?? routeID)
                    : routeID.displayRouteName
                let badgeColor = routeID.routeBadgeColor
                let textColor = routeID.routeTextColor

                Text(displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(textColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(badgeColor)
                    )

                Text(routeLineName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }

            // Destination title
            Text("To \(shortDestination(selectedDirectionDestination))")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)

            // Subtitle with stop name
            if let stopName = viewModel.selectedStop?.name {
                Text("via \(shortDestination(stopName))")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Redesigned Direction Section

    @ViewBuilder
    private var redesignedDirectionSection: some View {
        if viewModel.directions.count >= 2 {
            let dir0 = viewModel.directions[0]
            let dir1 = viewModel.directions[1]
            let isDir0Selected = viewModel.selectedDirectionID == dir0.id

            HStack(spacing: 0) {
                // Direction 0
                Button {
                    haptic()
                    viewModel.selectedDirectionID = dir0.id
                    Task {
                        await viewModel.selectDirection(dir0.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(dir0.id == viewModel.selectedDirectionID ? routeBadgeText : "")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(routeBadgeTextColor)
                            .frame(width: dir0.id == viewModel.selectedDirectionID ? 24 : 0, height: 24)
                            .background(
                                Circle().fill(dir0.id == viewModel.selectedDirectionID ? routeAccentColor : .clear)
                            )
                            .opacity(dir0.id == viewModel.selectedDirectionID ? 1 : 0)

                        Text("To \(shortDestination(dir0.destination))")
                            .font(.system(size: 14, weight: isDir0Selected ? .semibold : .medium))
                            .foregroundColor(isDir0Selected ? .white : .white.opacity(0.45))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                // Swap icon
                Button {
                    haptic()
                    let newDir = isDir0Selected ? dir1.id : dir0.id
                    viewModel.selectedDirectionID = newDir
                    Task {
                        await viewModel.selectDirection(newDir)
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: 30)
                }
                .buttonStyle(.plain)

                // Direction 1
                Button {
                    haptic()
                    viewModel.selectedDirectionID = dir1.id
                    Task {
                        await viewModel.selectDirection(dir1.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("To \(shortDestination(dir1.destination))")
                            .font(.system(size: 14, weight: !isDir0Selected ? .semibold : .medium))
                            .foregroundColor(!isDir0Selected ? .white : .white.opacity(0.45))
                            .lineLimit(1)

                        Text(dir1.id == viewModel.selectedDirectionID ? routeBadgeText : "")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(routeBadgeTextColor)
                            .frame(width: dir1.id == viewModel.selectedDirectionID ? 24 : 0, height: 24)
                            .background(
                                Circle().fill(dir1.id == viewModel.selectedDirectionID ? routeAccentColor : .clear)
                            )
                            .opacity(dir1.id == viewModel.selectedDirectionID ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(white: 0.20), lineWidth: 1)
                    )
            )
            .disabled(viewModel.isLoadingStops)
        }
    }

    // MARK: - Redesigned Stop Selector

    private var redesignedStopSelector: some View {
        Menu {
            ForEach(viewModel.stops) { stop in
                Button(stop.name) {
                    haptic()
                    viewModel.selectedStopID = stop.id
                    viewModel.saveWidgetSelection()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(routeAccentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selectedStop?.name ?? "Select your stop")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(viewModel.selectedStop != nil ? "Tap to change stop" : "Choose where you will board")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(white: 0.20), lineWidth: 1)
                    )
            )
        }
        .disabled(viewModel.selectedDirectionID == nil || viewModel.isLoadingStops || viewModel.stops.isEmpty)
    }

    // MARK: - Redesigned Results Section

    @ViewBuilder
    private var redesignedResultsSection: some View {
        if viewModel.arrivals.isEmpty && !viewModel.isLoadingArrivals {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                // Section title with refresh
                HStack {
                    Text(upcomingTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        haptic()
                        Task {
                            await viewModel.loadArrivals()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .blur(radius: isPickingPrediction ? 6 : 0)
                .allowsHitTesting(!isPickingPrediction)

                // Arrival cards
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(displayedArrivals.enumerated()), id: \.element.id) { index, arrival in
                        Button {
                            guard isPickingPrediction else { return }
                            guard arrival.minutesAway != nil, index < viewModel.arrivals.count else {
                                haptic()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isPickingPrediction = false
                                }
                                return
                            }
                            haptic()
                            let trackedTime = arrival.arrivalTime ?? arrival.departureTime
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedPredictionArrivalTime = trackedTime
                                isPickingPrediction = false
                            }
                            viewModel.startLiveActivity(arrivalIndex: index)

                            withAnimation(.easeInOut(duration: 0.3)) {
                                showIslandHint = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showIslandHint = false
                                }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                HStack(spacing: 4) {
                                    Text(arrival.minutesAway.map { "\($0)" } ?? "--")
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .foregroundColor(arrival.minutesAway != nil ? .white : .white.opacity(0.3))

                                    Text("min")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(white: 0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(
                                                    isSelectedArrival(arrival) ? routeAccentColor : Color(white: 0.20),
                                                    lineWidth: isSelectedArrival(arrival) ? 2 : 1
                                                )
                                        )
                                )
                                .scaleEffect(isPickingPrediction && arrival.minutesAway != nil ? 1.05 : 1.0)

                                // Arrival time
                                Text(arrivalTimeText(for: arrival))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)

                                // Stops away (bus only)
                                if let stopsText = stopsAwayText(for: arrival.stopsAway) {
                                    Text(stopsText)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.35))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // "Pick an arrival" hint during selection mode
                if isPickingPrediction {
                    HStack {
                        Text("Tap an arrival to show on Dynamic Island")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(routeAccentColor)

                        Spacer()

                        Button {
                            haptic()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isPickingPrediction = false
                            }
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Inline hint after send-to-island animation
                if showIslandHint {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                        Text("Visible on Dynamic Island after exiting app")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPickingPrediction)
        }
    }

    // MARK: - Redesigned Stop Search Bar

    private var redesignedStopSearchBar: some View {
        Menu {
            ForEach(viewModel.stops) { stop in
                Button(stop.name) {
                    haptic()
                    viewModel.selectedStopID = stop.id
                    viewModel.saveWidgetSelection()
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))

                Text("Search for a \(viewModel.stopTitle.lowercased())")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.35))

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(white: 0.20), lineWidth: 1)
                    )
            )
        }
        .disabled(viewModel.stops.isEmpty)
    }

    // MARK: - Redesigned Action Cards

    @ViewBuilder
    private func actionCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(white: 0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var redesignedActionCards: some View {
        VStack(spacing: 10) {
            // Show on Dynamic Island — original pill-preview button
            if !viewModel.arrivals.isEmpty {
                Button {
                    haptic(.medium)
                    if viewModel.currentActivity != nil {
                        viewModel.stopLiveActivity()
                        selectedPredictionArrivalTime = nil
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isPickingPrediction = true
                        }
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
                                // Route badge on left
                                let routeID = viewModel.selectedRoute?.id ?? "39"
                                let badgeText = routeID.isBusRoute
                                    ? (viewModel.selectedRoute?.displayName ?? routeID)
                                    : routeID.displayRouteName
                                if routeID.isCommuterRail {
                                    Image(systemName: "train.side.front.car")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(.purple)
                                        .padding(.leading, 6)
                                } else {
                                    Text(badgeText)
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(routeID.routeTextColor)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(routeID.routeBadgeColor)
                                        )
                                        .padding(.leading, 4)
                                }

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
                                Circle()
                                    .fill(.black.opacity(0.95))
                                    .frame(width: 3, height: 3)
                                    .overlay(
                                        Circle()
                                            .stroke(.white.opacity(0.1), lineWidth: 0.3)
                                    )

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
                                .foregroundColor(.white)

                            Text(viewModel.currentActivity != nil ? "Remove from screen" : "Live countdown on screen")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: viewModel.currentActivity != nil ? "xmark.circle.fill" : "arrow.right.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(viewModel.currentActivity != nil ? .red : routeAccentColor)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(white: 0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(white: 0.20), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // Add to Favorites
            actionCard(
                icon: isCurrentSelectionAlreadyFavorited ? "star.fill" : "star",
                iconColor: .yellow,
                title: "Add to Favorites",
                subtitle: isCurrentSelectionAlreadyFavorited ? "Already in your favorites" : "Quick access to this route",
                disabled: isCurrentSelectionAlreadyFavorited
            ) {
                haptic()
                isShowingFavoritePicker = true
            }

            // Add to Home Screen Widgets
            actionCard(
                icon: "square.grid.2x2",
                iconColor: routeAccentColor,
                title: "Add to Home Screen Widgets",
                subtitle: "Track arrivals from your Home Screen"
            ) {
                haptic()
                isShowingWidgetAssignment = true
            }
        }
    }

    // MARK: - Route Accent Color

    private var routeAccentColor: Color {
        let routeID = (viewModel.selectedRoute?.id ?? "").uppercased()

        // Bus — yellow
        if routeID.allSatisfy({ $0.isNumber }) || routeID.hasPrefix("SL") || routeID.hasPrefix("CT") {
            return Color(red: 255/255, green: 200/255, blue: 0/255)
        }
        if routeID.contains("RED") || routeID.contains("MATTAPAN") {
            return Color(red: 218/255, green: 41/255, blue: 28/255)
        }
        if routeID.contains("ORANGE") {
            return Color(red: 237/255, green: 139/255, blue: 0/255)
        }
        if routeID.contains("BLUE") {
            return Color(red: 0/255, green: 115/255, blue: 207/255)
        }
        if routeID.contains("GREEN") {
            return Color(red: 0/255, green: 132/255, blue: 61/255)
        }
        if routeID.hasPrefix("CR-") {
            return .purple
        }
        return Color(red: 255/255, green: 200/255, blue: 0/255) // default bus yellow
    }

    private var routeLineName: String {
        let routeID = (viewModel.selectedRoute?.id ?? "").uppercased()

        if routeID.allSatisfy({ $0.isNumber }) || routeID.hasPrefix("SL") || routeID.hasPrefix("CT") {
            return "Bus"
        }
        if routeID.contains("RED") { return "Red Line" }
        if routeID.contains("MATTAPAN") { return "Mattapan Line" }
        if routeID.contains("ORANGE") { return "Orange Line" }
        if routeID.contains("BLUE") { return "Blue Line" }
        if routeID.contains("GREEN") { return "Green Line" }
        if routeID.hasPrefix("CR-") {
            return viewModel.selectedRoute?.displayName ?? "Commuter Rail"
        }
        return viewModel.selectedRoute?.displayName ?? "Route"
    }

    private var routeBadgeText: String {
        let routeID = viewModel.selectedRoute?.id ?? ""
        if routeID.isBusRoute {
            return viewModel.selectedRoute?.displayName ?? routeID
        }
        return routeID.displayRouteName
    }

    private var routeBadgeTextColor: Color {
        (viewModel.selectedRoute?.id ?? "").routeTextColor
    }

    private var routeAlertCount: Int {
        guard let routeID = viewModel.selectedRoute?.id else { return 0 }
        return viewModel.allAlerts.filter { alert in
            alert.routeIDs.contains(routeID)
        }.count
    }

    private var routeAlerts: [MBTAAlert] {
        guard let routeID = viewModel.selectedRoute?.id else { return [] }
        return viewModel.allAlerts.filter { alert in
            alert.routeIDs.contains(routeID)
        }
    }

    private var upcomingTitle: String {
        switch viewModel.selectedMode {
        case .bus:
            return "Upcoming Buses"
        case .subway:
            return "Upcoming Trains"
        case .commuterRail:
            return "Upcoming Trains"
        }
    }

    // MARK: - Mode Cards

    private var modeCardsSection: some View {
        HStack(alignment: .top, spacing: 8) {
            // Bus card navigates to dedicated BusRoutesView
            Button {
                haptic(.medium)
                isShowingBusRoutes = true
            } label: {
                Image("MBTABus")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            // Subway card navigates to dedicated SubwayLinesView
            Button {
                haptic(.medium)
                isShowingSubwayLines = true
            } label: {
                Image("MBTASubway")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            // Commuter Rail card navigates to dedicated CommuterRailLinesView
            Button {
                haptic(.medium)
                isShowingCommuterRailLines = true
            } label: {
                Image("MBTACommuterRail")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, -8)
        .padding(.top, 4)
    }

    private func modeCard(mode: TransportMode, imageName: String, label: String) -> some View {
        Button {
            haptic(.medium)
            viewModel.selectedMode = mode
            viewModel.handleModeChange()
            withAnimation(.easeInOut(duration: 0.25)) {
                isLanding = false
            }
        } label: {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Searches

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with Clear All
            HStack {
                Text("Recent Searches")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))

                Spacer()

                if !recentSearches.isEmpty {
                    Button {
                        haptic()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            recentSearches.removeAll()
                        }
                        UserDefaults.standard.removeObject(forKey: "recentSearches")
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }

            if recentSearches.isEmpty {
                // Empty state
                HStack {
                    Spacer()
                    Text("Your recent searches will appear here")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                // Search rows
                VStack(spacing: 0) {
                    ForEach(Array(recentSearches.enumerated()), id: \.element.id) { index, recent in
                        Button {
                            haptic()
                            let fav = SavedFavorite(
                                mode: recent.mode,
                                routeID: recent.routeID,
                                routeName: recent.routeName,
                                directionID: recent.directionID,
                                directionName: "",
                                directionDestination: recent.directionDestination,
                                stopID: recent.stopID,
                                stopName: recent.stopName
                            )
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isLanding = false
                            }
                            Task {
                                await viewModel.loadFavorite(fav)
                            }
                        } label: {
                            recentSearchRow(recent, isLast: index == recentSearches.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(white: 0.10))
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func recentSearchRow(_ recent: RecentSearch, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                recentBadge(for: recent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recentPrimaryText(recent))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(recentSecondaryText(recent))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())

            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, 58)
            }
        }
        .contentShape(Rectangle())
    }

    private func recentBadge(for recent: RecentSearch) -> some View {
        let routeID = recent.routeID
        let color: Color = routeID.routeBadgeColor
        let textColor: Color = routeID.routeTextColor

        let badgeText: String = {
            if routeID.isBusRoute {
                return recent.routeName
            }
            return routeID.displayRouteName
        }()

        return Text(badgeText)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(textColor)
            .frame(width: 34, height: 34)
            .background(Circle().fill(color))
    }

    private func recentPrimaryText(_ recent: RecentSearch) -> String {
        // For subway/rail, show the destination; for bus, show "Harvard Square" etc.
        if !recent.directionDestination.isEmpty {
            return recent.directionDestination
                .replacingOccurrences(of: " Station", with: "")
        }
        return recent.stopName
            .replacingOccurrences(of: " Station", with: "")
    }

    private func recentSecondaryText(_ recent: RecentSearch) -> String {
        return recent.stopName
            .replacingOccurrences(of: " Station", with: "")
    }

    // MARK: - Recent Search Persistence

    private func saveRecentSearch() {
        guard let route = viewModel.selectedRoute,
              let directionID = viewModel.selectedDirectionID,
              let direction = viewModel.directions.first(where: { $0.id == directionID }),
              let stop = viewModel.selectedStop else { return }

        let entry = RecentSearch(
            routeID: route.id,
            routeName: route.displayName,
            mode: viewModel.selectedMode,
            directionID: directionID,
            directionDestination: direction.destination,
            stopID: stop.id,
            stopName: stop.name
        )

        // Remove duplicate, then insert at front
        recentSearches.removeAll { $0.id == entry.id }
        recentSearches.insert(entry, at: 0)
        if recentSearches.count > 6 {
            recentSearches = Array(recentSearches.prefix(6))
        }

        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: "recentSearches")
        }
    }

    private func loadRecentSearches() {
        guard let data = UserDefaults.standard.data(forKey: "recentSearches"),
              let decoded = try? JSONDecoder().decode([RecentSearch].self, from: data) else { return }
        recentSearches = decoded
    }

    private var quickRoutesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Access")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        Button {
                            haptic()
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
                                Capsule()
                                    .fill(isQuickRouteSelected(favorite) ? Color.blue : Color(.secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        haptic()
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
                        .liquidGlassPill()
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Menu {
                ForEach(TransportMode.allCases) { mode in
                    Button {
                        haptic()
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
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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
                .font(.system(size: 13, weight: .semibold))
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
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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
            
            // Autocomplete suggestions
            if !viewModel.routeSuggestions.isEmpty && viewModel.selectedRoute == nil {
                VStack(spacing: 0) {
                    ForEach(viewModel.routeSuggestions) { route in
                        Button {
                            haptic()
                            Task {
                                await viewModel.selectSuggestedRoute(route)
                            }
                        } label: {
                            HStack {
                                Text(route.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                if let longName = route.longName, !longName.isEmpty,
                                   longName != route.displayName {
                                    Text(longName)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        
                        if route.id != viewModel.routeSuggestions.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            }
        }
    }

    private var presetLineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.fieldTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Menu {
                ForEach(viewModel.presetLines) { line in
                    Button {
                        haptic()
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
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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
                            haptic()
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
                    .font(.system(size: 13, weight: .semibold))
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
                    haptic()
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
                    haptic()
                    viewModel.selectedStopID = stop.id
                    viewModel.saveWidgetSelection()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stop")
                    .font(.system(size: 13, weight: .semibold))
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
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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

    private var widgetButton: some View {
        Button {
            haptic()
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
            .liquidGlassCard()
        }
    }
    
    private var aboutButton: some View {
        Button {
            haptic()
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
            .liquidGlassCard()
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

    private var isCurrentSelectionAlreadyFavorited: Bool {
        guard let routeID = viewModel.selectedRoute?.id,
              let directionID = viewModel.selectedDirectionID,
              let stopID = viewModel.selectedStopID else {
            return false
        }
        return viewModel.quickFavorites.contains { favorite in
            guard let favorite else { return false }
            return favorite.routeID == routeID &&
                   favorite.directionID == directionID &&
                   favorite.stopID == stopID
        }
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

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    
    /// Returns true only for the single arrival closest to the tracked selection time (within 5 min).
    /// This ensures exactly one arrival card is highlighted, even when arrivals shift on refresh.
    private func isSelectedArrival(_ arrival: BusArrival) -> Bool {
        guard let selectedTime = selectedPredictionArrivalTime,
              (arrival.arrivalTime ?? arrival.departureTime) != nil else {
            return false
        }
        // Find the displayed arrival closest to the tracked time within a 5-minute window
        let candidates = viewModel.arrivals.filter { a in
            guard let t = a.arrivalTime ?? a.departureTime else { return false }
            return abs(t.timeIntervalSince(selectedTime)) < 300
        }
        guard let best = candidates.min(by: { a, b in
            let aTime = a.arrivalTime ?? a.departureTime ?? .distantFuture
            let bTime = b.arrivalTime ?? b.departureTime ?? .distantFuture
            return abs(aTime.timeIntervalSince(selectedTime)) < abs(bTime.timeIntervalSince(selectedTime))
        }) else {
            return false
        }
        return best.id == arrival.id
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

struct WidgetCustomizationView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @State private var editingDefault = false
    @State private var expandedOverrideID: String? = nil
    @State private var isShowingInstructions = false
    @State private var mediumWidgetFavoriteIndex: Int? = nil
    @State private var smallWidget1FavoriteIndex: Int? = nil
    @State private var smallWidget2FavoriteIndex: Int? = nil

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    var body: some View {
        ZStack {
            // Modern gradient background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Helper text if no favorites exist
                    if viewModel.quickFavorites.compactMap({ $0 }).isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                            Text("Create a favorite from the home screen to enable widgets")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemGroupedBackground))
                        }
                    }
                    
                    defaultWidgetSection
                    timeOverrideSection
                    widgetAssignmentSection
                    instructionsSection
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
                    haptic()
                    withAnimation(.spring(response: 0.3)) {
                        editingDefault.toggle()
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.blue)
            }

            Text("Shows all day unless a time override is active.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Text(favoriteSummary(viewModel.widgetDefaultFavorite))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(viewModel.widgetDefaultFavorite == nil ? .secondary : .primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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

            Text("Override the default route during specific times.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            ForEach(viewModel.widgetOverrides) { override in
                overrideCard(override)
            }

            Button {
                haptic()
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
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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
                        haptic()
                        withAnimation(.spring(response: 0.3)) {
                            expandedOverrideID = expandedOverrideID == override.id ? nil : override.id
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.blue)

                    Button {
                        haptic(.medium)
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
                                .fill(Color(.tertiarySystemGroupedBackground))
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
                                .fill(Color(.tertiarySystemGroupedBackground))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                haptic()
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
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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
            
            Text("Assign a favorite to each widget on your home screen.")
                .font(.system(size: 14))
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
                        haptic()
                        mediumWidgetFavoriteIndex = nil
                        saveWidgetAssignments()
                    }
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        if favorite != nil {
                            Button(favoriteSummary(favorite) ?? "Favorite \(index + 1)") {
                                haptic()
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
                            .fill(Color(.tertiarySystemGroupedBackground))
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
                        haptic()
                        smallWidget1FavoriteIndex = nil
                        saveWidgetAssignments()
                    }
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        if favorite != nil {
                            Button(favoriteSummary(favorite) ?? "Favorite \(index + 1)") {
                                haptic()
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
                            .fill(Color(.tertiarySystemGroupedBackground))
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
                        haptic()
                        smallWidget2FavoriteIndex = nil
                        saveWidgetAssignments()
                    }
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        if favorite != nil {
                            Button(favoriteSummary(favorite) ?? "Favorite \(index + 1)") {
                                haptic()
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
                            .fill(Color(.tertiarySystemGroupedBackground))
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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
                    haptic()
                    action(favorite)
                } label: {
                    HStack {
                        Text(favoriteSummary(favorite))
                            .foregroundColor(favorite == nil ? .secondary : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
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

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Instructions
                    NavigationLink(destination: InstructionsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.orange)
                                .frame(width: 24, height: 24)
                            
                            Text("Instructions")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                        }
                    }
                    
                    // What the app does
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            haptic()
                            withAnimation(.spring(response: 0.3)) {
                                isShowingWhatItDoes.toggle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "list.bullet.clipboard")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 24, height: 24)
                                
                                Text("What the app does")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .rotationEffect(.degrees(isShowingWhatItDoes ? 90 : 0))
                            }
                            .padding(16)
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
                            .padding(.horizontal, 16)
                            
                            Text("Why it exists:")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                            
                            Text("This app is designed for commuters who want fast, reliable information with zero friction. No clutter, no extra steps — just the data you need.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                            
                            Text("Data source:")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                            
                            Text("All transit data is provided by the official MBTA public API.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                    }
                    
                    // About this app
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            haptic()
                            withAnimation(.spring(response: 0.3)) {
                                isShowingAboutApp.toggle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.green)
                                    .frame(width: 24, height: 24)
                                
                                Text("About this app")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .rotationEffect(.degrees(isShowingAboutApp ? 90 : 0))
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                        
                        if isShowingAboutApp {
                            Text("MBTA Widgets is built to make your daily commute easier by showing real-time bus and train arrivals directly on your iPhone without needing to open an app. Just glance at your Home Screen, Lock Screen, or Dynamic Island and instantly know when your next ride is coming.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                    }
                    
                    // Share Feedback
                    Button {
                        haptic()
                        if let url = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSetMU7XgiDaOgMJXtlMQVteH796sDNcNeviN-cikIC2CuRFAA/viewform?usp=header") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 24, height: 24)

                            Text("Share Feedback")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                        }
                    }
                    
                    // Privacy Policy
                    Button {
                        haptic()
                        if let url = URL(string: "https://mbta-widgets.web.app") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.purple)
                                .frame(width: 24, height: 24)

                            Text("Privacy Policy")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                        }
                    }
                    
                    // Buy me a subway ride
                    Button {
                        haptic()
                        if let url = URL(string: "https://www.buymeacoffee.com/puneetramini") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("\u{1F687}")
                                .font(.system(size: 16))
                                .frame(width: 24, height: 24)

                            Text("Buy me a subway ride")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 255/255, green: 221/255, blue: 0/255).opacity(0.25))
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
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

// MARK: - Instructions View

struct InstructionsView: View {
    private struct InstructionStep: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        let imageName: String
        let icon: String
        let color: Color
    }
    
    private let steps: [InstructionStep] = [
        InstructionStep(
            id: 1,
            title: "Save to Quick Access",
            subtitle: "Tap the star on any route or use the + button to save favorites for one-tap access.",
            imageName: "InstructionQuickAccess",
            icon: "star.fill",
            color: .orange
        ),
        InstructionStep(
            id: 2,
            title: "Add a Widget",
            subtitle: "Put MBTA arrivals on your Home Screen in a few quick steps.",
            imageName: "InstructionAddWidget",
            icon: "plus.rectangle.on.rectangle",
            color: .blue
        ),
        InstructionStep(
            id: 3,
            title: "Customize Your Widget",
            subtitle: "Personalize your widgets to fit your schedule and favorite routes.",
            imageName: "InstructionCustomizeWidget",
            icon: "slider.horizontal.3",
            color: .blue
        ),
        InstructionStep(
            id: 4,
            title: "Smart Scheduling",
            subtitle: "Automatically switch routes based on time of day.",
            imageName: "InstructionSmartScheduling",
            icon: "clock.arrow.2.circlepath",
            color: .blue
        ),
        InstructionStep(
            id: 5,
            title: "Dynamic Island",
            subtitle: "See live arrival countdowns without opening the app.",
            imageName: "InstructionDynamicIsland",
            icon: "iphone",
            color: .blue
        )
    ]
    
    @State private var zoomedStep: InstructionStep? = nil
    @Namespace private var zoomNamespace
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Learn how to get the most out of MBTA Widgets.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    
                    ForEach(steps) { step in
                        VStack(alignment: .leading, spacing: 0) {
                            // Step header
                            HStack(spacing: 10) {
                                Text("\(step.id)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(step.color)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Text(step.subtitle)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                            }
                            .padding(16)
                            
                            // Instruction image
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    zoomedStep = step
                                }
                            } label: {
                                Image(step.imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 14)
                            }
                            .buttonStyle(.plain)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            
            // Fullscreen zoom overlay
            if let step = zoomedStep {
                ZoomOverlay(imageName: step.imageName) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        zoomedStep = nil
                    }
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("Instructions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ZoomOverlay: View {
    let imageName: String
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(20)
                    }
                }
                
                Spacer()
                
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = lastScale * value.magnification
                            }
                            .onEnded { value in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation(.spring(response: 0.3)) {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                            .simultaneously(with:
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { value in
                                        lastOffset = offset
                                        if scale <= 1.0 {
                                            withAnimation(.spring(response: 0.3)) {
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    }
                            )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                
                Spacer()
                
                Text("Pinch to zoom \u{2022} Double-tap to toggle \u{2022} Tap X to close")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - String Extensions for Route Colors
private extension String {
    var isBusRoute: Bool {
        let route = self.uppercased()
        return route.allSatisfy({ $0.isNumber })
            || route.first?.isNumber == true
            || route.starts(with: "SL")
            || route.starts(with: "CT")
    }

    var routeBadgeColor: Color {
        let route = self.uppercased()
        
        // Bus - Bright amber/gold for visibility on black pill
        if route.isBusRoute {
            return Color(red: 255/255, green: 200/255, blue: 0/255)
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
        } else if route.starts(with: "CR-") {
            return Color(red: 128/255, green: 0/255, blue: 160/255) // MBTA Commuter Rail purple
        }
        
        return .gray
    }
    
    var routeTextColor: Color {
        let route = self.uppercased()
        
        // Bus routes - black text on yellow
        if route.isBusRoute {
            return .black
        }
        
        // All subway lines - white text
        return .white
    }
    
    var isCommuterRail: Bool {
        self.uppercased().starts(with: "CR-")
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
        } else if route.contains("MATTAPAN") {
            return "ML"
        } else if route.starts(with: "CR-") {
            return "CR"
        }
        
        return self
    }
}

// MARK: - Widget Assignment Sheet

struct WidgetAssignmentSheet: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSlot: WidgetSlot = .wide
    @State private var mediumWidgetFavoriteIndex: Int? = nil
    @State private var smallWidget1FavoriteIndex: Int? = nil
    @State private var smallWidget2FavoriteIndex: Int? = nil

    // Post-assignment onboarding state
    @State private var showOnboarding = false
    @State private var showSuccessCheck = false
    @State private var successCheckScale: CGFloat = 0
    @State private var drawCheckmark = false
    @State private var assignmentSlideOut = false

    private enum WidgetSlot: String, CaseIterable, Identifiable {
        case wide = "Wide Widget"
        case small1 = "Small Widget 1"
        case small2 = "Small Widget 2"

        var id: String { rawValue }

        var screenshotAsset: String {
            switch self {
            case .wide: return "WidgetWide1"
            case .small1: return "WidgetSmall1"
            case .small2: return "WidgetSmall2"
            }
        }

        var userDefaultsKey: String {
            switch self {
            case .wide: return "mediumWidgetFavoriteIndex"
            case .small1: return "smallWidget1FavoriteIndex"
            case .small2: return "smallWidget2FavoriteIndex"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !showOnboarding {
                assignmentView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showOnboarding {
                onboardingView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            loadWidgetAssignments()
        }
    }

    // MARK: - Assignment View

    private var assignmentView: some View {
        VStack(spacing: 0) {
            // Header with close button
            ZStack {
                HStack {
                    Button {
                        haptic()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(white: 0.20)))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                VStack(spacing: 4) {
                    Text("Add to Home Screen Widget")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("Choose where you want this route to appear.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Widget cards
            VStack(spacing: 12) {
                ForEach(WidgetSlot.allCases) { slot in
                    widgetCard(for: slot)
                }
            }
            .padding(.horizontal, 20)

            // "This is how it appears" hint with arrow
            HStack(spacing: 6) {
                Spacer()
                Text("This is how it appears on your Home Screen")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                Image(systemName: "arrow.turn.right.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            Spacer(minLength: 20)

            // Assign button
            Button {
                haptic(.medium)
                assignToSelectedSlot()
            } label: {
                Text("Assign to \(selectedSlot.rawValue)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.blue)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Cancel
            Button {
                haptic()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Onboarding View

    private var onboardingView: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Button {
                    haptic()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(white: 0.20)))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Success animation
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 52, height: 52)

                    CheckmarkShape()
                        .trim(from: 0, to: drawCheckmark ? 1 : 0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                }
                .scaleEffect(successCheckScale)

                Text("Widget Assigned")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Text("Saved to Favorites and assigned successfully.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.top, 16)
            .padding(.bottom, 0)

            // Onboarding guide image — edge to edge, no side padding
            Image("WidgetOnboarding")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(.top, 10)

            Spacer()
        }
    }

    // MARK: - Widget Card

    private func widgetCard(for slot: WidgetSlot) -> some View {
        let isSelected = selectedSlot == slot

        return Button {
            haptic()
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSlot = slot
            }
        } label: {
            HStack(spacing: 14) {
                // Widget name and current assignment
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    if slot == .wide {
                        Text("Currently:")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                        Text(currentAssignmentRoute(for: slot))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(currentAssignmentLabel(for: slot))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                // Widget preview image — fixed height for all tiles
                Image(slot.screenshotAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color.blue : Color(white: 0.20),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Current Assignment Label

    private func currentAssignmentLabel(for slot: WidgetSlot) -> String {
        let index: Int?
        switch slot {
        case .wide: index = mediumWidgetFavoriteIndex
        case .small1: index = smallWidget1FavoriteIndex
        case .small2: index = smallWidget2FavoriteIndex
        }

        guard let idx = index,
              viewModel.quickFavorites.indices.contains(idx),
              let favorite = viewModel.quickFavorites[idx] else {
            return "Currently: None"
        }

        return "Currently: \(favorite.routeName) · \(favorite.directionDestination)"
    }

    private func currentAssignmentRoute(for slot: WidgetSlot) -> String {
        let index: Int?
        switch slot {
        case .wide: index = mediumWidgetFavoriteIndex
        case .small1: index = smallWidget1FavoriteIndex
        case .small2: index = smallWidget2FavoriteIndex
        }

        guard let idx = index,
              viewModel.quickFavorites.indices.contains(idx),
              let favorite = viewModel.quickFavorites[idx] else {
            return "None"
        }

        return "\(favorite.routeName) · \(favorite.directionDestination)"
    }

    // MARK: - Assignment Logic

    private func assignToSelectedSlot() {
        guard let favoriteIndex = resolveOrCreateFavoriteIndex() else { return }

        switch selectedSlot {
        case .wide:
            mediumWidgetFavoriteIndex = favoriteIndex
        case .small1:
            smallWidget1FavoriteIndex = favoriteIndex
        case .small2:
            smallWidget2FavoriteIndex = favoriteIndex
        }

        saveWidgetAssignments()

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif

        // Transition to onboarding
        withAnimation(.easeInOut(duration: 0.35)) {
            showOnboarding = true
        }

        // Animate success checkmark after transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                successCheckScale = 1.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.5)) {
                drawCheckmark = true
            }
        }
    }

    private func resolveOrCreateFavoriteIndex() -> Int? {
        guard let routeID = viewModel.selectedRoute?.id,
              let directionID = viewModel.selectedDirectionID,
              let stopID = viewModel.selectedStopID else {
            return nil
        }

        // Check if current route+direction+stop is already a favorite
        for (index, favorite) in viewModel.quickFavorites.enumerated() {
            if let fav = favorite,
               fav.routeID == routeID,
               fav.directionID == directionID,
               fav.stopID == stopID {
                return index
            }
        }

        // Use first empty slot if available
        if let emptyIndex = viewModel.quickFavorites.firstIndex(where: { $0 == nil }) {
            viewModel.saveFavorite(at: emptyIndex)
            return emptyIndex
        }

        // Replace last slot if all full
        viewModel.saveFavorite(at: 3)
        return 3
    }

    // MARK: - Persistence

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
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Checkmark Shape

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX * 0.8, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

#Preview {
    ContentView(viewModel: ArrivalsViewModel())
}
