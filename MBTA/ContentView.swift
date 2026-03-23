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

    private let pageBackground = Color(red: 248 / 255, green: 245 / 255, blue: 250 / 255)
    private let cardBackground = Color(red: 241 / 255, green: 238 / 255, blue: 245 / 255)
    private let quickRouteBackground = Color(red: 238 / 255, green: 235 / 255, blue: 242 / 255)
    private let quickRouteSelected = Color(red: 245 / 255, green: 208 / 255, blue: 78 / 255)
    private let loadButtonColor = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
    private let resultPillColor = Color(red: 247 / 255, green: 218 / 255, blue: 105 / 255)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("MBTA Schedules")
                        .font(.title3)
                        .fontWeight(.semibold)

                    quickRoutesSection
                    modeSection
                    routeSection
                    directionSection
                    stopSelectorSection
                    statusSection
                    resultsSection
                    widgetButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(pageBackground)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                    Button {
                        Task {
                            await viewModel.handleQuickRouteTap(at: index)
                        }
                    } label: {
                        Text(quickRouteLabel(for: favorite, index: index))
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isQuickRouteSelected(favorite) ? quickRouteSelected : quickRouteBackground)
                            .clipShape(Capsule())
                    }
                }

                Button {
                    isShowingFavoritePicker = true
                } label: {
                    Text("+ Add")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(quickRouteBackground)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode")
                .font(.footnote)
                .fontWeight(.semibold)

            Menu {
                ForEach(TransportMode.allCases) { mode in
                    Button(mode.rawValue) {
                        viewModel.selectedMode = mode
                        viewModel.handleModeChange()
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.selectedMode.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.fieldTitle)
                .font(.footnote)
                .fontWeight(.semibold)

            HStack(spacing: 10) {
                TextField(viewModel.routePlaceholder, text: $viewModel.routeInput)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    Task {
                        await viewModel.loadRoute()
                    }
                } label: {
                    if viewModel.isLoadingRoute {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    } else {
                        Text("Load Route")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                }
                .background(loadButtonColor)
                .clipShape(Capsule())
                .disabled(viewModel.isLoadingRoute)
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var presetLineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.fieldTitle)
                .font(.footnote)
                .fontWeight(.semibold)

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
                                .frame(width: 8, height: 8)
                            Text(line.title)
                        }
                    }
                }
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        if let selectedLine = selectedPresetLine {
                            Circle()
                                .fill(lineColor(for: selectedLine.colorName))
                                .frame(width: 8, height: 8)
                        }

                        Text(selectedPresetLine?.title ?? viewModel.routePlaceholder)
                            .font(.subheadline)
                            .foregroundColor(selectedPresetLine == nil ? .secondary : .primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if selectedPresetLine?.query == "Green" {
                HStack(spacing: 8) {
                    ForEach(viewModel.greenLineBranches) { branch in
                        Button(branch.title) {
                            viewModel.selectGreenBranch(branch)
                            Task {
                                await viewModel.loadRoute()
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(viewModel.selectedPresetLineQuery == branch.query ? .white : .green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.selectedPresetLineQuery == branch.query
                            ? Color.green
                            : Color.green.opacity(0.12)
                        )
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var directionSection: some View {
        if !viewModel.directions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Direction")
                        .font(.footnote)
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

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
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Stop")
                        .font(.footnote)
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(viewModel.selectedStop?.name ?? "Select a \(viewModel.stopTitle.lowercased())")
                    .font(.subheadline)
                    .foregroundColor(viewModel.selectedStop == nil ? .secondary : .primary)
                    .lineLimit(2)
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "bus.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text(resultsTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 10) {
                    ForEach(displayedArrivals) { arrival in
                        VStack(spacing: 5) {
                            Text(arrival.minutesAway.map { "\($0) min" } ?? "--")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(resultPillColor)
                                .clipShape(Capsule())

                            if let stopsText = stopsAwayText(for: arrival.stopsAway) {
                                Text(stopsText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Text(arrivalTimeText(for: arrival))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var widgetButton: some View {
        Button {
            isShowingWidgetCustomization = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.secondary)

                Text("Customize Widget")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .padding(.top, 8)
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

    private let pageBackground = Color(red: 248 / 255, green: 245 / 255, blue: 250 / 255)
    private let cardBackground = Color(red: 241 / 255, green: 238 / 255, blue: 245 / 255)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                defaultWidgetSection
                timeOverrideSection
                instructionsSection
                betaSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(pageBackground)
        .navigationTitle("Customize Widget")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var defaultWidgetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Default (All Day) Widget")
                    .font(.headline)

                Spacer()

                Button(editingDefault ? "Done" : "Edit") {
                    editingDefault.toggle()
                }
                .font(.subheadline.weight(.semibold))
            }

            Text("This route shows all day unless a time override is active.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(favoriteSummary(viewModel.widgetDefaultFavorite))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(viewModel.widgetDefaultFavorite == nil ? .secondary : .primary)

            if editingDefault {
                favoriteSelectionList { favorite in
                    viewModel.updateWidgetDefaultFavorite(favorite)
                    editingDefault = false
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var timeOverrideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Override Widget")
                .font(.headline)

            Text("When the current time falls inside one of these ranges, the widget shows that route instead of the default route.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(viewModel.widgetOverrides) { override in
                overrideCard(override)
            }

            Button {
                viewModel.addWidgetOverride()
                expandedOverrideID = viewModel.widgetOverrides.last?.id
            } label: {
                Text("Add Time Override")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func overrideCard(_ override: WidgetScheduleOverride) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(favoriteSummary(override.favorite))
                        .font(.subheadline.weight(.semibold))

                    Text("\(timeText(hour: override.startHour, minute: override.startMinute)) – \(timeText(hour: override.endHour, minute: override.endMinute))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(expandedOverrideID == override.id ? "Done" : "Edit") {
                    expandedOverrideID = expandedOverrideID == override.id ? nil : override.id
                }
                .font(.subheadline.weight(.semibold))

                Button("Delete", role: .destructive) {
                    viewModel.deleteWidgetOverride(id: override.id)
                    if expandedOverrideID == override.id {
                        expandedOverrideID = nil
                    }
                }
                .font(.subheadline.weight(.semibold))
            }

            if expandedOverrideID == override.id {
                VStack(alignment: .leading, spacing: 12) {
                    favoriteSelectionList { favorite in
                        viewModel.updateWidgetOverrideFavorite(id: override.id, favorite: favorite)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Time")
                            .font(.footnote.weight(.semibold))
                        DatePicker(
                            "Start Time",
                            selection: startTimeBinding(for: override),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("End Time")
                            .font(.footnote.weight(.semibold))
                        DatePicker(
                            "End Time",
                            selection: endTimeBinding(for: override),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to add a widget on your iPhone")
                .font(.headline)

            Text("Long press anywhere on your home screen")
            Text("Tap Edit")
            Text("Tap Add Widget")
            Text("Search MBTA Widget")
            Text("Select the second long tile widget")
        }
        .font(.subheadline)
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var betaSection: some View {
        Text("This is a beta version and we’d love to hear your feedback or feature ideas.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
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
