import ActivityKit
import SwiftUI

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
    public let stopName: String
    
    public init(routeID: String, routeName: String, destination: String, stopName: String) {
        self.routeID = routeID
        self.routeName = routeName
        self.destination = destination
        self.stopName = stopName
    }
}
