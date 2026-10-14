import Foundation

/// What the iPhone sends the Watch: today's workout with every set and its pre-filled values.
struct WatchPlan: Codable, Equatable {
    var dayName: String
    var splitWeekday: Int
    var isRestDay: Bool
    /// True once a workout has been started (on either device) and not finished.
    var inProgress: Bool
    var startedAt: Date?
    var restSeconds: Int
    var exercises: [WatchExercise]
    var sentAt: Date

    /// The first exercise that still has sets left.
    var nextExerciseIndex: Int? { exercises.firstIndex { $0.sets.contains { !$0.done } } }
    var doneSets: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

struct WatchExercise: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// "weightReps", "reps", "seconds" or "minutes"
    var logType: String
    var weightStep: Double
    var muscles: String
    var sets: [WatchSet]
}

struct WatchSet: Codable, Equatable {
    var index: Int
    /// e.g. "8-12" or "20"
    var target: String
    var weightKg: Double
    var reps: Int
    var seconds: Int
    var done: Bool
}

/// A set ticked off on the Watch, sent back to the iPhone to save.
struct WatchSetLog: Codable {
    var exerciseId: String
    var setIndex: Int
    var weightKg: Double
    var reps: Int
    var seconds: Int
    var dayName: String
    var splitWeekday: Int
}

enum WatchMessage {
    static let plan = "plan"
    static let logSet = "logSet"
    static let start = "start"
    static let finish = "finish"
    static let requestPlan = "requestPlan"

    static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Any?) -> T? {
        guard let data = data as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
