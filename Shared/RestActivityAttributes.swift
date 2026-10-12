import ActivityKit
import Foundation

/// Live Activity for the rest timer (Lock Screen + Dynamic Island). Shared by the app and the widget extension.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var totalSeconds: Int
        var nextUp: String
    }

    var workoutName: String
}
