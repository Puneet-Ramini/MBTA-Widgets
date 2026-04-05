//
//  ContentView.swift
//  MBTA
//
//  Created by Puneet Ramini on 3/14/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ArrivalsViewModel()
    @State private var isShowingFavoritePicker = false
    @State private var isShowingWidgetCustomization = false
    @Namespace private var glassNamespace

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
                    VStack(alignment: .leading, spacing: 16) {
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
                            .padding(.top, 4)

                        quickRoutesSection
                        modeSection
                        routeSection
                        directionSection
                        stopSelectorSection
                        statusSection
                        resultsSection
                        widgetButton
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
            VStack(alignment: .leading, spacing: 16) {
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

                HStack(spacing: 12) {
                    ForEach(displayedArrivals) { arrival in
                        VStack(spacing: 8) {
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
                            .padding(.vertical, 16)
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
                                }

                                Text(arrivalTimeText(for: arrival))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
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

    private func quickRouteLabel(for favorite: SavedFavorite?, index: Int) -> String {
        guard let favorite else {
            return "Empty"
        }

        return "\(favorite.routeID) \(directionSymbol(for: favorite.directionID))"
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
                    instructionsSection
                    betaSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Customize Widget")
        .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    ContentView()
}
