//
//  WidgetsView.swift
//  MBTA
//
//  Widgets tab: shows widget preview, list of configured widgets, and time override.
//

import SwiftUI
import WidgetKit

struct WidgetsView: View {
    @ObservedObject var viewModel: ArrivalsViewModel

    private let accentPink = Color(red: 232/255, green: 54/255, blue: 101/255)
    private let cardBackground = Color(white: 0.12)
    private let cardBorder = Color(white: 0.20)

    // Which widget slot is being edited (nil = sheet hidden)
    @State private var editingWidget: WidgetSlot? = nil
    @State private var isShowingTimeOverride = false

    // Widget assignment indices
    @State private var mediumWidgetFavoriteIndex: Int? = nil
    @State private var smallWidget1FavoriteIndex: Int? = nil
    @State private var smallWidget2FavoriteIndex: Int? = nil

    private enum WidgetSlot: Identifiable {
        case medium, small1, small2
        var id: String {
            switch self {
            case .medium: return "medium"
            case .small1: return "small1"
            case .small2: return "small2"
            }
        }
    }

    private var savedFavorites: [SavedFavorite] {
        viewModel.quickFavorites.compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if savedFavorites.isEmpty {
                        headerOnly
                        emptyState
                    } else {
                        topHeroSection
                            .padding(.bottom, -10)
                        yourWidgetsSection
                        timeOverrideRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                autoAssignWidgets()
                loadWidgetAssignments()
            }
            .sheet(item: $editingWidget) { slot in
                favoritePickerSheet(for: slot)
                    .presentationDetents([.medium])
                    .presentationBackground(Color.black)
                    .presentationCornerRadius(24)
            }
            .sheet(isPresented: $isShowingTimeOverride) {
                TimeOverrideSheet(viewModel: viewModel)
                    .presentationDetents([.large])
                    .presentationBackground(Color.black)
                    .presentationCornerRadius(24)
            }
        }
    }

    // MARK: - Header Only (empty state)

    private var headerOnly: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widgets")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text("Stay updated with your favorite routes, right from your home screen.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.25))

            Text("No widgets configured")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Text("Please add a favorite first.\nSave a shortcut from the Home or Search tab to automatically configure your widgets.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Top Hero Section

    private var topHeroSection: some View {
        Image("WidgetHeroPreview")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    // MARK: - Your Widgets Section

    private var yourWidgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Widgets")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            widgetTile(
                title: "Wide Widget",
                screenshotAsset: "WidgetWide1",
                assignedIndex: mediumWidgetFavoriteIndex,
                slot: .medium
            )

            widgetTile(
                title: "Small Widget 1",
                screenshotAsset: "WidgetSmall1",
                assignedIndex: smallWidget1FavoriteIndex,
                slot: .small1
            )

            widgetTile(
                title: "Small Widget 2",
                screenshotAsset: "WidgetSmall2",
                assignedIndex: smallWidget2FavoriteIndex,
                slot: .small2
            )
        }
    }

    // MARK: - Widget Tile

    private func widgetTile(title: String, screenshotAsset: String, assignedIndex: Int?, slot: WidgetSlot) -> some View {
        Button {
            haptic()
            editingWidget = slot
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    if slot == .medium {
                        // Wide widget: 3 lines
                        Text("Currently:")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                        if let index = assignedIndex,
                           viewModel.quickFavorites.indices.contains(index),
                           let fav = viewModel.quickFavorites[index] {
                            Text("\(fav.routeName) · \(fav.directionDestination)")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.35))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("None")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.35))
                        }
                    } else {
                        if let index = assignedIndex,
                           viewModel.quickFavorites.indices.contains(index),
                           let fav = viewModel.quickFavorites[index] {
                            Text("Currently: \(fav.routeName) · \(fav.directionDestination)")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.35))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("Currently: None")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }
                }

                Spacer()

                Image(screenshotAsset)
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
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Favorite Picker Sheet

    private func favoritePickerSheet(for slot: WidgetSlot) -> some View {
        let slotTitle: String = {
            switch slot {
            case .medium: return "Wide Widget"
            case .small1: return "Small Widget 1"
            case .small2: return "Small Widget 2"
            }
        }()

        return ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                ZStack {
                    HStack {
                        Button {
                            haptic()
                            editingWidget = nil
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
                        Text(slotTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)

                        Text("Select a route for this widget.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                // Favorite cards
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                        if let fav = favorite {
                            let assigned = isAssigned(index: index, to: slot)

                            Button {
                                haptic(.medium)
                                assignFavorite(index: index, to: slot)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    editingWidget = nil
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    routeBadge(for: fav)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fav.routeName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)

                                        Text("\(fav.directionDestination) · \(fav.stopName)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.4))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }

                                    Spacer()

                                    if assigned {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(white: assigned ? 0.14 : 0.10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(
                                                    assigned ? Color.green.opacity(0.4) : Color(white: 0.20),
                                                    lineWidth: assigned ? 1.5 : 1
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if savedFavorites.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "star.slash")
                                .font(.system(size: 28))
                                .foregroundColor(Color(white: 0.3))
                            Text("No favorites saved yet.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.4))
                            Text("Save a route from the Home tab first.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.25))
                        }
                        .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Cancel
                Button {
                    haptic()
                    editingWidget = nil
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Route Badge (for picker)

    private func routeBadge(for favorite: SavedFavorite) -> some View {
        let route = favorite.routeID.uppercased()
        let color: Color = {
            if route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT") {
                return Color(red: 255/255, green: 200/255, blue: 0/255)
            }
            if route.contains("RED") || route.contains("MATTAPAN") { return Color(red: 218/255, green: 41/255, blue: 28/255) }
            if route.contains("ORANGE") { return Color(red: 237/255, green: 139/255, blue: 0/255) }
            if route.contains("BLUE") { return Color(red: 0/255, green: 115/255, blue: 207/255) }
            if route.contains("GREEN") { return Color(red: 0/255, green: 132/255, blue: 61/255) }
            if route.starts(with: "CR-") { return .purple }
            return Color(red: 255/255, green: 200/255, blue: 0/255)
        }()
        let textColor: Color = (route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT")) ? .black : .white

        return Text(favorite.routeName)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(color))
    }

    // MARK: - Assignment Helpers

    private func isAssigned(index: Int, to slot: WidgetSlot) -> Bool {
        switch slot {
        case .medium: return mediumWidgetFavoriteIndex == index
        case .small1: return smallWidget1FavoriteIndex == index
        case .small2: return smallWidget2FavoriteIndex == index
        }
    }

    private func assignFavorite(index: Int, to slot: WidgetSlot) {
        switch slot {
        case .medium: mediumWidgetFavoriteIndex = index
        case .small1: smallWidget1FavoriteIndex = index
        case .small2: smallWidget2FavoriteIndex = index
        }
        saveWidgetAssignments()
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
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Time Override Row

    private var timeOverrideRow: some View {
        Button {
            haptic()
            isShowingTimeOverride = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 20))
                    .foregroundColor(accentPink)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Override")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Schedule different routes by time of day")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Auto Assignment (first-time only)

    private func autoAssignWidgets() {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA") else { return }

        var changed = false

        // Only auto-assign if no assignment exists yet (nil means never set)
        if defaults.object(forKey: "mediumWidgetFavoriteIndex") == nil,
           viewModel.quickFavorites[safe: 0] != nil {
            defaults.set(0, forKey: "mediumWidgetFavoriteIndex")
            changed = true
        }

        if defaults.object(forKey: "smallWidget1FavoriteIndex") == nil,
           viewModel.quickFavorites[safe: 1] != nil {
            defaults.set(1, forKey: "smallWidget1FavoriteIndex")
            changed = true
        }

        if defaults.object(forKey: "smallWidget2FavoriteIndex") == nil,
           viewModel.quickFavorites[safe: 2] != nil {
            defaults.set(2, forKey: "smallWidget2FavoriteIndex")
            changed = true
        }

        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Time Override Sheet

struct TimeOverrideSheet: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var expandedOverrideID: String? = nil
    @State private var editingFavoriteForID: String? = nil

    private var savedFavorites: [SavedFavorite] {
        viewModel.quickFavorites.compactMap { $0 }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
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

                    Text("Time Overrides")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Explanation
                Text("Show a different route on a specific widget during certain hours — like your morning commute from 7–9 AM and evening commute from 4–7 PM.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if viewModel.widgetOverrides.isEmpty {
                            // Empty state
                            VStack(spacing: 12) {
                                Spacer().frame(height: 30)

                                Image(systemName: "clock.badge.questionmark")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color(white: 0.25))

                                Text("No overrides yet")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)

                                Text("Your widgets will show the same route all day.\nTap the button below to schedule a change.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.35))
                                    .multilineTextAlignment(.center)

                                Spacer().frame(height: 20)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(viewModel.widgetOverrides) { override in
                                overrideCard(override)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                // Add override button
                Button {
                    haptic(.medium)
                    withAnimation(.spring(response: 0.35)) {
                        viewModel.addWidgetOverride(for: .wide)
                        if let newID = viewModel.widgetOverrides.last?.id {
                            expandedOverrideID = newID
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Add Override")
                            .font(.system(size: 17, weight: .semibold))
                    }
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
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Override Card

    private func overrideCard(_ override: WidgetScheduleOverride) -> some View {
        let isExpanded = expandedOverrideID == override.id

        return VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            Button {
                haptic()
                withAnimation(.spring(response: 0.3)) {
                    expandedOverrideID = isExpanded ? nil : override.id
                    editingFavoriteForID = nil
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Widget slot pill
                        Text(override.widgetSlot.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(slotColor(for: override.widgetSlot))
                            )

                        // Route name
                        if let fav = override.favorite {
                            Text("\(fav.routeName) · \(fav.directionDestination)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                            Text("No route selected")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                        }

                        // Time range
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text("\(timeText(hour: override.startHour, minute: override.startMinute)) – \(timeText(hour: override.endHour, minute: override.endMinute))")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer()

                    // Delete button
                    Button {
                        haptic(.medium)
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.deleteWidgetOverride(id: override.id)
                            if expandedOverrideID == override.id {
                                expandedOverrideID = nil
                            }
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.red.opacity(0.1)))
                    }
                    .buttonStyle(.plain)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
            .padding(14)

            // Expanded editor
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Divider
                    Rectangle()
                        .fill(Color(white: 0.20))
                        .frame(height: 1)
                        .padding(.horizontal, 14)

                    // Widget slot selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WIDGET")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                            .tracking(0.8)
                            .padding(.horizontal, 14)

                        HStack(spacing: 8) {
                            ForEach(WidgetSlotType.allCases) { slot in
                                Button {
                                    haptic()
                                    viewModel.updateWidgetOverrideSlot(id: override.id, slot: slot)
                                } label: {
                                    Text(slotShortName(slot))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(override.widgetSlot == slot ? .white : .white.opacity(0.5))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(override.widgetSlot == slot ? slotColor(for: slot) : Color(white: 0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    // Route selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROUTE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                            .tracking(0.8)
                            .padding(.horizontal, 14)

                        if editingFavoriteForID == override.id {
                            // Show favorite list
                            VStack(spacing: 6) {
                                ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                                    if let fav = favorite {
                                        Button {
                                            haptic()
                                            viewModel.updateWidgetOverrideFavorite(id: override.id, favorite: fav)
                                            withAnimation(.spring(response: 0.25)) {
                                                editingFavoriteForID = nil
                                            }
                                        } label: {
                                            HStack(spacing: 10) {
                                                routeBadge(for: fav)

                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(fav.routeName)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(.white)
                                                    Text("\(fav.directionDestination) · \(fav.stopName)")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.white.opacity(0.4))
                                                        .lineLimit(1)
                                                }

                                                Spacer()

                                                if override.favorite?.routeID == fav.routeID &&
                                                   override.favorite?.directionID == fav.directionID &&
                                                   override.favorite?.stopID == fav.stopID {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                            .padding(10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color(white: 0.12))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            // Show current selection, tappable to change
                            Button {
                                haptic()
                                withAnimation(.spring(response: 0.25)) {
                                    editingFavoriteForID = override.id
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if let fav = override.favorite {
                                        routeBadge(for: fav)
                                        Text("\(fav.routeName) · \(fav.directionDestination)")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
                                    } else {
                                        Text("Tap to select a route")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.4))
                                    }

                                    Spacer()

                                    Text("Change")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.blue)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(white: 0.12))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                        }
                    }

                    // Time pickers
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TIME RANGE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                            .tracking(0.8)
                            .padding(.horizontal, 14)

                        HStack(spacing: 12) {
                            // Start time
                            VStack(spacing: 4) {
                                Text("From")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.35))

                                DatePicker(
                                    "Start",
                                    selection: startTimeBinding(for: override),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .colorScheme(.dark)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(white: 0.12))
                            )

                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))

                            // End time
                            VStack(spacing: 4) {
                                Text("To")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.35))

                                DatePicker(
                                    "End",
                                    selection: endTimeBinding(for: override),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .colorScheme(.dark)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(white: 0.12))
                            )
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(white: 0.20), lineWidth: 1)
                )
        )
    }

    // MARK: - Route Badge

    private func routeBadge(for favorite: SavedFavorite) -> some View {
        let route = favorite.routeID.uppercased()
        let color: Color = {
            if route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT") {
                return Color(red: 255/255, green: 200/255, blue: 0/255)
            }
            if route.contains("RED") || route.contains("MATTAPAN") { return Color(red: 218/255, green: 41/255, blue: 28/255) }
            if route.contains("ORANGE") { return Color(red: 237/255, green: 139/255, blue: 0/255) }
            if route.contains("BLUE") { return Color(red: 0/255, green: 115/255, blue: 207/255) }
            if route.contains("GREEN") { return Color(red: 0/255, green: 132/255, blue: 61/255) }
            if route.starts(with: "CR-") { return .purple }
            return Color(red: 255/255, green: 200/255, blue: 0/255)
        }()
        let textColor: Color = (route.allSatisfy({ $0.isNumber }) || route.starts(with: "SL") || route.starts(with: "CT")) ? .black : .white

        return Text(favorite.routeName)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(color))
    }

    // MARK: - Helpers

    private func slotColor(for slot: WidgetSlotType) -> Color {
        switch slot {
        case .wide: return .blue
        case .small1: return .green
        case .small2: return .orange
        }
    }

    private func slotShortName(_ slot: WidgetSlotType) -> String {
        switch slot {
        case .wide: return "Wide"
        case .small1: return "Small 1"
        case .small2: return "Small 2"
        }
    }

    private func startTimeBinding(for override: WidgetScheduleOverride) -> Binding<Date> {
        Binding(
            get: { dateFrom(hour: override.startHour, minute: override.startMinute) },
            set: { viewModel.updateWidgetOverrideStart(id: override.id, date: $0) }
        )
    }

    private func endTimeBinding(for override: WidgetScheduleOverride) -> Binding<Date> {
        Binding(
            get: { dateFrom(hour: override.endHour, minute: override.endMinute) },
            set: { viewModel.updateWidgetOverrideEnd(id: override.id, date: $0) }
        )
    }

    private func dateFrom(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func timeText(hour: Int, minute: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: dateFrom(hour: hour, minute: minute))
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    WidgetsView(viewModel: ArrivalsViewModel())
        .preferredColorScheme(.dark)
}
