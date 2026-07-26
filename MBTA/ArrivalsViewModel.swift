import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif
import FirebaseFirestore

@available(iOS 16.2, *)
public struct BusArrivalAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var arrivalTime: Date
        public var minutesAway: Int
        public var stopsAway: Int
        
        public init(arrivalTime: Date, minutesAway: Int, stopsAway: Int) {
            self.arrivalTime = arrivalTime
            self.minutesAway = minutesAway
            self.stopsAway = stopsAway
        }
        
        /// Minutes computed from arrivalTime for live countdown
        public var minutesFromArrival: Int {
            max(0, Int(arrivalTime.timeIntervalSinceNow / 60))
        }
        
        public var minutesText: String {
            let mins = minutesFromArrival
            return mins < 1 ? "Now" : "\(mins) min"
        }
    }
    
    public let routeID: String
    public let routeName: String
    public let destination: String
    public let directionID: Int?
    public let stopID: String
    public let stopName: String
    
    public init(routeID: String, routeName: String, destination: String, directionID: Int? = nil, stopID: String = "", stopName: String) {
        self.routeID = routeID
        self.routeName = routeName
        self.destination = destination
        self.directionID = directionID
        self.stopID = stopID
        self.stopName = stopName
    }
}

enum WidgetSlotType: String, Codable, CaseIterable, Identifiable {
    case wide = "Wide Widget"
    case small1 = "Small Widget 1"
    case small2 = "Small Widget 2"

    var id: String { rawValue }
}

struct WidgetScheduleOverride: Codable, Identifiable {
    let id: String
    var widgetSlot: WidgetSlotType
    var favorite: SavedFavorite?
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    init(
        id: String = UUID().uuidString,
        widgetSlot: WidgetSlotType = .wide,
        favorite: SavedFavorite? = nil,
        startHour: Int = 7,
        startMinute: Int = 0,
        endHour: Int = 9,
        endMinute: Int = 0
    ) {
        self.id = id
        self.widgetSlot = widgetSlot
        self.favorite = favorite
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }
}

struct WidgetConfiguration: Codable {
    var defaultFavorite: SavedFavorite?
    var overrides: [WidgetScheduleOverride]

    static let empty = WidgetConfiguration(defaultFavorite: nil, overrides: [])
}

struct SavedFavorite: Codable, Identifiable {
    let mode: TransportMode
    let routeID: String
    let routeName: String
    let directionID: Int
    let directionName: String
    let directionDestination: String
    let stopID: String
    let stopName: String

    var id: String {
        "\(routeID)-\(directionID)-\(stopID)"
    }

    var buttonTitle: String {
        routeID
    }

    init(
        mode: TransportMode,
        routeID: String,
        routeName: String,
        directionID: Int,
        directionName: String,
        directionDestination: String,
        stopID: String,
        stopName: String
    ) {
        self.mode = mode
        self.routeID = routeID
        self.routeName = routeName
        self.directionID = directionID
        self.directionName = directionName
        self.directionDestination = directionDestination
        self.stopID = stopID
        self.stopName = stopName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(TransportMode.self, forKey: .mode) ?? .bus
        routeID = try container.decode(String.self, forKey: .routeID)
        routeName = try container.decode(String.self, forKey: .routeName)
        directionID = try container.decode(Int.self, forKey: .directionID)
        directionName = try container.decode(String.self, forKey: .directionName)
        directionDestination = try container.decode(String.self, forKey: .directionDestination)
        stopID = try container.decode(String.self, forKey: .stopID)
        stopName = try container.decode(String.self, forKey: .stopName)
    }
}

/// ViewModel that connects the SwiftUI view to the MBTAService.
@MainActor
final class ArrivalsViewModel: ObservableObject {
    private enum QuickRouteKeys {
        static let route0 = "quickRoute0"
        static let route1 = "quickRoute1"
        static let route2 = "quickRoute2"
        static let route3 = "quickRoute3"

        static let all = [route0, route1, route2, route3]
    }

    @Published var routeInput: String = ""
    @Published var selectedRoute: Route? = nil
    @Published var selectedMode: TransportMode = .bus
    @Published var quickFavorites: [SavedFavorite?] = Array(repeating: nil, count: 4)
    @Published var selectedPresetLineQuery: String? = nil
    
    /// Cached arrival times for each favorite, keyed by favorite id
    @Published var shortcutArrivals: [String: [BusArrival]] = [:]
    
    /// All currently active alerts
    @Published var allAlerts: [MBTAAlert] = []
    @Published var isLoadingAlerts: Bool = false
    
    /// Number of alerts affecting saved favorite routes
    var favoriteAlertCount: Int {
        let favoriteRouteIDs = Set(quickFavorites.compactMap { $0?.routeID })
        guard !favoriteRouteIDs.isEmpty else { return 0 }
        return allAlerts.filter { alert in
            alert.routeIDs.contains(where: { favoriteRouteIDs.contains($0) })
        }.count
    }
    
    @Published var widgetDefaultFavorite: SavedFavorite? = nil
    @Published var widgetOverrides: [WidgetScheduleOverride] = []

    @Published var directions: [RouteDirection] = []
    @Published var selectedDirectionID: Int? = nil

    @Published var stops: [BusStop] = []
    @Published var selectedStopID: String? = nil

    @Published var arrivals: [BusArrival] = []
    @Published var isLoadingRoute: Bool = false
    @Published var isLoadingStops: Bool = false
    @Published var isLoadingArrivals: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentActivity: Any? = nil
    @Published var allBusRoutes: [Route] = []
    /// The direction ID used for the active Live Activity, so we can filter predictions correctly
    private var liveActivityDirectionID: Int? = nil
    
    /// Stored reference to the Live Activity polling task so it isn't deallocated in Release builds
    private var liveActivityPollingTask: Task<Void, Never>?
    /// Stored reference to the Live Activity timer task
    private var liveActivityTimerTask: Task<Void, Never>?
    /// Shared tracker for Live Activity state between timer and polling loop
    private var liveActivityTracker: LiveActivityTracker?
    
    private var reloadTimer: Task<Void, Never>?
    
    /// Filtered bus route suggestions based on current input
    var routeSuggestions: [Route] {
        let query = routeInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty, selectedMode == .bus else { return [] }
        return allBusRoutes.filter { route in
            let name = route.displayName.lowercased()
            let id = route.id.lowercased()
            return name.hasPrefix(query) || id.hasPrefix(query) ||
                   name.contains(query) || id.contains(query)
        }
        .prefix(8)
        .map { $0 }
    }

    var selectedStop: BusStop? {
        stops.first { $0.id == selectedStopID }
    }

    init() {
        loadQuickRoutes()
        loadWidgetConfiguration()
        restoreLiveActivitySelectionIfNeeded()
        Task {
            await loadAllBusRoutes()
        }
    }
    
    func loadAllBusRoutes() async {
        guard allBusRoutes.isEmpty else { return }
        do {
            let routes = try await MBTAService.shared.fetchAllRoutes(mode: .bus)
            await MainActor.run {
                allBusRoutes = routes
            }
        } catch {
            // Non-critical, autocomplete just won't work
        }
    }
    
    /// Fetches arrival predictions for all saved shortcuts (for the Home screen cards).
    func loadShortcutArrivals() async {
        let favorites = quickFavorites.compactMap { $0 }
        guard !favorites.isEmpty else { return }
        
        await withTaskGroup(of: (String, [BusArrival]).self) { group in
            for favorite in favorites {
                group.addTask {
                    do {
                        let allPredictions = try await MBTAService.shared.fetchPredictions(
                            stopId: favorite.stopID,
                            routeId: favorite.routeID,
                            routeName: favorite.routeName,
                            stopName: favorite.stopName
                        )
                        let filtered = allPredictions
                            .filter { $0.directionId == favorite.directionID }
                        return (favorite.id, Array(filtered.prefix(2)))
                    } catch {
                        return (favorite.id, [])
                    }
                }
            }
            
            var results: [String: [BusArrival]] = [:]
            for await (id, arrivals) in group {
                results[id] = arrivals
            }
            
            self.shortcutArrivals = results
        }
    }
    
    /// Removes a saved favorite at the given index.
    func removeFavorite(at index: Int) {
        guard quickFavorites.indices.contains(index) else { return }
        quickFavorites[index] = nil
        saveQuickRoutes()
    }
    
    /// Fetches all currently active alerts from the MBTA API.
    func loadAlerts() async {
        isLoadingAlerts = true
        do {
            allAlerts = try await MBTAService.shared.fetchAlerts()
        } catch {
            // Silent fail — alerts are non-critical
        }
        isLoadingAlerts = false
    }
    
    deinit {
        reloadTimer?.cancel()
    }
    
    func loadFromWidget(url: URL) async {
        // Parse URL parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            // Fallback to old behavior
            await loadFromWidgetLegacy()
            return
        }
        
        let routeID = queryItems.first(where: { $0.name == "routeID" })?.value
        let directionIDString = queryItems.first(where: { $0.name == "directionID" })?.value
        let directionID = directionIDString.flatMap { Int($0) }
        let stopID = queryItems.first(where: { $0.name == "stopID" })?.value
        let routeName = queryItems.first(where: { $0.name == "route" })?.value
        
        // Best match: find favorite by routeID + directionID + stopID
        if let routeID = routeID {
            let match = quickFavorites.compactMap({ $0 }).first(where: { fav in
                fav.routeID == routeID
                    && (directionID == nil || fav.directionID == directionID)
                    && (stopID == nil || fav.stopID == stopID)
            })
            if let match {
                await loadFavorite(match)
                await loadArrivals()
                return
            }
        }
        
        // Fallback: match by routeName + directionID (legacy URLs without routeID)
        if let routeName = routeName {
            let match = quickFavorites.compactMap({ $0 }).first(where: { fav in
                fav.routeName == routeName
                    && (directionID == nil || fav.directionID == directionID)
                    && (stopID == nil || fav.stopID == stopID)
            })
            if let match {
                await loadFavorite(match)
                await loadArrivals()
                return
            }
        }
        
        // No favorite match — load the route directly from URL parameters
        // This handles non-favorited routes opened from the Dynamic Island / widget
        if let routeID = routeID, let directionID = directionID, let stopID = stopID {
            await loadRouteDirectly(routeID: routeID, directionID: directionID, stopID: stopID)
            return
        }
        
        // Final fallback to old behavior
        await loadFromWidgetLegacy()
    }
    
    /// Loads a route directly from URL parameters (routeID, directionID, stopID)
    /// without requiring a saved favorite. Used when tapping a Live Activity / widget
    /// for a non-favorited route.
    private func loadRouteDirectly(routeID: String, directionID: Int, stopID: String) async {
        errorMessage = nil
        arrivals = []
        stops = []
        selectedStopID = nil
        directions = []
        selectedDirectionID = nil
        selectedRoute = nil

        isLoadingRoute = true

        do {
            let route = try await MBTAService.shared.fetchRoute(matching: routeID, mode: .bus)
            selectedMode = .bus
            selectedRoute = route
            directions = route.directionOptions
            routeInput = route.displayName
            selectedPresetLineQuery = route.id
            selectedDirectionID = directionID
            saveWidgetSelection()
        } catch {
            // Try other modes if bus didn't match
            for mode in [TransportMode.commuterRail, .subway] {
                if let route = try? await MBTAService.shared.fetchRoute(matching: routeID, mode: mode) {
                    selectedMode = mode
                    selectedRoute = route
                    directions = route.directionOptions
                    routeInput = route.displayName
                    selectedPresetLineQuery = route.id
                    selectedDirectionID = directionID
                    saveWidgetSelection()
                    break
                }
            }
        }

        isLoadingRoute = false

        guard selectedRoute != nil else {
            errorMessage = "Could not load that route."
            return
        }

        await loadStops()

        if stops.contains(where: { $0.id == stopID }) {
            selectedStopID = stopID
            saveWidgetSelection()
            await loadArrivals()
        }
    }

    private func loadFromWidgetLegacy() async {
        // Load the favorite that's currently showing in the widget
        guard let favorite = loadActiveWidgetFavorite() else {
            return
        }
        
        await loadFavorite(favorite)
        await loadArrivals()
    }
    
    private func loadActiveWidgetFavorite() -> SavedFavorite? {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA") else {
            return nil
        }
        
        // Try widget assignments first
        if let mediumIndex = defaults.object(forKey: "mediumWidgetFavoriteIndex") as? Int,
           quickFavorites.indices.contains(mediumIndex),
           let favorite = quickFavorites[mediumIndex] {
            return favorite
        }
        
        // Fall back to widget configuration (default or time-based)
        if let configData = defaults.data(forKey: "widget.configuration"),
           let configuration = try? JSONDecoder().decode(WidgetConfiguration.self, from: configData) {
            let now = Date()
            return configuration.overrides.first(where: { isOverrideActive($0, at: now) })?.favorite 
                ?? configuration.defaultFavorite
        }
        
        return nil
    }
    
    private func isOverrideActive(_ override: WidgetScheduleOverride, at date: Date) -> Bool {
        let calendar = Calendar.current
        let nowMinutes = (calendar.component(.hour, from: date) * 60) + calendar.component(.minute, from: date)
        let startMinutes = (override.startHour * 60) + override.startMinute
        let endMinutes = (override.endHour * 60) + override.endMinute

        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        }

        return nowMinutes >= startMinutes || nowMinutes < endMinutes
    }

    var fieldTitle: String {
        selectedMode.fieldTitle
    }

    var routePlaceholder: String {
        selectedMode.placeholder
    }

    var stopTitle: String {
        selectedMode.stopTitle
    }

    var presetLines: [PresetLine] {
        selectedMode.presetLines
    }

    var greenLineBranches: [PresetLine] {
        selectedMode.greenLineBranches
    }

    func selectSuggestedRoute(_ route: Route) async {
        errorMessage = nil
        arrivals = []
        stops = []
        selectedStopID = nil
        directions = []
        selectedDirectionID = nil
        
        selectedRoute = route
        directions = route.directionOptions
        routeInput = route.displayName
        saveWidgetSelection()
    }
    
    func loadRoute() async {
        errorMessage = nil
        arrivals = []
        stops = []
        selectedStopID = nil
        directions = []
        selectedDirectionID = nil
        selectedRoute = nil

        let trimmedRoute = routeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoute.isEmpty else {
            errorMessage = "Type a bus number first."
            return
        }

        isLoadingRoute = true

        do {
            let route = try await MBTAService.shared.fetchRoute(matching: trimmedRoute, mode: selectedMode)
            selectedRoute = route
            directions = route.directionOptions
            routeInput = route.displayName
            saveWidgetSelection()
        } catch {
            errorMessage = "Could not find that bus route."
        }

        isLoadingRoute = false
    }

    func handleQuickRouteTap(at index: Int) async {
        guard quickFavorites.indices.contains(index) else {
            return
        }

        guard let favorite = quickFavorites[index] else {
            errorMessage = "Save a favorite first."
            return
        }

        await loadFavorite(favorite)
    }

    func saveFavorite(at index: Int) {
        guard quickFavorites.indices.contains(index) else {
            return
        }

        guard
            let route = selectedRoute,
            let directionID = selectedDirectionID,
            let direction = directions.first(where: { $0.id == directionID }),
            let stop = selectedStop
        else {
            errorMessage = "Choose a bus number, direction, and stop before saving."
            return
        }

        quickFavorites[index] = SavedFavorite(
            mode: selectedMode,
            routeID: route.id,
            routeName: route.displayName,
            directionID: direction.id,
            directionName: direction.name,
            directionDestination: direction.destination,
            stopID: stop.id,
            stopName: stop.name
        )
        saveQuickRoutes()
    }

    func showFavoriteInWidget(at index: Int) {
        guard quickFavorites.indices.contains(index), let favorite = quickFavorites[index] else {
            errorMessage = "Save a favorite first."
            return
        }

        let direction = RouteDirection(
            id: favorite.directionID,
            name: favorite.directionName,
            destination: favorite.directionDestination
        )
        let route = Route(
            id: favorite.routeID,
            shortName: favorite.routeName,
            longName: nil,
            directionNames: [],
            directionDestinations: []
        )
        let stop = BusStop(id: favorite.stopID, name: favorite.stopName)
        WidgetSharedStore.save(mode: favorite.mode, route: route, direction: direction, stop: stop)
    }

    func updateWidgetDefaultFavorite(_ favorite: SavedFavorite?) {
        widgetDefaultFavorite = favorite
        saveWidgetConfiguration()
    }

    func addWidgetOverride(for slot: WidgetSlotType = .wide) {
        let fallbackFavorite = quickFavorites.compactMap { $0 }.first
        widgetOverrides.append(WidgetScheduleOverride(widgetSlot: slot, favorite: fallbackFavorite))
        saveWidgetConfiguration()
    }

    func updateWidgetOverrideSlot(id: String, slot: WidgetSlotType) {
        guard let index = widgetOverrides.firstIndex(where: { $0.id == id }) else {
            return
        }
        widgetOverrides[index].widgetSlot = slot
        saveWidgetConfiguration()
    }

    func updateWidgetOverrideFavorite(id: String, favorite: SavedFavorite?) {
        guard let index = widgetOverrides.firstIndex(where: { $0.id == id }) else {
            return
        }

        widgetOverrides[index].favorite = favorite
        saveWidgetConfiguration()
    }

    func updateWidgetOverrideStart(id: String, date: Date) {
        guard let index = widgetOverrides.firstIndex(where: { $0.id == id }) else {
            return
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        widgetOverrides[index].startHour = components.hour ?? 0
        widgetOverrides[index].startMinute = components.minute ?? 0
        saveWidgetConfiguration()
    }

    func updateWidgetOverrideEnd(id: String, date: Date) {
        guard let index = widgetOverrides.firstIndex(where: { $0.id == id }) else {
            return
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        widgetOverrides[index].endHour = components.hour ?? 0
        widgetOverrides[index].endMinute = components.minute ?? 0
        saveWidgetConfiguration()
    }

    func deleteWidgetOverride(id: String) {
        widgetOverrides.removeAll { $0.id == id }
        saveWidgetConfiguration()
    }

    func handleReturnToForeground() {
        // Only refresh if we have a valid selection
        guard selectedRoute != nil, selectedStopID != nil else { return }
        Task {
            await loadArrivals()
        }
        
        // Restart Live Activity polling if we have an active activity
        // (the polling Task dies when iOS suspends the app in the background)
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            restartLiveActivityPollingIfNeeded()
        }
        #endif
    }
    
    func handleModeChange() {
        errorMessage = nil
        routeInput = ""
        selectedRoute = nil
        directions = []
        selectedDirectionID = nil
        stops = []
        selectedStopID = nil
        arrivals = []
        selectedPresetLineQuery = nil
        saveWidgetSelection()
    }

    func selectPresetLine(_ line: PresetLine) {
        selectedPresetLineQuery = line.query
        routeInput = line.query
        
        // Clear directions and subsequent data if selecting Green Line
        // (user needs to pick a branch first)
        if line.query == "Green" {
            directions = []
            selectedDirectionID = nil
            stops = []
            selectedStopID = nil
            arrivals = []
            selectedRoute = nil
            saveWidgetSelection()
        }
    }

    func selectGreenBranch(_ line: PresetLine) {
        selectedPresetLineQuery = line.query
        routeInput = line.query
    }

    func selectDirection(_ directionID: Int) async {
        let previousStopName = selectedStop?.name
        errorMessage = nil
        arrivals = []
        stops = []
        selectedStopID = nil
        selectedDirectionID = directionID
        saveWidgetSelection()
        await loadStops(preferredStopName: previousStopName)
    }

    func loadStops(preferredStopName: String? = nil) async {
        guard let routeID = selectedRoute?.id, let directionID = selectedDirectionID else {
            return
        }

        isLoadingStops = true

        do {
            var allStops = try await MBTAService.shared.fetchStops(routeId: routeID, directionId: directionID)
            
            // Route 39: only show stops between Forest Hills and Back Bay
            if routeID == "39" {
                let boundaryIDs: Set<String> = ["place-forhl", "place-bbsta"]
                if let firstIdx = allStops.firstIndex(where: { boundaryIDs.contains($0.id) }),
                   let lastIdx = allStops.lastIndex(where: { boundaryIDs.contains($0.id) }),
                   firstIdx <= lastIdx {
                    allStops = Array(allStops[firstIdx...lastIdx])
                }
            }
            
            stops = allStops
            
            // Try to re-select the same stop by name when switching directions
            if let preferredName = preferredStopName,
               let matchingStop = stops.first(where: { $0.name == preferredName }) {
                selectedStopID = matchingStop.id
            } else {
                // Default to the middle stop instead of the first
                let middleIndex = stops.count / 2
                selectedStopID = stops.indices.contains(middleIndex) ? stops[middleIndex].id : stops.first?.id
            }
            saveWidgetSelection()
        } catch {
            errorMessage = "Could not load stops for that direction."
        }

        isLoadingStops = false
    }

    func loadArrivals() async {
        errorMessage = nil

        guard let routeID = selectedRoute?.id else {
            arrivals = []
            errorMessage = "Load a bus route first."
            return
        }

        guard selectedDirectionID != nil else {
            errorMessage = "Choose a direction."
            return
        }

        guard let stopID = selectedStopID, let stop = selectedStop else {
            errorMessage = "Choose a stop."
            return
        }

        isLoadingArrivals = true

        do {
            let routeName = selectedRoute?.displayName ?? routeID
            let direction = directions.first { $0.id == selectedDirectionID }
            let directionName = direction?.name
            
            let allPredictions = try await MBTAService.shared.fetchPredictions(
                stopId: stopID,
                routeId: routeID,
                routeName: routeName,
                directionName: directionName,
                stopName: stop.name
            )

            // Filter by selected direction so subway/rail stops only show the chosen direction
            let predictions: [BusArrival]
            if let dirID = selectedDirectionID {
                predictions = allPredictions.filter { $0.directionId == dirID }
            } else {
                predictions = allPredictions
            }

            arrivals = Array(predictions.prefix(3)).map { arrival in
                BusArrival(
                    id: arrival.id,
                    routeId: arrival.routeId,
                    routeName: routeName,
                    stopId: arrival.stopId,
                    stopName: stop.name,
                    arrivalTime: arrival.arrivalTime,
                    departureTime: arrival.departureTime,
                    minutesAway: arrival.minutesAway,
                    stopsAway: arrival.stopsAway,
                    directionId: arrival.directionId,
                    status: arrival.status
                )
            }

            if arrivals.isEmpty {
                errorMessage = "No upcoming arrivals found for this stop."
            }
            
            // Reload widgets immediately when user loads arrivals
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
            
            // Start auto-reload timer (30 seconds)
            startAutoReload()
        } catch {
            errorMessage = "Failed to load arrival times."
        }

        isLoadingArrivals = false
    }
    
    private func startAutoReload() {
        reloadTimer?.cancel()
        reloadTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20 seconds
                await loadArrivalsQuietly()
            }
        }
    }
    
    private func loadArrivalsQuietly() async {
        guard let routeID = selectedRoute?.id,
              let stopID = selectedStopID,
              let stop = selectedStop else {
            return
        }

        do {
            let routeName = selectedRoute?.displayName ?? routeID
            let direction = directions.first { $0.id == selectedDirectionID }
            let directionName = direction?.name
            
            let allPredictions = try await MBTAService.shared.fetchPredictions(
                stopId: stopID,
                routeId: routeID,
                routeName: routeName,
                directionName: directionName,
                stopName: stop.name
            )

            // Filter by selected direction so subway/rail stops only show the chosen direction
            let predictions: [BusArrival]
            if let dirID = selectedDirectionID {
                predictions = allPredictions.filter { $0.directionId == dirID }
            } else {
                predictions = allPredictions
            }

            var newArrivals = Array(predictions.prefix(3)).map { arrival in
                BusArrival(
                    id: arrival.id,
                    routeId: arrival.routeId,
                    routeName: routeName,
                    stopId: arrival.stopId,
                    stopName: stop.name,
                    arrivalTime: arrival.arrivalTime,
                    departureTime: arrival.departureTime,
                    minutesAway: arrival.minutesAway,
                    stopsAway: arrival.stopsAway,
                    directionId: arrival.directionId,
                    status: arrival.status
                )
            }

            // If new data has fewer results, keep old predictions that haven't expired
            // This prevents the third tile from flashing "--" between refreshes
            let now = Date()
            if newArrivals.count < arrivals.count {
                for i in newArrivals.count..<arrivals.count {
                    let old = arrivals[i]
                    let arrivalTime = old.arrivalTime ?? old.departureTime
                    if let arrivalTime, arrivalTime > now {
                        newArrivals.append(old)
                    }
                }
            }

            arrivals = Array(newArrivals.prefix(3))
        } catch {
            // Silent fail - don't update error message during background refresh
        }
    }

    func saveWidgetSelection() {
        let direction = directions.first { $0.id == selectedDirectionID }
        WidgetSharedStore.save(mode: selectedMode, route: selectedRoute, direction: direction, stop: selectedStop)
    }

    private func loadQuickRoutes() {
        let decoder = JSONDecoder()
        quickFavorites = QuickRouteKeys.all.map { key in
            guard
                let data = UserDefaults.standard.data(forKey: key),
                let favorite = try? decoder.decode(SavedFavorite.self, from: data)
            else {
                return nil
            }

            return favorite
        }
        
        // Also sync to app group for widgets on first load
        saveQuickRoutes()
    }

    private func saveQuickRoutes() {
        let encoder = JSONEncoder()
        for (index, key) in QuickRouteKeys.all.enumerated() {
            if let favorite = quickFavorites[index], let data = try? encoder.encode(favorite) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        // Also save to app group for widgets
        if let appGroupDefaults = UserDefaults(suiteName: "group.Widgets.MBTA"),
           let favoritesData = try? encoder.encode(quickFavorites) {
            appGroupDefaults.set(favoritesData, forKey: "quickFavorites")
            
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    private func loadWidgetConfiguration() {
        let configuration = WidgetSharedStore.loadConfiguration() ?? .empty
        widgetDefaultFavorite = configuration.defaultFavorite
        widgetOverrides = configuration.overrides
    }

    private func saveWidgetConfiguration() {
        let configuration = WidgetConfiguration(
            defaultFavorite: widgetDefaultFavorite,
            overrides: widgetOverrides
        )
        WidgetSharedStore.saveConfiguration(configuration)
    }

    func loadFavorite(_ favorite: SavedFavorite) async {
        selectedMode = favorite.mode
        selectedPresetLineQuery = favorite.routeID
        routeInput = favorite.routeID
        errorMessage = nil
        arrivals = []
        stops = []
        selectedStopID = nil
        directions = []
        selectedDirectionID = nil
        selectedRoute = nil

        isLoadingRoute = true

        do {
            let route = try await MBTAService.shared.fetchRoute(matching: favorite.routeID, mode: favorite.mode)
            selectedRoute = route
            directions = route.directionOptions
            selectedDirectionID = favorite.directionID
            saveWidgetSelection()
        } catch {
            isLoadingRoute = false
            errorMessage = "Could not load that saved route."
            return
        }

        isLoadingRoute = false

        await loadStops()
        if stops.contains(where: { $0.id == favorite.stopID }) {
            selectedStopID = favorite.stopID
            saveWidgetSelection()
        }
    }
    
    func startLiveActivity(arrivalIndex: Int? = nil) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        
        // End any existing Live Activity and deactivate its Firestore token
        stopLiveActivity()
        
        // Persist the current selection so it survives app relaunch
        saveLiveActivitySelection()
        
        // Use the specified arrival index, or fall back to first arrival with minutes > 0
        let validArrival: BusArrival?
        if let index = arrivalIndex, index < arrivals.count {
            validArrival = arrivals[index]
        } else {
            validArrival = arrivals.first(where: { ($0.minutesAway ?? 0) > 0 })
        }
        
        guard let validArrival,
              let minutesAway = validArrival.minutesAway,
              let arrivalTime = validArrival.arrivalTime ?? validArrival.departureTime else {
            errorMessage = "No upcoming arrivals"
            return
        }
        
        let destination = selectedDirectionDestination
        let stopsAway = validArrival.stopsAway ?? 0
        
        let attributes = BusArrivalAttributes(
            routeID: selectedRoute?.id ?? validArrival.routeId,
            routeName: validArrival.routeName,
            destination: destination.isEmpty ? "Arriving" : destination,
            directionID: selectedDirectionID,
            stopID: selectedStopID ?? validArrival.stopId,
            stopName: validArrival.stopName
        )
        
        let initialState = BusArrivalAttributes.ContentState(
            arrivalTime: arrivalTime,
            minutesAway: minutesAway,
            stopsAway: stopsAway
        )
        
        // Store direction for filtering during updates
        liveActivityDirectionID = selectedDirectionID
        
        do {
            // Set stale date to 2 minutes from now so system knows to check for updates
            let staleDate = Date().addingTimeInterval(120)
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: staleDate),
                pushType: .token
            )
            currentActivity = activity
            
            // Always register push token for background updates via Firebase
            let pushStopID = selectedStopID ?? validArrival.stopId
            let pushStopName = selectedStop?.name ?? validArrival.stopName
            let pushRouteID = selectedRoute?.id ?? validArrival.routeId
            let pushRouteName = selectedRoute?.displayName ?? validArrival.routeName
            Task {
                for await tokenData in activity.pushTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    print("Live Activity push token: \(token)")
                    
                    await registerPushToken(
                        token: token,
                        routeID: pushRouteID,
                        routeName: pushRouteName,
                        stopID: pushStopID,
                        stopName: pushStopName,
                        destination: destination,
                        directionID: self.liveActivityDirectionID,
                        trackedArrivalTime: arrivalTime
                    )
                }
            }
            
            // Start local polling — stored as instance properties so Tasks survive in Release builds
            let tracker = LiveActivityTracker(
                trackedTime: arrivalTime,
                stopsAway: stopsAway,
                directionID: liveActivityDirectionID,
                routeID: selectedRoute?.id ?? validArrival.routeId,
                stopID: selectedStopID ?? validArrival.stopId
            )
            liveActivityTracker = tracker
            startPollingAndTimer(activity: activity, tracker: tracker)
        } catch {
            errorMessage = "Could not start Live Activity: \(error.localizedDescription)"
        }
        #endif
    }
    
    /// Registers the Live Activity push token with Firestore so the backend can send updates
    private func registerPushToken(
        token: String,
        routeID: String,
        routeName: String,
        stopID: String,
        stopName: String,
        destination: String,
        directionID: Int? = nil,
        trackedArrivalTime: Date? = nil
    ) async {
        let db = Firestore.firestore()
        var data: [String: Any] = [
            "pushToken": token,
            "routeID": routeID,
            "routeName": routeName,
            "stopID": stopID,
            "stopName": stopName,
            "destination": destination,
            "active": true,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let directionID {
            data["directionID"] = directionID
        }
        if let trackedArrivalTime {
            data["trackedArrivalTime"] = Int(trackedArrivalTime.timeIntervalSince1970)
        }
        
        do {
            try await db.collection("liveActivities").document(token).setData(data)
            print("Registered push token with Firestore")
        } catch {
            print("Failed to register push token: \(error)")
        }
    }
    
    /// Shared mutable state for Live Activity polling, using a reference type
    /// so both the timer closure and the polling loop see the same values
    /// regardless of Swift compiler optimizations in Release builds.
    private class LiveActivityTracker {
        var currentTrackedTime: Date
        var latestStopsAway: Int
        let directionID: Int?
        let routeID: String
        let stopID: String
        
        init(trackedTime: Date, stopsAway: Int, directionID: Int?, routeID: String, stopID: String) {
            self.currentTrackedTime = trackedTime
            self.latestStopsAway = stopsAway
            self.directionID = directionID
            self.routeID = routeID
            self.stopID = stopID
        }
    }
    
    #if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private func restartLiveActivityPollingIfNeeded() {
        guard let activity = currentActivity as? Activity<BusArrivalAttributes> else { return }
        
        // If the polling task is still running, nothing to do
        if let existing = liveActivityPollingTask, !existing.isCancelled {
            return
        }
        
        // Use existing tracker's arrival time, or fall back to the activity's current state
        let trackedTime = liveActivityTracker?.currentTrackedTime ?? activity.content.state.arrivalTime
        let stopsAway = liveActivityTracker?.latestStopsAway ?? activity.content.state.stopsAway
        
        let routeID = liveActivityTracker?.routeID ?? selectedRoute?.id ?? activity.attributes.routeID
        let stopID = liveActivityTracker?.stopID ?? selectedStopID ?? ""
        let directionID = liveActivityTracker?.directionID ?? liveActivityDirectionID
        
        guard !stopID.isEmpty else { return }
        
        let tracker = LiveActivityTracker(
            trackedTime: trackedTime,
            stopsAway: stopsAway,
            directionID: directionID,
            routeID: routeID,
            stopID: stopID
        )
        liveActivityTracker = tracker
        
        startPollingAndTimer(activity: activity, tracker: tracker)
    }
    
    @available(iOS 16.2, *)
    private func startPollingAndTimer(activity: Activity<BusArrivalAttributes>, tracker: LiveActivityTracker) {
        // Cancel any existing tasks
        liveActivityTimerTask?.cancel()
        liveActivityPollingTask?.cancel()
        
        // Timer task: refresh the countdown display every 15 seconds using MainActor Timer
        liveActivityTimerTask = Task { @MainActor [weak self] in
            let timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
                Task.detached {
                    let trackedTime = tracker.currentTrackedTime
                    let freshState = BusArrivalAttributes.ContentState(
                        arrivalTime: trackedTime,
                        minutesAway: max(0, Int(trackedTime.timeIntervalSinceNow / 60)),
                        stopsAway: tracker.latestStopsAway
                    )
                    await activity.update(.init(state: freshState, staleDate: Date().addingTimeInterval(60)))
                }
            }
            RunLoop.current.add(timer, forMode: .common)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            timer.invalidate()
            _ = self
        }
        
        // Polling task: runs OFF the main actor so it doesn't compete with UI work.
        // Uses Task.detached to avoid inheriting @MainActor from the calling context,
        // which caused the Task to be silently cancelled in Release/TestFlight builds.
        let weakSelf = Weak(self)
        liveActivityPollingTask = Task.detached {
            while !Task.isCancelled {
                // Sleep off the main actor — this is the critical difference vs before
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                
                do {
                    let predictions = try await MBTAService.shared.fetchPredictions(
                        stopId: tracker.stopID,
                        routeId: tracker.routeID
                    )
                    
                    // Filter by direction to avoid matching wrong-direction trains at shared stops
                    let directionalPredictions: [BusArrival]
                    if let dirID = tracker.directionID {
                        directionalPredictions = predictions.filter { $0.directionId == dirID }
                    } else {
                        directionalPredictions = predictions
                    }
                    
                    // Find the prediction closest to the tracked arrival time (within 5 min tolerance)
                    let currentTrackedTime = tracker.currentTrackedTime
                    let validPrediction = directionalPredictions
                        .filter { $0.minutesAway != nil }
                        .filter {
                            let time = $0.arrivalTime ?? $0.departureTime ?? .distantFuture
                            return abs(time.timeIntervalSince(currentTrackedTime)) < 300
                        }
                        .min(by: { a, b in
                            let aTime = a.arrivalTime ?? a.departureTime ?? .distantFuture
                            let bTime = b.arrivalTime ?? b.departureTime ?? .distantFuture
                            return abs(aTime.timeIntervalSince(currentTrackedTime)) < abs(bTime.timeIntervalSince(currentTrackedTime))
                        })
                    
                    // Don't fall back to the next bus — if the tracked bus arrived, end the activity
                    let bestPrediction = validPrediction
                    
                    guard let bestPrediction,
                          let newArrivalTime = bestPrediction.arrivalTime ?? bestPrediction.departureTime,
                          let newMinutesAway = bestPrediction.minutesAway else {
                        // No more arrivals, end activity
                        await MainActor.run {
                            weakSelf.value?.liveActivityTimerTask?.cancel()
                        }
                        await activity.end(nil, dismissalPolicy: .immediate)
                        await MainActor.run {
                            weakSelf.value?.currentActivity = nil
                            weakSelf.value?.liveActivityDirectionID = nil
                            weakSelf.value?.liveActivityTracker = nil
                        }
                        break
                    }
                    
                    // Update shared tracker so the timer sees fresh data
                    tracker.currentTrackedTime = newArrivalTime
                    tracker.latestStopsAway = bestPrediction.stopsAway ?? 0
                    
                    let updatedState = BusArrivalAttributes.ContentState(
                        arrivalTime: newArrivalTime,
                        minutesAway: newMinutesAway,
                        stopsAway: bestPrediction.stopsAway ?? 0
                    )
                    await activity.update(.init(state: updatedState, staleDate: Date().addingTimeInterval(120)))
                    
                    // Auto-dismiss: if arrival is within 1 minute or has passed
                    if newMinutesAway <= 1 || newArrivalTime.timeIntervalSinceNow < 60 {
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                        await MainActor.run {
                            weakSelf.value?.liveActivityTimerTask?.cancel()
                        }
                        await activity.end(nil, dismissalPolicy: .immediate)
                        await MainActor.run {
                            weakSelf.value?.currentActivity = nil
                            weakSelf.value?.liveActivityDirectionID = nil
                            weakSelf.value?.liveActivityTracker = nil
                        }
                        break
                    }
                    
                    // Update local arrivals in the app too
                    let routeID = tracker.routeID
                    await MainActor.run {
                        guard let vm = weakSelf.value else { return }
                        let routeName = vm.selectedRoute?.displayName ?? routeID
                        let stop = vm.selectedStop
                        
                        vm.arrivals = Array(directionalPredictions.prefix(3)).map { arrival in
                            BusArrival(
                                id: arrival.id,
                                routeId: arrival.routeId,
                                routeName: routeName,
                                stopId: arrival.stopId,
                                stopName: stop?.name ?? "",
                                arrivalTime: arrival.arrivalTime,
                                departureTime: arrival.departureTime,
                                minutesAway: arrival.minutesAway,
                                stopsAway: arrival.stopsAway,
                                directionId: arrival.directionId,
                                status: arrival.status
                            )
                        }
                    }
                } catch {
                    // On error, continue trying — don't break the loop
                    print("Failed to update Live Activity: \(error)")
                }
            }
        }
    }
    
    /// Type-erased weak reference wrapper for use in Task.detached closures
    /// (which cannot capture [weak self] directly).
    private class Weak<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }
    #endif
    
    func stopLiveActivity() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        
        // Cancel polling and timer tasks
        liveActivityPollingTask?.cancel()
        liveActivityTimerTask?.cancel()
        liveActivityPollingTask = nil
        liveActivityTimerTask = nil
        liveActivityTracker = nil
        
        if let activity = currentActivity as? Activity<BusArrivalAttributes> {
            Task {
                // Deactivate token in Firestore
                let tokenData = activity.pushToken
                if let tokenData {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    try? await Firestore.firestore()
                        .collection("liveActivities")
                        .document(token)
                        .updateData(["active": false])
                }
                
                await activity.end(nil, dismissalPolicy: .immediate)
                await MainActor.run {
                    currentActivity = nil
                    liveActivityDirectionID = nil
                    clearLiveActivitySelection()
                }
            }
        }
        #endif
    }
    
    private var selectedDirectionDestination: String {
        guard let directionID = selectedDirectionID,
              let direction = directions.first(where: { $0.id == directionID }) else {
            return ""
        }
        return direction.destination
            .replacingOccurrences(of: " Station", with: "")
            .replacingOccurrences(of: " station", with: "")
    }
    
    // MARK: - Live Activity Selection Persistence
    
    private func saveLiveActivitySelection() {
        guard let route = selectedRoute,
              let directionID = selectedDirectionID,
              let stopID = selectedStopID else { return }
        
        let favorite = SavedFavorite(
            mode: selectedMode,
            routeID: route.id,
            routeName: route.displayName,
            directionID: directionID,
            directionName: directions.first(where: { $0.id == directionID })?.name ?? "",
            directionDestination: directions.first(where: { $0.id == directionID })?.destination ?? "",
            stopID: stopID,
            stopName: selectedStop?.name ?? ""
        )
        
        if let data = try? JSONEncoder().encode(favorite) {
            UserDefaults.standard.set(data, forKey: "liveActivitySelection")
        }
    }
    
    private func clearLiveActivitySelection() {
        UserDefaults.standard.removeObject(forKey: "liveActivitySelection")
    }
    
    private func restoreLiveActivitySelectionIfNeeded() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        
        // Check if there's a running live activity
        let runningActivities = Activity<BusArrivalAttributes>.activities
        guard !runningActivities.isEmpty else {
            clearLiveActivitySelection()
            return
        }
        
        // Restore the saved selection
        guard let data = UserDefaults.standard.data(forKey: "liveActivitySelection"),
              let favorite = try? JSONDecoder().decode(SavedFavorite.self, from: data) else {
            return
        }
        
        // Reconnect to the running activity
        currentActivity = runningActivities.first
        
        // Restore the selection by loading the favorite
        Task {
            await loadFavorite(favorite)
        }
        #endif
    }
}
