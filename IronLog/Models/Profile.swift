import Foundation

/// Keys and defaults for settings stored with @AppStorage.
enum ProfileKey {
    static let heightCm = "profile.heightCm"
    static let kcalTarget = "targets.kcal"
    static let proteinTarget = "targets.protein"
    static let carbsTarget = "targets.carbs"
    static let fatTarget = "targets.fat"
    static let restSeconds = "workout.restSeconds"
    static let healthSyncEnabled = "health.syncEnabled"
    static let didSeed = "app.didSeed"
}

enum ProfileDefault {
    static let heightCm = 180.34
    static let startWeightKg = 86.6
    static let startBodyFat = 24.3
    static let kcal = 2400.0
    static let protein = 180.0
    static let carbs = 326.0
    static let fat = 75.0
    static let restSeconds = 90
}

/// BMI, lean mass and FFMI calculations.
enum BodyMath {
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        guard m > 0 else { return 0 }
        return weightKg / (m * m)
    }

    static func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case ..<25: return "Normal"
        case ..<30: return "Overweight"
        default: return "Obese"
        }
    }

    static func leanMass(weightKg: Double, bodyFatPercent: Double) -> Double {
        weightKg * (1 - bodyFatPercent / 100)
    }

    /// Fat-free mass index, normalised to 1.8 m height. ~20 is average for a trained man, 25 is a very high natural ceiling.
    static func ffmi(weightKg: Double, bodyFatPercent: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        guard m > 0 else { return 0 }
        let raw = leanMass(weightKg: weightKg, bodyFatPercent: bodyFatPercent) / (m * m)
        return raw + 6.1 * (1.8 - m)
    }
}
