import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

private enum WidgetTransportMode: String {
    case bus = "Bus"
    case subway = "Subway"
    case commuterRail = "Commuter Rail"

    var showsStopsAway: Bool {
        self == .bus
    }
}

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

struct MBTAWidgetEntry: TimelineEntry {
    let date: Date
    let routeName: String
    let directionLine: String
    let stopName: String
    let predictions: [WidgetArrivalDisplay]
    let message: String?
}

struct WidgetArrivalDisplay: Hashable {
    let arrivalDate: Date? // Store actual arrival date instead of text
    let minutesText: String // Keep for backward compatibility with previews
    let stopsAwayText: String
    
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
    let routeName: String
    let directionLine: String
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
            routeName: "39",
            directionLine: "To Back Bay Station",
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
                routeName: state.routeName,
                directionLine: state.directionLine,
                stopName: state.stopName,
                predictions: [],
                message: message
            )
        }
        
        let predictions = state.arrivals.map { arrival in
            WidgetArrivalDisplay(
                arrivalDate: arrival.arrivalDate,
                minutesText: formatMinutes(arrival.arrivalDate),
                stopsAwayText: arrival.stopsAwayText
            )
        }
        
        return MBTAWidgetEntry(
            date: Date(),
            routeName: state.routeName,
            directionLine: state.directionLine,
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
        
        // iOS limits widget refreshes to ~15 min minimum in practice
        // Request 1 minute but expect iOS to throttle to 15+ minutes
        let refreshDate = now.addingTimeInterval(60)
        
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func loadState() async -> WidgetContentState {
        // First check if there's a widget assignment for the medium widget
        if let assignedFavorite = loadAssignedFavorite(widgetKey: "mediumWidgetFavoriteIndex") {
            return await loadStateForFavorite(assignedFavorite)
        }
        
        // Fall back to the selection method (default or time-based override)
        guard let selection = StoredWidgetSelection.load() else {
            return WidgetContentState(
                mode: .bus,
                routeName: "--",
                directionLine: "Pick a route in the app",
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
                source: "medium_widget"
            )

            return WidgetContentState(
                mode: selection.mode,
                routeName: selection.routeName,
                directionLine: selection.directionLine,
                stopName: selection.stopName,
                arrivals: Array(arrivals.prefix(3)),
                message: arrivals.isEmpty ? "No upcoming buses right now." : nil
            )
        } catch {
            return WidgetContentState(
                mode: selection.mode,
                routeName: selection.routeName,
                directionLine: selection.directionLine,
                stopName: selection.stopName,
                arrivals: [],
                message: "Could not load bus times."
            )
        }
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
                source: "medium_widget"
            )
            
            return WidgetContentState(
                mode: mode,
                routeName: favorite.routeName,
                directionLine: directionLine,
                stopName: favorite.stopName,
                arrivals: Array(arrivals.prefix(3)),
                message: arrivals.isEmpty ? "No upcoming arrivals." : nil
            )
        } catch {
            return WidgetContentState(
                mode: mode,
                routeName: favorite.routeName,
                directionLine: directionLine,
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
            routeName: state.routeName,
            directionLine: state.directionLine,
            stopName: state.stopName,
            predictions: state.arrivals.prefix(3).map { arrival in
                let minutes = max(Int(arrival.arrivalDate.timeIntervalSince(startDate) / 60), 0)
                return WidgetArrivalDisplay(
                    arrivalDate: arrival.arrivalDate,
                    minutesText: "\(minutes) min",
                    stopsAwayText: state.mode.showsStopsAway ? arrival.stopsAwayText : ""
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
                return WidgetArrivalDisplay(
                    arrivalDate: arrival.arrivalDate,
                    minutesText: "\(minutes) min",
                    stopsAwayText: mode.showsStopsAway ? arrival.stopsAwayText : ""
                )
            }
    }
}

struct MBTAWidgetEntryView: View {
    var entry: MBTAWidgetProvider.Entry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(entry.routeName.displayRouteName)
                    .font(.headline)
                    .bold()
                    .foregroundColor(entry.routeName.routeTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(entry.routeName.routeBadgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

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
                
                // Last updated timestamp
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Updated")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(entry.date, style: .time)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            if let message = entry.message {
                Spacer()
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                Spacer(minLength: 4)
                
                HStack(spacing: 8) {
                    ForEach(Array(entry.predictions.enumerated()), id: \.offset) { index, prediction in
                        VStack(spacing: 4) {
                            // Use dynamic time calculation based on current date
                            Text(prediction.formattedMinutes(from: entry.date))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 6)
                                .background(Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255))
                                .clipShape(Capsule())

                            if !prediction.stopsAwayText.isEmpty {
                                Text(prediction.stopsAwayText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(" ")
                                    .font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }

                    if entry.predictions.count < 3 {
                        ForEach(entry.predictions.count..<3, id: \.self) { _ in
                            VStack(spacing: 4) {
                                Text("--")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 6)
                                    .background(Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255))
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
        .widgetURL(URL(string: "mbta-widget://open?route=\(entry.routeName)&stop=\(entry.stopName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"))
    }
}

struct MBTAWidget: Widget {
    let kind: String = "MBTAWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MBTAWidgetProvider()) { entry in
            MBTAWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MBTA Arrivals")
        .description("Shows the next 3 buses for your selected stop.")
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
                routeName: "39",
                directionLine: "To Back Bay Station",
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
                routeName: "CT2",
                directionLine: "To Sullivan Square",
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
                routeName: state.routeName,
                directionLine: state.directionLine,
                stopName: "",
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
            routeName: state.routeName,
            directionLine: state.directionLine,
            stopName: "",
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
        
        // iOS limits widget refreshes to ~15 min minimum in practice
        // Request 1 minute but expect iOS to throttle to 15+ minutes
        let refreshDate = now.addingTimeInterval(60)
        
        return Timeline(entries: entries, policy: .after(refreshDate))
    }
    
    private func loadState() async -> WidgetContentState {
        // Check for widget assignment first
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
        
        // Fall back to direct favorite index
        guard let favorite = loadFavorite(at: favoriteIndex) else {
            return WidgetContentState(
                mode: .bus,
                routeName: "--",
                directionLine: "Set Favorite \(favoriteIndex + 1)",
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
                source: "small_widget_fav\(favoriteIndex + 1)"
            )
            
            return WidgetContentState(
                mode: mode,
                routeName: favorite.routeName,
                directionLine: directionLine,
                stopName: "",
                arrivals: Array(arrivals.prefix(2)),
                message: arrivals.isEmpty ? "No upcoming arrivals." : nil
            )
        } catch {
            return WidgetContentState(
                mode: mode,
                routeName: favorite.routeName,
                directionLine: directionLine,
                stopName: "",
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
            routeName: state.routeName,
            directionLine: state.directionLine,
            stopName: "",
            predictions: state.arrivals.prefix(2).map { arrival in
                let minutes = max(Int(arrival.arrivalDate.timeIntervalSince(startDate) / 60), 0)
                return WidgetArrivalDisplay(
                    arrivalDate: arrival.arrivalDate,
                    minutesText: "\(minutes) min",
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
                    minutesText: "\(minutes) min",
                    stopsAwayText: ""
                )
            }
    }
}

struct SmallFavoriteWidgetView: View {
    var entry: MBTAWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                // Route badge
                Text(entry.routeName.displayRouteName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(entry.routeName.routeTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(entry.routeName.routeBadgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                // Reload indicator
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Updated")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(entry.date, style: .time)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            
            // Direction
            Text(entry.directionLine)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .foregroundColor(.primary)
            
            Spacer(minLength: 4)
            
            // Arrival times
            if let message = entry.message {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(entry.predictions.prefix(2).enumerated()), id: \.offset) { index, prediction in
                        // Use dynamic time calculation
                        Text(prediction.formattedMinutes(from: entry.date))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255))
                            .clipShape(Capsule())
                    }
                    
                    // Fill remaining slots
                    ForEach(entry.predictions.count..<2, id: \.self) { _ in
                        Text("--")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(red: 0 / 255, green: 57 / 255, blue: 166 / 255))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "mbta-widget://open?route=\(entry.routeName)&stop=\(entry.stopName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"))
    }
}

struct SmallFavorite1Widget: Widget {
    let kind: String = "SmallFavorite1Widget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmallFavoriteWidgetProvider(favoriteIndex: 0)) { entry in
            SmallFavoriteWidgetView(entry: entry)
        }
        .configurationDisplayName("Favorite 1")
        .description("Shows next 2 arrivals for your first favorite.")
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
        .description("Shows next 2 arrivals for your second favorite.")
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

// MARK: - Live Activity
#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct BusArrivalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusArrivalAttributes.self) { context in
            // Lock Screen & Banner UI
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(context.attributes.routeName.displayRouteName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(context.attributes.routeName.routeTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(context.attributes.routeName.routeBadgeColor)
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
                    
                    VStack(spacing: 2) {
                        Text(context.state.minutesText)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        if context.state.stopsAway > 0 {
                            Text("\(context.state.stopsAway) stops")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0/255, green: 57/255, blue: 166/255))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(context.attributes.routeName.displayRouteName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(context.attributes.routeName.routeTextColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(context.attributes.routeName.routeBadgeColor)
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
                        Text("\(context.state.minutesFromArrival)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Text("min")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0/255, green: 57/255, blue: 166/255))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } compactLeading: {
                Text(context.attributes.routeName.displayRouteName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(context.attributes.routeName.routeTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(context.attributes.routeName.routeBadgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } compactTrailing: {
                Text(context.state.minutesText)
                    .font(.system(size: 13, weight: .bold))
            } minimal: {
                Text("\(context.state.minutesFromArrival)")
                    .font(.system(size: 11, weight: .bold))
            }
        }
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
        routeName: "39",
        directionLine: "To Back Bay Station",
        stopName: "Huntington Ave @ Perkins St",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(6*60), minutesText: "6 min", stopsAwayText: "2 stops away"),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(15*60), minutesText: "15 min", stopsAwayText: "5 stops away"),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(22*60), minutesText: "22 min", stopsAwayText: "8 stops away")
        ],
        message: nil
    )
    
    MBTAWidgetEntry(
        date: now.addingTimeInterval(60),
        routeName: "39",
        directionLine: "To Back Bay Station",
        stopName: "Huntington Ave @ Perkins St",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(5*60), minutesText: "5 min", stopsAwayText: "2 stops away"),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(14*60), minutesText: "14 min", stopsAwayText: "5 stops away"),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(21*60), minutesText: "21 min", stopsAwayText: "8 stops away")
        ],
        message: nil
    )
}

private struct StoredWidgetSelection {
    let mode: WidgetTransportMode
    let routeID: String
    let routeName: String
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

        let now = Date()
        let activeFavorite = configuration.activeFavorite(at: now) ?? configuration.defaultFavorite
        guard let favorite = activeFavorite else {
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
            directionLine: directionLine,
            stopID: favorite.stopID,
            stopName: favorite.stopName
        )
    }
}

private struct WidgetStoredConfiguration: Decodable {
    let defaultFavorite: WidgetStoredFavorite?
    let overrides: [WidgetStoredOverride]

    func activeFavorite(at date: Date) -> WidgetStoredFavorite? {
        overrides.first(where: { $0.isActive(at: date) })?.favorite
    }
}

private struct WidgetStoredOverride: Decodable {
    let id: String
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

// MARK: - Widget Supabase Logging
private enum WidgetSupabaseLogger {
    // Hardcode the values for widget extension since it can't access main bundle
    private static let supabaseURL = "https://ifooqfgcpeczamayyzja.supabase.co"
    private static let supabaseKey = "sb_publishable_woKkE6OsLhUo7KaJLxvUSQ_RuV2-oI6"
    
    static var deviceID: String {
        let defaults = UserDefaults(suiteName: "group.Widgets.MBTA")
        if let existing = defaults?.string(forKey: "deviceID") {
            return existing
        }
        let newID = UUID().uuidString
        defaults?.set(newID, forKey: "deviceID")
        return newID
    }
    
    static func logAPICall(endpoint: String, statusCode: Int?, responseTimeMs: Int?, source: String = "widget") {
        // Simplified - just skip Supabase logging for now
        // The issue is widgets can't reliably make network calls
        // Use local logging instead via WidgetAPIUsageStore
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

private struct WidgetMBTAService {
    private let apiKey = "6aaf4b37ca464bc298e7573999c87d4d"

    func fetchPredictions(mode: WidgetTransportMode, routeID: String, stopID: String, source: String = "widget") async throws -> [WidgetArrivalSnapshot] {
        var components = URLComponents(string: "https://api-v3.mbta.com/predictions")!
        components.queryItems = [
            URLQueryItem(name: "filter[route]", value: routeID),
            URLQueryItem(name: "filter[stop]", value: stopID),
            URLQueryItem(name: "sort", value: "arrival_time"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        let url = components.url!
        var didRecord = false
        let startTime = Date()
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(from: url)
            let responseTime = Int(Date().timeIntervalSince(startTime) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            WidgetAPIUsageStore.record(url: url, statusCode: statusCode, source: source)
            
            // Log to Supabase
            WidgetSupabaseLogger.logAPICall(
                endpoint: "predictions",
                statusCode: statusCode,
                responseTimeMs: responseTime,
                source: source
            )
            
            didRecord = true
        } catch {
            if !didRecord {
                WidgetAPIUsageStore.record(url: url, statusCode: nil, source: source)
                WidgetSupabaseLogger.logAPICall(endpoint: "predictions", statusCode: nil, responseTimeMs: nil, source: source)
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

        return decoded.data
            .compactMap { prediction in
                guard let date = prediction.attributes.arrivalTime ?? prediction.attributes.departureTime else {
                    return nil
                }

                guard date >= now else {
                    return nil
                }

                let vehicleID = prediction.relationships?.vehicle?.data?.id
                let currentStopSequence = vehicleID.flatMap { vehiclesByID[$0] }
                let minutesAway = max(Int(date.timeIntervalSince(now) / 60), 0)

                return WidgetArrivalSnapshot(
                    arrivalDate: date,
                    stopsAwayText: formatStopsAway(
                        targetStopSequence: prediction.attributes.stopSequence,
                        currentStopSequence: currentStopSequence,
                        minutesAway: minutesAway
                    )
                )
            }
            .prefix(3)
            .map { $0 }
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

        let url = components.url!
        var didRecord = false
        let startTime = Date()
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(from: url)
            let responseTime = Int(Date().timeIntervalSince(startTime) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            WidgetAPIUsageStore.record(url: url, statusCode: statusCode, source: source)
            
            // Log to Supabase
            WidgetSupabaseLogger.logAPICall(
                endpoint: "vehicles",
                statusCode: statusCode,
                responseTimeMs: responseTime,
                source: source
            )
            
            didRecord = true
        } catch {
            if !didRecord {
                WidgetAPIUsageStore.record(url: url, statusCode: nil, source: source)
                WidgetSupabaseLogger.logAPICall(endpoint: "vehicles", statusCode: nil, responseTimeMs: nil, source: source)
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
            return "stops away unavailable"
        }

        let directDistance = max(targetStopSequence - currentStopSequence, 0)
        let stopsAway: Int
        if directDistance == 0, targetStopSequence > 1, let minutesAway, minutesAway > 1 {
            stopsAway = targetStopSequence - 1
        } else {
            stopsAway = directDistance
        }

        if stopsAway == 1 {
            return "1 stop away"
        }

        return "\(stopsAway) stops away"
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
        routeName: "39",
        directionLine: "To Back Bay Station",
        stopName: "",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(2*60), minutesText: "2 min", stopsAwayText: ""),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(4*60), minutesText: "4 min", stopsAwayText: "")
        ],
        message: nil
    )
    
    MBTAWidgetEntry(
        date: now.addingTimeInterval(60),
        routeName: "39",
        directionLine: "To Back Bay Station",
        stopName: "",
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
        routeName: "CT2",
        directionLine: "To Sullivan Square",
        stopName: "",
        predictions: [
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(5*60), minutesText: "5 min", stopsAwayText: ""),
            WidgetArrivalDisplay(arrivalDate: now.addingTimeInterval(12*60), minutesText: "12 min", stopsAwayText: "")
        ],
        message: nil
    )
}
