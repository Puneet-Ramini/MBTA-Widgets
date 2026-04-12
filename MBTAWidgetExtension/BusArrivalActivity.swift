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
