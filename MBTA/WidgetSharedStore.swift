import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetSharedStore {
    static let appGroupID = "group.Widgets.MBTA"

    enum Keys {
        static let mode = "widget.mode"
        static let routeID = "widget.routeID"
        static let routeName = "widget.routeName"
        static let directionID = "widget.directionID"
        static let directionName = "widget.directionName"
        static let directionDestination = "widget.directionDestination"
        static let stopID = "widget.stopID"
        static let stopName = "widget.stopName"
        static let configuration = "widget.configuration"
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(mode: TransportMode? = nil, route: Route?, direction: RouteDirection?, stop: BusStop?) {
        guard let defaults else {
            return
        }

        defaults.set(mode?.rawValue, forKey: Keys.mode)
        defaults.set(route?.id, forKey: Keys.routeID)
        defaults.set(route?.displayName, forKey: Keys.routeName)
        defaults.set(direction?.id, forKey: Keys.directionID)
        defaults.set(direction?.name, forKey: Keys.directionName)
        defaults.set(direction?.destination, forKey: Keys.directionDestination)
        defaults.set(stop?.id, forKey: Keys.stopID)
        defaults.set(stop?.name, forKey: Keys.stopName)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func saveConfiguration(_ configuration: WidgetConfiguration) {
        guard let defaults else {
            return
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(configuration) else {
            return
        }

        defaults.set(data, forKey: Keys.configuration)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func loadConfiguration() -> WidgetConfiguration? {
        guard
            let defaults,
            let data = defaults.data(forKey: Keys.configuration)
        else {
            return nil
        }

        return try? JSONDecoder().decode(WidgetConfiguration.self, from: data)
    }
}
