import Foundation
import Observation
import SwiftData

/// Live Apple Health data for the dashboard: today's activity and workouts recorded elsewhere.
@Observable
final class HealthData {
    static let shared = HealthData()

    var today = ActivitySummary()
    var weekSteps: [(Date, Double)] = []
    var recentWorkouts: [HealthWorkout] = []
    var lastRefresh: Date?

    var isConnected: Bool { UserDefaults.standard.bool(forKey: ProfileKey.healthSyncEnabled) }

    /// Workouts recorded today by the Fitness app / Apple Watch / other apps.
    var todaysWorkouts: [HealthWorkout] {
        recentWorkouts.filter { Calendar.current.isDateInToday($0.start) }
    }

    /// Days (yyyy-MM-dd) with a workout recorded in Apple Health; counts towards your streak.
    var workoutDays: Set<String> { Set(recentWorkouts.map { $0.start.dayKey }) }

    @MainActor
    func refresh() async {
        guard isConnected, HealthKitManager.shared.isAvailable else { return }
        let hk = HealthKitManager.shared
        let since = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        async let a = hk.activity()
        async let w = hk.workouts(since: since)
        async let s = hk.dailySteps(days: 7)
        today = await a
        recentWorkouts = await w
        weekSteps = await s
        lastRefresh = .now
    }
}

/// Water logging + reminders.
enum WaterService {
    static let reminderHours = [9, 11, 13, 15, 17, 19, 21]

    static func log(ml: Double, context: ModelContext) {
        context.insert(WaterLog(ml: ml))
        try? context.save()
        if UserDefaults.standard.bool(forKey: ProfileKey.healthSyncEnabled) {
            Task { try? await HealthKitManager.shared.saveWater(ml: ml) }
        }
        Haptics.success()
    }

    static func setReminders(_ on: Bool) {
        for h in reminderHours {
            let id = "water-\(h)"
            if on {
                NotificationManager.shared.scheduleDaily(id: id, title: "HYDRATE",
                                                         body: "Time for a glass of water. Small sips add up.",
                                                         hour: h, minute: 0)
            } else {
                NotificationManager.shared.cancel(id: id)
            }
        }
    }
}
