import Foundation
import SwiftData
import WidgetKit

/// Writes today's numbers for the Home Screen widget and asks it to refresh.
enum WidgetSync {
    static func update(context: ModelContext) {
        let start = Date.now.startOfDay
        let food = (try? context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start }))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.startedAt >= start }))) ?? []
        let defaults = UserDefaults.standard
        let kcalTarget = defaults.object(forKey: ProfileKey.kcalTarget) as? Double ?? ProfileDefault.kcal
        let proteinTarget = defaults.object(forKey: ProfileKey.proteinTarget) as? Double ?? ProfileDefault.protein
        let kcal = food.reduce(0) { $0 + $1.kcal }
        let protein = food.reduce(0) { $0 + $1.protein }
        let done = sessions.first { $0.isFinished }

        WidgetSnapshot(date: .now,
                       workoutName: done?.dayName ?? WidgetSnapshot.plannedWorkout(),
                       kcalLeft: Int(max(kcalTarget - kcal, 0)),
                       proteinLeft: Int(max(proteinTarget - protein, 0)),
                       workoutDone: done != nil).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
