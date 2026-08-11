import SwiftUI
import WidgetKit
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Interactive Refresh Intent

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh MBTA Widget"
    static var description = IntentDescription("Fetches the latest arrival predictions.")
    
    func perform() async throws -> some IntentResult {
        // The timeline reload happens automatically when perform() returns.
        // By simply returning here, WidgetKit will call getTimeline() again,
        // which already fetches fresh data from the MBTA API.
        return .result()
    }
}

private enum WidgetTransportMode: String {
    case bus = "Bus"
    case subway = "Subway"
    case commuterRail = "Commuter Rail"

    var showsStopsAway: Bool {
        self == .bus
    }
}

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
        
        // Bus - Yellow
        if route.isBusRoute {
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
        } else if route.starts(with: "CR-") {
            return .purple
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

struct MBTAWidgetEntry: TimelineEntry {
    let date: Date
    let routeID: String?
    let routeName: String
    let directionID: Int?
    let directionLine: String
    let stopID: String?
    let stopName: String
    let predictions: [WidgetArrivalDisplay]
    let message: String?

    /// For badge display: buses show routeName (friendly name like "SL1"),
    /// others use routeID (has "CR-" prefix for commuter rail detection).
    var badgeKey: String {
        guard let routeID else { return routeName }
        // Bus routes: prefer routeName for display (routeID can be cryptic, e.g. "741" for SL1)
        if routeID.isBusRoute { return routeName }
        return routeID
    }
}

struct WidgetArrivalDisplay: Hashable {
    let arrivalDate: Date? // Store actual arrival date instead of text
    let minutesText: String // Keep for backward compatibility with previews
    let stopsAwayText: String
    var arrivalTimeText: String = "" // e.g. "1:50 PM"
    
    // Helper to calculate current minutes
    func minutesUntilArrival(from currentDate: Date) -> Int {
        guard let arrivalDate = arrivalDate else { return 0 }
        return max(Int(arrivalDate.timeIntervalSince(currentDate) / 60), 0)
    }
    
    func formattedMinutes(from currentDate: Date) -> String {
        guard let arrivalDate = arrivalDate else { return minutesText }
        let minutes = minutesUntilArrival(from: currentDate)
        if minutes < 1 {
            return "Now"
        }
        return "\(minutes) min"
    }
}

private struct WidgetArrivalSnapshot {
    let arrivalDate: Date
    let stopsAwayText: String
}

private struct WidgetContentState {
    let mode: WidgetTransportMode
    let routeID: String?
    let routeName: String
    let directionID: Int?
    let directionLine: String
    let stopID: String?
    let stopName: String
    let arrivals: [WidgetArrivalSnapshot]
    let message: String?
}

struct MBTAWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MBTAWidgetEntry {
        // This is shown in widget gallery and during loading
        let now = Date()
        return MBTAWidgetEntry(
            date: now,
            routeID: "39",
            routeName: "39",
            directionID: 0,
            directionLine: "To Back Bay Station",
            stopID: nil,
            stopName: "Huntington Ave @ Perkins St",
            predictions: [
                WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(6*60), minutesText: "6 min", stopsAwayText: "2 stops away"),
                WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(15*60), minutesText: "15 min", stopsAwayText: "5 stops away"),
                WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(22*60), minutesText: "22 min", stopsAwayText: "8 stops away")
            ],
            message: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MBTAWidgetEntry) -> Void) {
        // Always show nice preview in widget gallery
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            // For actual widget on home screen, try to load real data
            Task {
                let state = await loadState()
                let entry = buildPreviewEntry(from: state)
                completion(entry)
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MBTAWidgetEntry>) -> Void) {
        Task {
            let timeline = await loadTimeline()
            completion(timeline)
        }
    }
    
    private func buildPreviewEntry(from state: WidgetContentState) -> MBTAWidgetEntry {
        if let message = state.message {
            return MBTAWidgetEntry(
                date: Date(),
                routeID: state.routeID,
                routeName: state.routeName,
                directionID: state.directionID,
                directionLine: state.directionLine,
                stopID: state.stopID,
                stopName: state.stopName,
                predictions: [],
                message: message
            )
        }
        
        let predictions = state.arrivals.map { arrival in
            let timeText = Self.arrivalTimeFormatter.string(from: arrival.arrivalDate)
            return WidgetArrivalDisplay(
                arrivalDate: arrival.arrivalDate,
                minutesText: formatMinutes(arrival.arrivalDate),
                stopsAwayText: state.mode.showsStopsAway ? arrival.stopsAwayText : "",
                arrivalTimeText: timeText
            )
        }
        
        return MBTAWidgetEntry(
            date: Date(),
            routeID: state.routeID,
            routeName: state.routeName,
            directionID: state.directionID,
            directionLine: state.directionLine,
            stopID: state.stopID,
            stopName: state.stopName,
            predictions: predictions,
            message: nil
        )
    }
    
    private func formatMinutes(_ date: Date) -> String {
        let minutes = Int(date.timeIntervalSinceNow / 60)
        if minutes < 1 {
            return "Now"
        }
        return "\(minutes) min"
    }

    private func loadTimeline() async -> Timeline<MBTAWidgetEntry> {
        let state = await loadState()
        let now = Date()
        let entries = buildEntries(from: state, startingAt: now)
        
        // Refresh at the next override boundary so the widget switches routes on time,
        // or fall back to 1 minute (iOS throttles to ~15 min minimum in practice).
        let refreshDate = Self.nextOverrideBoundary(after: now, forSlot: "Wide Widget")
            ?? now.addingTimeInterval(60)
        
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func loadState() async -> WidgetContentState {
        // 1. Check time-based overrides first (they take priority when active)
        if let overrideFavorite = Self.loadTimeOverrideFavorite(forSlot: "Wide Widget") {
            return await loadStateForFavorite(overrideFavorite)
        }
        
        // 2. Fall back to widget assignment
        if let assignedFavorite = loadAssignedFavorite(widgetKey: "mediumWidgetFavoriteIndex") {
            return await loadStateForFavorite(assignedFavorite)
        }
        
        // 3. Fall back to the selection method (default config or legacy keys)
        guard let selection = StoredWidgetSelection.load() else {
            return WidgetContentState(
                mode: .bus,
                routeID: nil,
                routeName: "--",
                directionID: nil,
                directionLine: "Pick a route in the app",
                stopID: nil,
                stopName: "",
                arrivals: [],
                message: "Open the app and choose a bus, direction, and stop."
            )
        }

        do {
            let arrivals = try await WidgetMBTAService().fetchPredictions(
                mode: selection.mode,
                routeID: selection.routeID,
                stopID: selection.stopID,
                directionID: selection.directionID,
                routeName: selection.routeName,
                directionName: selection.directionLine,
                stopName: selection.stopName,
                source: "medium_widget"
            )

            return WidgetContentState(
                mode: selection.mode,
                routeID: selection.routeID,
                routeName: selection.routeName,
                directionID: selection.directionID,
                directionLine: selection.directionLine,
                stopID: selection.stopID,
                stopName: selection.stopName,
                arrivals: Array(arrivals.prefix(3)),
                message: arrivals.isEmpty ? "No upcoming buses right now." : nil
            )
        } catch {
            return WidgetContentState(
                mode: selection.mode,
                routeID: selection.routeID,
                routeName: selection.routeName,
                directionID: selection.directionID,
                directionLine: selection.directionLine,
                stopID: selection.stopID,
                stopName: selection.stopName,
                arrivals: [],
                message: "Could not load bus times."
            )
        }
    }
    
    /// Returns the next time an override for this slot starts or ends, so the timeline
    /// can refresh exactly when the active route should change.
    fileprivate static func nextOverrideBoundary(after date: Date, forSlot slot: String) -> Date? {
        guard
            let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
            let data = defaults.data(forKey: "widget.configuration"),
            let configuration = try? JSONDecoder().decode(WidgetStoredConfiguration.self, from: data)
        else {
            return nil
        }
        let calendar = Calendar.current
        let slotOverrides = configuration.overrides.filter { $0.widgetSlot == slot }
        guard !slotOverrides.isEmpty else { return nil }

        var candidates: [Date] = []
        for override in slotOverrides {
            // Build today's start and end dates
            if let start = calendar.date(bySettingHour: override.startHour, minute: override.startMinute, second: 0, of: date),
               start > date {
                candidates.append(start)
            }
            if let end = calendar.date(bySettingHour: override.endHour, minute: override.endMinute, second: 0, of: date),
               end > date {
                candidates.append(end)
            }
            // Also check tomorrow's start in case we're past today's boundaries
            if let tomorrowStart = calendar.date(bySettingHour: override.startHour, minute: override.startMinute, second: 0, of: date),
               let nextDay = calendar.date(byAdding: .day, value: 1, to: tomorrowStart),
               nextDay > date {
                candidates.append(nextDay)
            }
        }
        return candidates.min()
    }

    /// Checks if there's an active time-based override for the given widget slot.
    fileprivate static func loadTimeOverrideFavorite(forSlot slot: String) -> WidgetStoredFavorite? {
        guard
            let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
            let data = defaults.data(forKey: "widget.configuration"),
            let configuration = try? JSONDecoder().decode(WidgetStoredConfiguration.self, from: data)
        else {
            return nil
        }
        return configuration.activeFavorite(at: Date(), forSlot: slot)
    }
    
    private func loadAssignedFavorite(widgetKey: String) -> WidgetStoredFavorite? {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
              let favoriteIndex = defaults.object(forKey: widgetKey) as? Int else {
            return nil
        }
        
        guard let data = defaults.data(forKey: "quickFavorites"),
              let favorites = try? JSONDecoder().decode([WidgetStoredFavorite?].self, from: data),
              favoriteIndex < favorites.count,
              let favorite = favorites[favoriteIndex] else {
            return nil
        }
        
        return favorite
    }
    
    private func loadStateForFavorite(_ favorite: WidgetStoredFavorite) async -> WidgetContentState {
        let mode = WidgetTransportMode(rawValue: favorite.mode) ?? .bus
        let directionLine: String
        if !favorite.directionDestination.isEmpty {
            directionLine = "To \(favorite.directionDestination)"
        } else if !favorite.directionName.isEmpty {
            directionLine = favorite.directionName
        } else {
            directionLine = ""
        }
        
        do {
            let arrivals = try await WidgetMBTAService().fetchPredictions(
                mode: mode,
                routeID: favorite.routeID,
                stopID: favorite.stopID,
                directionID: favorite.directionID,
                routeName: favorite.routeName,
                directionName: directionLine,
                stopName: favorite.stopName,
                source: "medium_widget"
            )
            
            return WidgetContentState(
                mode: mode,
                routeID: favorite.routeID,
                routeName: favorite.routeName,
                directionID: favorite.directionID,
                directionLine: directionLine,
                stopID: favorite.stopID,
                stopName: favorite.stopName,
                arrivals: Array(arrivals.prefix(3)),
                message: arrivals.isEmpty ? "No upcoming arrivals." : nil
            )
        } catch {
            return WidgetContentState(
                mode: mode,
                routeID: favorite.routeID,
                routeName: favorite.routeName,
                directionID: favorite.directionID,
                directionLine: directionLine,
                stopID: favorite.stopID,
                stopName: favorite.stopName,
                arrivals: [],
                message: "Could not load times."
            )
        }
    }

    private func buildEntries(from state: WidgetContentState, startingAt startDate: Date) -> [MBTAWidgetEntry] {
        // Create a single entry with arrival dates stored
        // The view will calculate minutes dynamically based on current time
        let entry = MBTAWidgetEntry(
            date: startDate,
            routeID: state.routeID,
            routeName: state.routeName,
            directionID: state.directionID,
            directionLine: state.directionLine,
            stopID: state.stopID,
            stopName: state.stopName,
            predictions: state.arrivals.prefix(3).map { arrival in
                let minutes = max(Int(arrival.arrivalDate.timeIntervalSince(startDate) / 60), 0)
                let timeText = Self.arrivalTimeFormatter.string(from: arrival.arrivalDate)
                return WidgetArrivalDisplay(
                    arrivalDate: arrival.arrivalDate,
                    minutesText: minutes < 1 ? "Now" : "\(minutes) min",
                    stopsAwayText: state.mode.showsStopsAway ? arrival.stopsAwayText : "",
                    arrivalTimeText: timeText
                )
            },
            message: state.message
        )

        return [entry]
    }

    private func displays(for arrivals: [WidgetArrivalSnapshot], at date: Date, mode: WidgetTransportMode) -> [WidgetArrivalDisplay] {
        arrivals
            .filter { $0.arrivalDate >= date }
            .prefix(3)
            .map { arrival in
                let minutes = max(Int(arrival.arrivalDate.timeIntervalSince(date) / 60), 0)
                let timeText = Self.arrivalTimeFormatter.string(from: arrival.arrivalDate)
                return WidgetArrivalDisplay(
                    arrivalDate: arrival.arrivalDate,
                    minutesText: minutes < 1 ? "Now" : "\(minutes) min",
                    stopsAwayText: mode.showsStopsAway ? arrival.stopsAwayText : "",
                    arrivalTimeText: timeText
                )
            }
    }

    fileprivate static let arrivalTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()
}

struct MBTAWidgetEntryView: View {
    var entry: MBTAWidgetProvider.Entry
    @Environment(\.widgetRenderingMode) var renderingMode
    
    private var isAccented: Bool { renderingMode == .accented }
    private let mbtaBlue = Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row: route badge + direction/stop + refresh button
            HStack(alignment: .top) {
                Text(entry.badgeKey.displayRouteName)
                    .font(.headline)
                    .bold()
                    .foregroundColor(isAccented ? .primary : entry.badgeKey.routeTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isAccented ? Color.primary.opacity(0.2) : entry.badgeKey.routeBadgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .widgetAccentable()

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.directionLine)
                        .font(.subheadline)
                        .bold()
                        .lineLimit(2)

                    if !entry.stopName.isEmpty {
                        Text(entry.stopName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Refresh button
                if #available(iOS 17.0, *) {
                    Button(intent: RefreshWidgetIntent()) {
                        VStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isAccented ? .primary : .white)
                                .frame(width: 30, height: 30)
                                .background(isAccented ? Color.primary.opacity(0.2) : mbtaBlue)
                                .clipShape(Circle())
                                .widgetAccentable()
                            Text(entry.date, style: .time)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Updated")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(entry.date, style: .time)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let message = entry.message {
                Spacer()
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                Spacer(minLength: 6)
                
                // Arrival predictions
                HStack(spacing: 8) {
                    ForEach(Array(entry.predictions.enumerated()), id: \.offset) { index, prediction in
                        VStack(spacing: 4) {
                            Text(prediction.formattedMinutes(from: entry.date))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(isAccented ? .primary : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 6)
                                .background(isAccented ? Color.primary.opacity(0.15) : mbtaBlue)
                                .clipShape(Capsule())
                                .widgetAccentable()

                            Text(prediction.arrivalTimeText.isEmpty ? " " : prediction.arrivalTimeText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            Text(prediction.stopsAwayText.isEmpty ? " " : prediction.stopsAwayText)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }

                    if entry.predictions.count < 3 {
                        ForEach(entry.predictions.count..<3, id: \.self) { _ in
                            VStack(spacing: 4) {
                                Text("--")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(isAccented ? .primary.opacity(0.5) : .white.opacity(0.85))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 6)
                                    .background(isAccented ? Color.primary.opacity(0.1) : mbtaBlue)
                                    .clipShape(Capsule())

                                Text(" ")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
                
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
        .widgetURL(Self.widgetDeepLink(entry: entry))
    }
    
    private static func widgetDeepLink(entry: MBTAWidgetEntry) -> URL {
        var components = URLComponents()
        components.scheme = "mbta-widget"
        components.host = "open"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "route", value: entry.routeName)
        ]
        if let routeID = entry.routeID {
            items.append(URLQueryItem(name: "routeID", value: routeID))
        }
        if let directionID = entry.directionID {
            items.append(URLQueryItem(name: "directionID", value: String(directionID)))
        }
        if let stopID = entry.stopID {
            items.append(URLQueryItem(name: "stopID", value: stopID))
        }
        items.append(URLQueryItem(name: "stop", value: entry.stopName))
        components.queryItems = items
        return components.url ?? URL(string: "mbta-widget://open")!
    }
}

struct MBTAWidget: Widget {
    let kind: String = "MBTAWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MBTAWidgetProvider()) { entry in
            MBTAWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MBTA Arrivals")
        .description("Next 3 arrivals for your stop. Customize in app under Widget Assignments.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Small Favorite Widgets

struct SmallFavoriteWidgetProvider: TimelineProvider {
    let favoriteIndex: Int
    
    func placeholder(in context: Context) -> MBTAWidgetEntry {
        let now = Date()
        if favoriteIndex == 0 {
            return MBTAWidgetEntry(
                date: now,
                routeID: "39",
                routeName: "39",
                directionID: 0,
                directionLine: "To Back Bay Station",
                stopID: nil,
                stopName: "",
                predictions: [
                    WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(2*60), minutesText: "2 min", stopsAwayText: ""),
                    WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(6*60), minutesText: "6 min", stopsAwayText: "")
                ],
                message: nil
            )
        } else {
            return MBTAWidgetEntry(
                date: now,
                routeID: "CT2",
                routeName: "CT2",
                directionID: 0,
                directionLine: "To Sullivan Square",
                stopID: nil,
                stopName: "",
                predictions: [
                    WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(5*60), minutesText: "5 min", stopsAwayText: ""),
                    WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(12*60), minutesText: "12 min", stopsAwayText: "")
                ],
                message: nil
            )
        }
    }
    
    func getSnapshot(in context: Context, completion: @escaping (MBTAWidgetEntry) -> Void) {
        // For widget gallery, show placeholder
        // For actual widget (edit mode), load real data
        Task {
            let state = await loadState()
            let entry = buildPreviewEntry(from: state)
            completion(entry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<MBTAWidgetEntry>) -> Void) {
        Task {
            let timeline = await loadTimeline()
            completion(timeline)
        }
    }
    
    private func buildPreviewEntry(from state: WidgetContentState) -> MBTAWidgetEntry {
        if let message = state.message {
            return MBTAWidgetEntry(
                date: Date(),
                routeID: state.routeID,
                routeName: state.routeName,
                directionID: state.directionID,
                directionLine: state.directionLine,
                stopID: state.stopID,
                stopName: state.stopName,
                predictions: [],
                message: message
            )
        }
        
        let predictions = state.arrivals.prefix(2).map { arrival in
            WidgetArrivalDisplay(
                arrivalDate: arrival.arrivalDate,
                minutesText: formatMinutes(arrival.arrivalDate),
                stopsAwayText: ""
            )
        }
        
        return MBTAWidgetEntry(
            date: Date(),
            routeID: state.routeID,
            routeName: state.routeName,
            directionID: state.directionID,
            directionLine: state.directionLine,
            stopID: state.stopID,
            stopName: state.stopName,
            predictions: Array(predictions),
            message: nil
        )
    }
    
    private func formatMinutes(_ date: Date) -> String {
        let minutes = Int(date.timeIntervalSinceNow / 60)
        if minutes < 1 {
            return "Now"
        }
        return "\(minutes) min"
    }
    
    private func loadTimeline() async -> Timeline<MBTAWidgetEntry> {
        let state = await loadState()
        let now = Date()
        let entries = buildEntries(from: state, startingAt: now)
        
        // Refresh at the next override boundary so the widget switches routes on time,
        // or fall back to 1 minute (iOS throttles to ~15 min minimum in practice).
        let slotName = favoriteIndex == 0 ? "Small Widget 1" : "Small Widget 2"
        let refreshDate = MBTAWidgetProvider.nextOverrideBoundary(after: now, forSlot: slotName)
            ?? now.addingTimeInterval(60)
        
        return Timeline(entries: entries, policy: .after(refreshDate))
    }
    
    private func loadState() async -> WidgetContentState {
        // 1. Check time-based overrides first (they take priority when active)
        let slotName = favoriteIndex == 0 ? "Small Widget 1" : "Small Widget 2"
        if let overrideFavorite = MBTAWidgetProvider.loadTimeOverrideFavorite(forSlot: slotName) {
            return await loadStateForFavorite(overrideFavorite)
        }
        
        // 2. Fall back to widget assignment
        let widgetKey: String
        if favoriteIndex == 0 {
            widgetKey = "smallWidget1FavoriteIndex"
        } else {
            widgetKey = "smallWidget2FavoriteIndex"
        }
        
        if let assignedFavoriteIndex = loadAssignedFavoriteIndex(widgetKey: widgetKey),
           let favorite = loadFavorite(at: assignedFavoriteIndex) {
            return await loadStateForFavorite(favorite)
        }
        
        // 3. Fall back to direct favorite index
        guard let favorite = loadFavorite(at: favoriteIndex) else {
            return WidgetContentState(
                mode: .bus,
                routeID: nil,
                routeName: "--",
                directionID: nil,
                directionLine: "Set Favorite \(favoriteIndex + 1)",
                stopID: nil,
                stopName: "",
                arrivals: [],
                message: "Open the app to set this favorite."
            )
        }
        
        return await loadStateForFavorite(favorite)
    }
    
    private func loadAssignedFavoriteIndex(widgetKey: String) -> Int? {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
              let index = defaults.object(forKey: widgetKey) as? Int else {
            return nil
        }
        return index
    }
    
    private func loadStateForFavorite(_ favorite: WidgetStoredFavorite) async -> WidgetContentState {
        let mode = WidgetTransportMode(rawValue: favorite.mode) ?? .bus
        let directionLine: String
        if !favorite.directionDestination.isEmpty {
            directionLine = "To \(favorite.directionDestination)"
        } else if !favorite.directionName.isEmpty {
            directionLine = favorite.directionName
        } else {
            directionLine = ""
        }
        
        do {
            let arrivals = try await WidgetMBTAService().fetchPredictions(
                mode: mode,
                routeID: favorite.routeID,
                stopID: favorite.stopID,
                directionID: favorite.directionID,
                routeName: favorite.routeName,
                directionName: directionLine,
                stopName: favorite.stopName,
                source: "small_widget_fav\(favoriteIndex + 1)"
            )
            
            return WidgetContentState(
                mode: mode,
                routeID: favorite.routeID,
                routeName: favorite.routeName,
                directionID: favorite.directionID,
                directionLine: directionLine,
                stopID: favorite.stopID,
                stopName: favorite.stopName,
                arrivals: Array(arrivals.prefix(2)),
                message: arrivals.isEmpty ? "No upcoming arrivals." : nil
            )
        } catch {
            return WidgetContentState(
                mode: mode,
                routeID: favorite.routeID,
                routeName: favorite.routeName,
                directionID: favorite.directionID,
                directionLine: directionLine,
                stopID: favorite.stopID,
                stopName: favorite.stopName,
                arrivals: [],
                message: "Could not load times."
            )
        }
    }
    
    private func loadFavorite(at index: Int) -> WidgetStoredFavorite? {
        guard
            let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
            let data = defaults.data(forKey: "quickFavorites"),
            let favorites = try? JSONDecoder().decode([WidgetStoredFavorite?].self, from: data),
            index < favorites.count
        else {
            return nil
        }
        
        return favorites[index]
    }
    
    private func buildEntries(from state: WidgetContentState, startingAt startDate: Date) -> [MBTAWidgetEntry] {
        // Single entry with arrival dates stored for dynamic calculation
        let entry = MBTAWidgetEntry(
            date: startDate,
            routeID: state.routeID,
            routeName: state.routeName,
            directionID: state.directionID,
            directionLine: state.directionLine,
            stopID: state.stopID,
            stopName: state.stopName,
            predictions: state.arrivals.prefix(2).map { arrival in
                let minutes = max(Int(arrival.arrivalDate.timeIntervalSince(startDate) / 60), 0)
                return WidgetArrivalDisplay(
                    arrivalDate: arrival.arrivalDate,
                    minutesText: minutes < 1 ? "Now" : "\(minutes) min",
                    stopsAwayText: ""
                )
            },
            message: state.message
        )
        
        return [entry]
    }
    
    private func displays(for arrivals: [WidgetArrivalSnapshot], at date: Date) -> [WidgetArrivalDisplay] {
        arrivals
            .filter { $0.arrivalDate >= date }
            .prefix(2)
            .map { arrival in
                let minutes = max(Int(arrival.arrivalDate.timeIntervalSince(date) / 60), 0)
                return WidgetArrivalDisplay(
                    arrivalDate: arrival.arrivalDate,
                    minutesText: minutes < 1 ? "Now" : "\(minutes) min",
                    stopsAwayText: ""
                )
            }
    }
}

struct SmallFavoriteWidgetView: View {
    var entry: MBTAWidgetEntry
    @Environment(\.widgetRenderingMode) var renderingMode
    
    private var isAccented: Bool { renderingMode == .accented }
    private let mbtaBlue = Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                // Route badge
                Text(entry.badgeKey.displayRouteName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isAccented ? .primary : entry.badgeKey.routeTextColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(isAccented ? Color.primary.opacity(0.2) : entry.badgeKey.routeBadgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .widgetAccentable()
                
                Spacer()
                
                // Refresh button
                if #available(iOS 17.0, *) {
                    Button(intent: RefreshWidgetIntent()) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isAccented ? .primary : .white)
                                .frame(width: 22, height: 22)
                                .background(isAccented ? Color.primary.opacity(0.2) : mbtaBlue)
                                .clipShape(Circle())
                                .widgetAccentable()
                            Text(entry.date, style: .time)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Updated")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(entry.date, style: .time)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Direction
            Text(entry.directionLine)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)
            
            // Stop name
            if !entry.stopName.isEmpty {
                Text(entry.stopName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 1)
            
            // Arrival times
            if let message = entry.message {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(entry.predictions.prefix(2).enumerated()), id: \.offset) { index, prediction in
                        Text(prediction.formattedMinutes(from: entry.date))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isAccented ? .primary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(isAccented ? Color.primary.opacity(0.15) : mbtaBlue)
                            .clipShape(Capsule())
                            .widgetAccentable()
                    }
                    
                    // Fill remaining slots
                    ForEach(entry.predictions.count..<2, id: \.self) { _ in
                        Text("--")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isAccented ? .primary.opacity(0.5) : .white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(isAccented ? Color.primary.opacity(0.1) : mbtaBlue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
        .widgetURL(Self.widgetDeepLink(entry: entry))
    }
    
    private static func widgetDeepLink(entry: MBTAWidgetEntry) -> URL {
        var components = URLComponents()
        components.scheme = "mbta-widget"
        components.host = "open"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "route", value: entry.routeName)
        ]
        if let routeID = entry.routeID {
            items.append(URLQueryItem(name: "routeID", value: routeID))
        }
        if let directionID = entry.directionID {
            items.append(URLQueryItem(name: "directionID", value: String(directionID)))
        }
        if let stopID = entry.stopID {
            items.append(URLQueryItem(name: "stopID", value: stopID))
        }
        items.append(URLQueryItem(name: "stop", value: entry.stopName))
        components.queryItems = items
        return components.url ?? URL(string: "mbta-widget://open")!
    }
}

struct SmallFavorite1Widget: Widget {
    let kind: String = "SmallFavorite1Widget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmallFavoriteWidgetProvider(favoriteIndex: 0)) { entry in
            SmallFavoriteWidgetView(entry: entry)
        }
        .configurationDisplayName("Favorite 1")
        .description("Next 2 arrivals for Favorite 1. Customize in app under Widget Assignments.")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallFavorite2Widget: Widget {
    let kind: String = "SmallFavorite2Widget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmallFavoriteWidgetProvider(favoriteIndex: 1)) { entry in
            SmallFavoriteWidgetView(entry: entry)
        }
        .configurationDisplayName("Favorite 2")
        .description("Next 2 arrivals for Favorite 2. Customize in app under Widget Assignments.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct MBTAWidgetBundle: WidgetBundle {
    var body: some Widget {
        MBTAWidget()
        SmallFavorite1Widget()
        SmallFavorite2Widget()
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            BusArrivalLiveActivity()
        }
        #endif
    }
}

// ⛔️ DO NOT MODIFY ANYTHING BELOW THIS LINE UNTIL #endif — Live Activity / Dynamic Island code. It is sealed and working. Any changes risk breaking it.
// MARK: - Live Activity
#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct BusArrivalLiveActivity: Widget {
    /// Badge key for Live Activity: buses show routeName, others use routeID
    private static func badgeKey(for attributes: BusArrivalAttributes) -> String {
        if attributes.routeID.isBusRoute { return attributes.routeName }
        return attributes.routeID
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusArrivalAttributes.self) { context in
            // Lock Screen & Banner UI
            let badge = Self.badgeKey(for: context.attributes)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(badge.displayRouteName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(badge.routeTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badge.routeBadgeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.destination)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        
                        Text(context.attributes.stopName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text(context.state.minutesText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    .background(Color(red: 0/255, green: 57/255, blue: 166/255))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .widgetURL(Self.liveActivityDeepLink(attributes: context.attributes))
        } dynamicIsland: { context in
            let badge = Self.badgeKey(for: context.attributes)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(badge.displayRouteName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(badge.routeTextColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(badge.routeBadgeColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("To")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(context.attributes.destination)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(spacing: 4) {
                        Text(context.state.minutesText)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0/255, green: 57/255, blue: 166/255))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } compactLeading: {
                Text(badge.displayRouteName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(badge.routeTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(badge.routeBadgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } compactTrailing: {
                Text(context.state.minutesText)
                    .font(.system(size: 13, weight: .bold))
                    .frame(minWidth: 36)
            } minimal: {
                Text(context.state.minutesText)
                    .font(.system(size: 11, weight: .bold))
            }
            .widgetURL(Self.liveActivityDeepLink(attributes: context.attributes))
        }
    }
    
    private static func liveActivityDeepLink(attributes: BusArrivalAttributes) -> URL {
        var components = URLComponents()
        components.scheme = "mbta-widget"
        components.host = "open"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "route", value: attributes.routeName),
            URLQueryItem(name: "routeID", value: attributes.routeID),
            URLQueryItem(name: "stopID", value: attributes.stopID),
            URLQueryItem(name: "stop", value: attributes.stopName)
        ]
        if let directionID = attributes.directionID {
            items.append(URLQueryItem(name: "directionID", value: String(directionID)))
        }
        components.queryItems = items
        return components.url ?? URL(string: "mbta-widget://open")!
    }
}
#endif

// MARK: - Previews
#Preview(as: .systemMedium) {
    MBTAWidget()
} timeline: {
    let now = Date()
    MBTAWidgetEntry(
        date: now,
        routeID: "39",
        routeName: "39",
        directionID: 0,
        directionLine: "To Back Bay Station",
        stopID: nil,
        stopName: "Huntington Ave @ Perkins St",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(6*60), minutesText: "6 min", stopsAwayText: "2 stops away", arrivalTimeText: "1:36 PM"),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(15*60), minutesText: "15 min", stopsAwayText: "5 stops away", arrivalTimeText: "1:45 PM"),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(22*60), minutesText: "22 min", stopsAwayText: "8 stops away", arrivalTimeText: "1:52 PM")
        ],
        message: nil
    )
    
    MBTAWidgetEntry(
        date: now.addingTimeInterval(60),
        routeID: "39",
        routeName: "39",
        directionID: 0,
        directionLine: "To Back Bay Station",
        stopID: nil,
        stopName: "Huntington Ave @ Perkins St",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(5*60), minutesText: "5 min", stopsAwayText: "2 stops away", arrivalTimeText: "1:35 PM"),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(14*60), minutesText: "14 min", stopsAwayText: "5 stops away", arrivalTimeText: "1:44 PM"),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(21*60), minutesText: "21 min", stopsAwayText: "8 stops away", arrivalTimeText: "1:51 PM")
        ],
        message: nil
    )
}

private struct StoredWidgetSelection {
    let mode: WidgetTransportMode
    let routeID: String
    let routeName: String
    let directionID: Int?
    let directionLine: String
    let stopID: String
    let stopName: String

    static func load() -> StoredWidgetSelection? {
        if let configuredSelection = loadConfiguredSelection() {
            return configuredSelection
        }

        guard
            let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
            let modeValue = defaults.string(forKey: "widget.mode"),
            let mode = WidgetTransportMode(rawValue: modeValue),
            let routeID = defaults.string(forKey: "widget.routeID"),
            let routeName = defaults.string(forKey: "widget.routeName"),
            let stopID = defaults.string(forKey: "widget.stopID"),
            let stopName = defaults.string(forKey: "widget.stopName")
        else {
            return nil
        }

        let directionID = defaults.object(forKey: "widget.directionID") as? Int
        let directionName = defaults.string(forKey: "widget.directionName") ?? ""
        let destination = defaults.string(forKey: "widget.directionDestination") ?? ""
        let directionLine: String

        if !destination.isEmpty {
            directionLine = "To \(destination)"
        } else if !directionName.isEmpty {
            directionLine = directionName
        } else {
            directionLine = ""
        }

        return StoredWidgetSelection(
            mode: mode,
            routeID: routeID,
            routeName: routeName,
            directionID: directionID,
            directionLine: directionLine,
            stopID: stopID,
            stopName: stopName
        )
    }

    private static func loadConfiguredSelection() -> StoredWidgetSelection? {
        guard
            let defaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
            let data = defaults.data(forKey: "widget.configuration"),
            let configuration = try? JSONDecoder().decode(WidgetStoredConfiguration.self, from: data)
        else {
            return nil
        }

        // Time overrides are handled earlier with slot filtering;
        // this path only returns the default favorite.
        guard let favorite = configuration.defaultFavorite else {
            return nil
        }

        let mode = WidgetTransportMode(rawValue: favorite.mode) ?? .bus
        let directionLine: String
        if !favorite.directionDestination.isEmpty {
            directionLine = "To \(favorite.directionDestination)"
        } else if !favorite.directionName.isEmpty {
            directionLine = favorite.directionName
        } else {
            directionLine = ""
        }

        return StoredWidgetSelection(
            mode: mode,
            routeID: favorite.routeID,
            routeName: favorite.routeName,
            directionID: favorite.directionID,
            directionLine: directionLine,
            stopID: favorite.stopID,
            stopName: favorite.stopName
        )
    }
}

private struct WidgetStoredConfiguration: Decodable {
    let defaultFavorite: WidgetStoredFavorite?
    let overrides: [WidgetStoredOverride]

    func activeFavorite(at date: Date, forSlot slot: String? = nil) -> WidgetStoredFavorite? {
        let filtered = slot != nil
            ? overrides.filter { $0.widgetSlot == slot }
            : overrides
        return filtered.first(where: { $0.isActive(at: date) })?.favorite
    }
}

private struct WidgetStoredOverride: Decodable {
    let id: String
    let widgetSlot: String?
    let favorite: WidgetStoredFavorite?
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int

    func isActive(at date: Date) -> Bool {
        let calendar = Calendar.current
        let nowMinutes = (calendar.component(.hour, from: date) * 60) + calendar.component(.minute, from: date)
        let startMinutes = (startHour * 60) + startMinute
        let endMinutes = (endHour * 60) + endMinute

        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        }

        return nowMinutes >= startMinutes || nowMinutes < endMinutes
    }
}

private struct WidgetStoredFavorite: Decodable {
    let mode: String
    let routeID: String
    let routeName: String
    let directionID: Int
    let directionName: String
    let directionDestination: String
    let stopID: String
    let stopName: String
}

// MARK: - Widget Firebase Logging
private enum WidgetFirebaseLogger {
    // Firebase project config — hardcoded for widget extension since it can't use FirebaseApp.configure()
    private static let projectID = "mbta-widgets"
    private static let apiKey = "AIzaSyAcIWs06AICYqzTmLNt2vrgLd2rHKdt95c"

    /// Cached device ID — read once from Keychain (shared with the main app)
    private static let _deviceID: String = {
        let service = "com.mbta.monitoring"
        let account = "deviceID"

        // 1. Try Keychain (same location the main app uses)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let existing = String(data: data, encoding: .utf8) {
            return existing
        }

        // 2. Fall back to app group UserDefaults (migration from old widget ID)
        let defaults = UserDefaults(suiteName: "group.Widgets.MBTA")
        if let existing = defaults?.string(forKey: "deviceID") {
            // Migrate to Keychain so it stays in sync with the app
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: Data(existing.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
            return existing
        }

        // 3. Generate new ID and save to both Keychain and app group
        let newID = UUID().uuidString
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(newID.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        defaults?.set(newID, forKey: "deviceID")
        return newID
    }()

    static var deviceID: String { _deviceID }

    static func logAPICall(endpoint: String, statusCode: Int?, responseTimeMs: Int?, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil, source: String = "widget") {
        Task.detached {
            await incrementDailyStats(deviceId: deviceID)
        }
    }

    // MARK: - Daily Stats (REST)

    /// ET date key (YYYY-MM-DD)
    private static func todayET() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f.string(from: Date())
    }

    private static let firestoreBase = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents"

    /// Increment total_api_calls via Firestore commit with a fieldTransform (1 write, 0 reads).
    private static func incrementDailyStats(deviceId: String) async {
        let dateKey = todayET()

        let statsPath = "projects/\(projectID)/databases/(default)/documents/daily_stats/\(dateKey)"

        let incrementCommit: [String: Any] = [
            "writes": [[
                "transform": [
                    "document": statsPath,
                    "fieldTransforms": [
                        [
                            "fieldPath": "total_api_calls",
                            "increment": ["integerValue": "1"]
                        ]
                    ]
                ]
            ],
            // Ensure the date field exists
            [
                "update": [
                    "name": statsPath,
                    "fields": [
                        "date": ["stringValue": dateKey]
                    ]
                ],
                "updateMask": ["fieldPaths": ["date"]]
            ]]
        ]

        guard let commitURL = URL(string: "\(firestoreBase):commit?key=\(apiKey)") else { return }
        var req = URLRequest(url: commitURL)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: incrementCommit)
        _ = try? await URLSession.shared.data(for: req)
    }
}

private struct WidgetPredictionsResponse: Decodable {
    let data: [WidgetPredictionData]
}

private struct WidgetPredictionData: Decodable {
    let attributes: WidgetPredictionAttributes
    let relationships: WidgetPredictionRelationships?
}

private struct WidgetPredictionAttributes: Decodable {
    let arrivalTime: Date?
    let departureTime: Date?
    let stopSequence: Int?

    enum CodingKeys: String, CodingKey {
        case arrivalTime = "arrival_time"
        case departureTime = "departure_time"
        case stopSequence = "stop_sequence"
    }
}

private struct WidgetPredictionRelationships: Decodable {
    let vehicle: WidgetRelationship?
}

private struct WidgetRelationship: Decodable {
    let data: WidgetRelationshipData?
}

private struct WidgetRelationshipData: Decodable {
    let id: String
}

private struct WidgetVehiclesResponse: Decodable {
    let data: [WidgetVehicleData]
}

private struct WidgetVehicleData: Decodable {
    let id: String
    let attributes: WidgetVehicleAttributes
}

private struct WidgetVehicleAttributes: Decodable {
    let currentStopSequence: Int?

    enum CodingKeys: String, CodingKey {
        case currentStopSequence = "current_stop_sequence"
    }
}

private struct WidgetSchedulesResponse: Decodable {
    let data: [WidgetScheduleData]
}

private struct WidgetScheduleData: Decodable {
    let id: String
    let attributes: WidgetScheduleAttributes
}

private struct WidgetScheduleAttributes: Decodable {
    let arrivalTime: Date?
    let departureTime: Date?

    enum CodingKeys: String, CodingKey {
        case arrivalTime = "arrival_time"
        case departureTime = "departure_time"
    }
}

private struct WidgetMBTAService {
    private let apiKey = "6aaf4b37ca464bc298e7573999c87d4d"

    func fetchPredictions(mode: WidgetTransportMode, routeID: String, stopID: String, directionID: Int? = nil, routeName: String? = nil, directionName: String? = nil, stopName: String? = nil, source: String = "widget") async throws -> [WidgetArrivalSnapshot] {
        let isCommuterRail = mode == .commuterRail
        var components = URLComponents(string: "https://api-v3.mbta.com/predictions")!
        components.queryItems = [
            URLQueryItem(name: "filter[route]", value: routeID),
            URLQueryItem(name: "filter[stop]", value: stopID),
            URLQueryItem(name: "sort", value: isCommuterRail ? "departure_time" : "arrival_time"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        if let directionID {
            components.queryItems?.append(
                URLQueryItem(name: "filter[direction_id]", value: String(directionID))
            )
        }

        guard let url = components.url else { throw URLError(.badURL) }
        var didRecord = false
        let startTime = Date()
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(from: url)
            let responseTime = Int(Date().timeIntervalSince(startTime) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            WidgetAPIUsageStore.record(url: url, statusCode: statusCode, source: source)
            
            // Log to Firebase
            WidgetFirebaseLogger.logAPICall(
                endpoint: "predictions",
                statusCode: statusCode,
                responseTimeMs: responseTime,
                routeName: routeName,
                directionName: directionName,
                stopName: stopName,
                source: source
            )
            
            didRecord = true
        } catch {
            if !didRecord {
                WidgetAPIUsageStore.record(url: url, statusCode: nil, source: source)
                WidgetFirebaseLogger.logAPICall(endpoint: "predictions", statusCode: nil, responseTimeMs: nil, routeName: routeName, directionName: directionName, stopName: stopName, source: source)
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetPredictionsResponse.self, from: data)
        let now = Date()
        let vehiclesByID: [String: Int]
        if mode.showsStopsAway {
            let vehicleIDs = decoded.data.compactMap { $0.relationships?.vehicle?.data?.id }
            vehiclesByID = (try? await fetchVehicles(ids: vehicleIDs, source: source)) ?? [:]
        } else {
            vehiclesByID = [:]
        }

        let predictions = decoded.data
            .compactMap { prediction -> WidgetArrivalSnapshot? in
                let attrs = prediction.attributes
                // Commuter rail: prefer departure time; bus/subway: prefer arrival time
                let date = isCommuterRail
                    ? (attrs.departureTime ?? attrs.arrivalTime)
                    : (attrs.arrivalTime ?? attrs.departureTime)
                
                guard let date, date >= now else {
                    return nil
                }

                let vehicleID = prediction.relationships?.vehicle?.data?.id
                let currentStopSequence = vehicleID.flatMap { vehiclesByID[$0] }
                let minutesAway = max(Int(date.timeIntervalSince(now) / 60), 0)

                return WidgetArrivalSnapshot(
                    arrivalDate: date,
                    stopsAwayText: formatStopsAway(
                        targetStopSequence: attrs.stopSequence,
                        currentStopSequence: currentStopSequence,
                        minutesAway: minutesAway
                    )
                )
            }
            .sorted { $0.arrivalDate < $1.arrivalDate }
            .prefix(3)
            .map { $0 }
        
        // For commuter rail, fall back to schedules when predictions are empty
        if predictions.isEmpty && isCommuterRail {
            return try await fetchSchedules(routeID: routeID, stopID: stopID, directionID: directionID, source: source)
        }
        
        return predictions
    }

    private func fetchVehicles(ids: [String], source: String = "widget") async throws -> [String: Int] {
        let uniqueIDs = Array(Set(ids)).sorted()

        guard !uniqueIDs.isEmpty else {
            return [:]
        }

        var components = URLComponents(string: "https://api-v3.mbta.com/vehicles")!
        components.queryItems = [
            URLQueryItem(name: "filter[id]", value: uniqueIDs.joined(separator: ",")),
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        var didRecord = false
        let startTime = Date()
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(from: url)
            let responseTime = Int(Date().timeIntervalSince(startTime) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            WidgetAPIUsageStore.record(url: url, statusCode: statusCode, source: source)
            
            // Log to Firebase
            WidgetFirebaseLogger.logAPICall(
                endpoint: "vehicles",
                statusCode: statusCode,
                responseTimeMs: responseTime,
                source: source
            )
            
            didRecord = true
        } catch {
            if !didRecord {
                WidgetAPIUsageStore.record(url: url, statusCode: nil, source: source)
                WidgetFirebaseLogger.logAPICall(endpoint: "vehicles", statusCode: nil, responseTimeMs: nil, source: source)
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(WidgetVehiclesResponse.self, from: data)
        return decoded.data.reduce(into: [:]) { partialResult, vehicle in
            partialResult[vehicle.id] = vehicle.attributes.currentStopSequence
        }
    }

    private func formatStopsAway(targetStopSequence: Int?, currentStopSequence: Int?, minutesAway: Int?) -> String {
        guard let targetStopSequence, let currentStopSequence else {
            return ""
        }

        let stopsAway = targetStopSequence - currentStopSequence

        // Bus hasn't started this trip or is past the stop
        if stopsAway <= 0 {
            return ""
        }

        if stopsAway == 1 {
            return "1 stop away"
        }

        return "\(stopsAway) stops away"
    }
    
    /// Fetch scheduled departures as fallback when predictions are empty (commuter rail).
    func fetchSchedules(routeID: String, stopID: String, directionID: Int? = nil, source: String = "widget") async throws -> [WidgetArrivalSnapshot] {
        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.startOfDay(for: now).addingTimeInterval(86400)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        var components = URLComponents(string: "https://api-v3.mbta.com/schedules")!
        components.queryItems = [
            URLQueryItem(name: "filter[route]", value: routeID),
            URLQueryItem(name: "filter[stop]", value: stopID),
            URLQueryItem(name: "filter[min_time]", value: formatter.string(from: now)),
            URLQueryItem(name: "filter[max_time]", value: formatter.string(from: endOfDay)),
            URLQueryItem(name: "sort", value: "departure_time"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        if let directionID {
            components.queryItems?.append(
                URLQueryItem(name: "filter[direction_id]", value: String(directionID))
            )
        }
        
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        WidgetAPIUsageStore.record(url: url, statusCode: (response as? HTTPURLResponse)?.statusCode, source: source)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSchedulesResponse.self, from: data)
        
        return decoded.data
            .compactMap { schedule -> WidgetArrivalSnapshot? in
                let time = schedule.attributes.departureTime ?? schedule.attributes.arrivalTime
                guard let time, time >= now, time <= endOfDay else { return nil }
                return WidgetArrivalSnapshot(arrivalDate: time, stopsAwayText: "")
            }
            .sorted { $0.arrivalDate < $1.arrivalDate }
            .prefix(3)
            .map { $0 }
    }
}

private struct WidgetAPIUsageEvent: Codable {
    let timestamp: Date
    let endpoint: String
    let source: String
    let statusCode: Int?
}

private struct WidgetAPIUsageSnapshot: Codable {
    var totalRequests: Int
    var successRequests: Int
    var failedRequests: Int
    var endpointCounts: [String: Int]
    var sourceCounts: [String: Int]
    var dailyCounts: [String: Int]
    var hourlyCounts: [String: Int]
    var minuteCounts: [String: Int]
    var recentRequests: [WidgetAPIUsageEvent]
    var lastUpdated: Date

    static let empty = WidgetAPIUsageSnapshot(
        totalRequests: 0,
        successRequests: 0,
        failedRequests: 0,
        endpointCounts: [:],
        sourceCounts: [:],
        dailyCounts: [:],
        hourlyCounts: [:],
        minuteCounts: [:],
        recentRequests: [],
        lastUpdated: .distantPast
    )
}

private enum WidgetAPIUsageStore {
    static func record(url: URL, statusCode: Int?, source: String) {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA") else {
            return
        }

        let now = Date()
        var snapshot = loadSnapshot(from: defaults)
        let endpoint = endpointName(from: url)
        let dayKey = dayFormatter.string(from: now)
        let hourKey = hourFormatter.string(from: now)
        let minuteKey = minuteFormatter.string(from: now)

        snapshot.totalRequests += 1
        if let statusCode, (200...299).contains(statusCode) {
            snapshot.successRequests += 1
        } else {
            snapshot.failedRequests += 1
        }
        snapshot.endpointCounts[endpoint, default: 0] += 1
        snapshot.sourceCounts[source, default: 0] += 1
        snapshot.dailyCounts[dayKey, default: 0] += 1
        snapshot.hourlyCounts[hourKey, default: 0] += 1
        snapshot.minuteCounts[minuteKey, default: 0] += 1
        snapshot.recentRequests.insert(
            WidgetAPIUsageEvent(timestamp: now, endpoint: endpoint, source: source, statusCode: statusCode),
            at: 0
        )
        snapshot.recentRequests = Array(snapshot.recentRequests.prefix(100))
        snapshot.lastUpdated = now

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: "apiUsageSnapshot")
        defaults.set(2000, forKey: "apiUsageLimit")
    }

    private static func loadSnapshot(from defaults: UserDefaults) -> WidgetAPIUsageSnapshot {
        guard let data = defaults.data(forKey: "apiUsageSnapshot") else {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetAPIUsageSnapshot.self, from: data)) ?? .empty
    }

    private static func endpointName(from url: URL) -> String {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.contains("/") {
            return String(path.split(separator: "/").first ?? "")
        }
        return path.isEmpty ? "unknown" : path
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH"
        return formatter
    }()

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

#Preview("Favorite 1", as: .systemSmall) {
    SmallFavorite1Widget()
} timeline: {
    let now = Date()
    MBTAWidgetEntry(
        date: now,
        routeID: "39",
        routeName: "39",
        directionID: 0,
        directionLine: "To Back Bay Station",
        stopID: "place-NEU",
        stopName: "Northeastern University",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(2*60), minutesText: "2 min", stopsAwayText: ""),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(4*60), minutesText: "4 min", stopsAwayText: "")
        ],
        message: nil
    )
    
    MBTAWidgetEntry(
        date: now.addingTimeInterval(60),
        routeID: "39",
        routeName: "39",
        directionID: 0,
        directionLine: "To Back Bay Station",
        stopID: "place-NEU",
        stopName: "Northeastern University",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(1*60), minutesText: "1 min", stopsAwayText: ""),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(3*60), minutesText: "3 min", stopsAwayText: "")
        ],
        message: nil
    )
}
#Preview("Favorite 2", as: .systemSmall) {
    SmallFavorite2Widget()
} timeline: {
    let now = Date()
    MBTAWidgetEntry(
        date: now,
        routeID: "CT2",
        routeName: "CT2",
        directionID: 0,
        directionLine: "To Sullivan Square",
        stopID: "place-sull",
        stopName: "Sullivan Station",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(5*60), minutesText: "5 min", stopsAwayText: ""),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(12*60), minutesText: "12 min", stopsAwayText: "")
        ],
        message: nil
    )
}
