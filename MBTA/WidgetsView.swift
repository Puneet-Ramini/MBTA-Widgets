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
                    .presentationBackground(.ultraThinMaterial)
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
                icon: "rectangle.fill",
                iconColor: .blue,
                assignedIndex: mediumWidgetFavoriteIndex,
                slot: .medium
            )

            widgetTile(
                title: "Small Widget 1",
                icon: "square.fill",
                iconColor: .green,
                assignedIndex: smallWidget1FavoriteIndex,
                slot: .small1
            )

            widgetTile(
                title: "Small Widget 2",
                icon: "square.fill",
                iconColor: .orange,
                assignedIndex: smallWidget2FavoriteIndex,
                slot: .small2
            )
        }
    }

    // MARK: - Widget Tile

    private func widgetTile(title: String, icon: String, iconColor: Color, assignedIndex: Int?, slot: WidgetSlot) -> some View {
        Button {
            editingWidget = slot
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    if let index = assignedIndex,
                       viewModel.quickFavorites.indices.contains(index),
                       let fav = viewModel.quickFavorites[index] {
                        Text("\(fav.routeName) • \(fav.stopName)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    } else {
                        Text("Tap to assign a favorite")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
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

        return VStack(spacing: 16) {
            // Handle bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text(slotTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Text("Choose a favorite to display")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            VStack(spacing: 8) {
                ForEach(Array(viewModel.quickFavorites.enumerated()), id: \.offset) { index, favorite in
                    if let fav = favorite {
                        Button {
                            assignFavorite(index: index, to: slot)
                            editingWidget = nil
                        } label: {
                            HStack(spacing: 12) {
                                routeBadge(for: fav)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fav.routeName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)

                                    Text("\(fav.directionDestination) • \(fav.stopName)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                        .lineLimit(1)
                                }

                                Spacer()

                                if isAssigned(index: index, to: slot) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(isAssigned(index: index, to: slot) ? 0.12 : 0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
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
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(color))
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
        NavigationLink {
            WidgetCustomizationView(viewModel: viewModel)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 20))
                    .foregroundColor(accentPink)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Override")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Set specific times for a different route")
                        .font(.system(size: 12))
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
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Auto Assignment

    private func autoAssignWidgets() {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA") else { return }

        var changed = false

        if viewModel.quickFavorites[safe: 0] != nil {
            if defaults.object(forKey: "mediumWidgetFavoriteIndex") as? Int != 0 {
                defaults.set(0, forKey: "mediumWidgetFavoriteIndex")
                changed = true
            }
        }

        if viewModel.quickFavorites[safe: 1] != nil {
            if defaults.object(forKey: "smallWidget1FavoriteIndex") as? Int != 1 {
                defaults.set(1, forKey: "smallWidget1FavoriteIndex")
                changed = true
            }
        }

        if viewModel.quickFavorites[safe: 2] != nil {
            if defaults.object(forKey: "smallWidget2FavoriteIndex") as? Int != 2 {
                defaults.set(2, forKey: "smallWidget2FavoriteIndex")
                changed = true
            }
        }

        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
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
