import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit

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
    }
    
    public let routeName: String
    public let destination: String
    public let stopName: String
    
    public init(routeName: String, destination: String, stopName: String) {
        self.routeName = routeName
        self.destination = destination
        self.stopName = stopName
    }
}
#endif

struct WidgetScheduleOverride: Codable, Identifiable {
    let id: String
    var favorite: SavedFavorite?
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    init(
        id: String = UUID().uuidString,
        favorite: SavedFavorite? = nil,
        startHour: Int = 16,
        startMinute: Int = 0,
        endHour: Int = 18,
        endMinute: Int = 0
    ) {
        self.id = id
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
    
    private var reloadTimer: Task<Void, Never>?

    var selectedStop: BusStop? {
        stops.first { $0.id == selectedStopID }
    }

    init() {
        loadQuickRoutes()
        loadWidgetConfiguration()
    }
    
    deinit {
        reloadTimer?.cancel()
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

    func addWidgetOverride() {
        let fallbackFavorite = quickFavorites.compactMap { $0 }.first
        widgetOverrides.append(WidgetScheduleOverride(favorite: fallbackFavorite))
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
        errorMessage = nil
        arrivals = []
        stops = []
        selectedStopID = nil
        selectedDirectionID = directionID
        saveWidgetSelection()
        await loadStops()
    }

    func loadStops() async {
        guard let routeID = selectedRoute?.id, let directionID = selectedDirectionID else {
            return
        }

        isLoadingStops = true

        do {
            stops = try await MBTAService.shared.fetchStops(routeId: routeID, directionId: directionID)
            selectedStopID = stops.first?.id
            saveWidgetSelection()
        } catch {
            errorMessage = "Could not load stops for that direction."
        }

        isLoadingStops = false
    }

    func loadArrivals() async {
        errorMessage = nil
        arrivals = []

        guard let routeID = selectedRoute?.id else {
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
            
            let predictions = try await MBTAService.shared.fetchPredictions(
                stopId: stopID,
                routeId: routeID,
                routeName: routeName,
                directionName: directionName,
                stopName: stop.name
            )

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
                errorMessage = "No upcoming buses found for this stop."
            }
            
            // Start auto-reload timer (10 seconds)
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
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
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
            
            let predictions = try await MBTAService.shared.fetchPredictions(
                stopId: stopID,
                routeId: routeID,
                routeName: routeName,
                directionName: directionName,
                stopName: stop.name
            )

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

    private func loadFavorite(_ favorite: SavedFavorite) async {
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
    
    func startLiveActivity() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        
        // Find first arrival with minutes > 0
        guard let validArrival = arrivals.first(where: { ($0.minutesAway ?? 0) > 0 }),
              let minutesAway = validArrival.minutesAway,
              let arrivalTime = validArrival.arrivalTime ?? validArrival.departureTime else {
            errorMessage = "No upcoming arrivals"
            return
        }
        
        let destination = selectedDirectionDestination
        let stopsAway = validArrival.stopsAway ?? 0
        
        let attributes = BusArrivalAttributes(
            routeName: validArrival.routeName,
            destination: destination.isEmpty ? "Arriving" : destination,
            stopName: validArrival.stopName
        )
        
        let initialState = BusArrivalAttributes.ContentState(
            arrivalTime: arrivalTime,
            minutesAway: minutesAway,
            stopsAway: stopsAway
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            
            Task {
                await updateLiveActivity(activity: activity)
            }
        } catch {
            errorMessage = "Could not start Live Activity: \(error.localizedDescription)"
        }
        #endif
    }
    
    #if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private func updateLiveActivity(activity: Activity<BusArrivalAttributes>) async {
        var isFirstIteration = true
        
        while !Task.isCancelled {
            // Wait 10 seconds before API call (skip on first iteration)
            if !isFirstIteration {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
            isFirstIteration = false
            
            // Fetch fresh data from API every 10 seconds
            guard let routeID = selectedRoute?.id,
                  let stopID = selectedStopID else {
                break
            }
            
            do {
                let predictions = try await MBTAService.shared.fetchPredictions(stopId: stopID, routeId: routeID)
                
                // Get first arrival with minutes > 0
                guard let validPrediction = predictions.first(where: { ($0.minutesAway ?? 0) > 0 }),
                      let newArrivalTime = validPrediction.arrivalTime ?? validPrediction.departureTime,
                      let newMinutesAway = validPrediction.minutesAway else {
                    // No more arrivals, end activity
                    await activity.end(nil, dismissalPolicy: .immediate)
                    await MainActor.run {
                        currentActivity = nil
                    }
                    break
                }
                
                // Update Live Activity with fresh data
                let updatedState = BusArrivalAttributes.ContentState(
                    arrivalTime: newArrivalTime,
                    minutesAway: newMinutesAway,
                    stopsAway: validPrediction.stopsAway ?? 0
                )
                
                await activity.update(.init(state: updatedState, staleDate: nil))
                
                // Update local arrivals in the app too
                await MainActor.run {
                    let routeName = selectedRoute?.displayName ?? routeID
                    let stop = selectedStop
                    
                    arrivals = Array(predictions.prefix(3)).map { arrival in
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
                // On error, continue trying
                print("Failed to update Live Activity: \(error)")
            }
        }
        
        // Cleanup
        await activity.end(nil, dismissalPolicy: .immediate)
        await MainActor.run {
            currentActivity = nil
        }
    }
    #endif
    
    func stopLiveActivity() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        
        if let activity = currentActivity as? Activity<BusArrivalAttributes> {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
                await MainActor.run {
                    currentActivity = nil
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
}
