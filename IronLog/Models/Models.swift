import Foundation
import SwiftData

// Everything you log is stored on the phone with SwiftData.
// Static reference data (exercises, split, foods) lives in the bundled JSON files instead.

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        WorkoutSession.self,
        SetLog.self,
        BodyMetric.self,
        FoodEntry.self,
        CustomFood.self,
        LearnedPortion.self,
        SupplementCheck.self,
        CustomExercise.self,
        WaterLog.self,
    ]
}

// MARK: - Training

/// One gym visit.
@Model
final class WorkoutSession {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date?
    /// Name of the split day that was trained, e.g. "Chest & Abs".
    var dayName: String
    /// Weekday of the split day that was trained (1 = Sunday … 7 = Saturday), which may differ from the calendar day.
    var splitWeekday: Int
    var notes: String
    /// Set while the workout is paused.
    var pausedAt: Date? = nil
    /// Total time spent paused, in seconds (left out of the workout duration).
    var pausedSeconds: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var sets: [SetLog] = []

    init(dayName: String, splitWeekday: Int, startedAt: Date = .now) {
        self.id = UUID()
        self.startedAt = startedAt
        self.dayName = dayName
        self.splitWeekday = splitWeekday
        self.notes = ""
    }

    var isFinished: Bool { finishedAt != nil }
    var isPaused: Bool { pausedAt != nil }

    /// Start time shifted by the paused time, so the clock shows only active training.
    var effectiveStart: Date { startedAt.addingTimeInterval(pausedSeconds) }

    /// Active training time so far (or in total once finished).
    var activeDuration: TimeInterval {
        (pausedAt ?? finishedAt ?? .now).timeIntervalSince(effectiveStart)
    }

    func pause() {
        guard pausedAt == nil else { return }
        pausedAt = .now
    }

    func resume() {
        guard let p = pausedAt else { return }
        pausedSeconds += Date.now.timeIntervalSince(p)
        pausedAt = nil
    }

    /// Sum of weight × reps over all weighted sets, in kg.
    var totalVolume: Double {
        sets.reduce(0) { $0 + $1.volume }
    }
}

/// One completed set. Which fields matter depends on the exercise's log type:
/// weight+reps, reps only, seconds held (plank) or minutes (cardio).
@Model
final class SetLog {
    var exerciseId: String
    var setIndex: Int
    var weightKg: Double
    var reps: Int
    var seconds: Int
    var completedAt: Date
    var session: WorkoutSession?

    init(exerciseId: String, setIndex: Int, weightKg: Double = 0, reps: Int = 0, seconds: Int = 0, completedAt: Date = .now) {
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.seconds = seconds
        self.completedAt = completedAt
    }

    var volume: Double { weightKg * Double(reps) }

    /// Estimated one-rep max (Epley), used to detect strength PRs.
    var estimatedOneRepMax: Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }
}

// MARK: - Body

/// A weigh-in. Body fat is optional.
@Model
final class BodyMetric {
    var date: Date
    var weightKg: Double
    var bodyFatPercent: Double?
    /// "app", "health" or "scan"
    var source: String
    // Extra readings from a body-composition scan (InBody, Tanita, smart scales). All optional.
    var muscleMassKg: Double?
    var fatMassKg: Double?
    var visceralFat: Double?
    var bmr: Double?
    var bodyWater: Double?
    var bodyScore: Double?

    init(date: Date = .now, weightKg: Double, bodyFatPercent: Double? = nil, source: String = "app") {
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.source = source
    }
}

// MARK: - Nutrition

/// One food item eaten. Macros are stored already calculated for the portion,
/// so history stays correct even if the food database is edited later.
@Model
final class FoodEntry {
    var id: UUID
    var date: Date
    /// e.g. "Breakfast", "Post-workout", "Snack"
    var meal: String
    var name: String
    var foodId: String?
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double = 0

    init(date: Date = .now, meal: String, name: String, foodId: String?, grams: Double,
         kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double = 0) {
        self.id = UUID()
        self.date = date
        self.meal = meal
        self.name = name
        self.foodId = foodId
        self.grams = grams
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
    }
}

/// A food you added yourself because it wasn't in the bundled database.
@Model
final class CustomFood {
    @Attribute(.unique) var id: String
    var name: String
    var aliases: [String]
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double = 0
    var createdAt: Date

    init(id: String, name: String, aliases: [String] = [], kcalPer100g: Double,
         proteinPer100g: Double, carbsPer100g: Double, fatPer100g: Double) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.createdAt = .now
    }
}

/// Your own portion size, learned from corrections, e.g. "1 bowl rice = 180 g".
@Model
final class LearnedPortion {
    /// "<foodId>|<unit>"
    @Attribute(.unique) var key: String
    var foodId: String
    var unit: String
    var grams: Double
    var updatedAt: Date

    init(foodId: String, unit: String, grams: Double) {
        self.key = LearnedPortion.key(foodId: foodId, unit: unit)
        self.foodId = foodId
        self.unit = unit
        self.grams = grams
        self.updatedAt = .now
    }

    static func key(foodId: String, unit: String) -> String { "\(foodId)|\(unit)" }
}

/// A supplement ticked off on a given day.
@Model
final class SupplementCheck {
    /// "yyyy-MM-dd"
    var dayKey: String
    var supplementId: String
    var takenAt: Date

    init(dayKey: String, supplementId: String, takenAt: Date = .now) {
        self.dayKey = dayKey
        self.supplementId = supplementId
        self.takenAt = takenAt
    }
}

/// A glass / bottle of water.
@Model
final class WaterLog {
    var date: Date
    var ml: Double

    init(date: Date = .now, ml: Double) {
        self.date = date
        self.ml = ml
    }
}

/// An exercise you added yourself (not in the bundled library).
@Model
final class CustomExercise {
    @Attribute(.unique) var id: String
    var name: String
    /// LogType raw value
    var logType: String
    var equipment: String
    var primary: [String]
    var secondary: [String]
    var createdAt: Date

    init(id: String, name: String, logType: String, equipment: String, primary: [String], secondary: [String]) {
        self.id = id
        self.name = name
        self.logType = logType
        self.equipment = equipment
        self.primary = primary
        self.secondary = secondary
        self.createdAt = .now
    }

    var definition: ExerciseDef {
        ExerciseDef(id: id, name: name, logType: LogType(rawValue: logType) ?? .weightReps, equipment: equipment,
                    primary: primary, secondary: secondary, weightStep: 2.5, source: "custom")
    }
}

// MARK: - Date helpers

extension Date {
    /// "yyyy-MM-dd" in the current time zone. Used as a stable key for "which day".
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var endOfDay: Date { Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? self }
}
