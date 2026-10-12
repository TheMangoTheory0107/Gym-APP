import Foundation

/// Number and time formatting used across the app.
enum Fmt {
    /// 30 → "30", 32.5 → "32.5", 1.25 → "1.25"
    static func weight(_ kg: Double) -> String {
        if kg == kg.rounded() { return String(format: "%.0f", kg) }
        if (kg * 10) == (kg * 10).rounded() { return String(format: "%.1f", kg) }
        return String(format: "%.2f", kg)
    }

    /// 120 → "2:00"
    static func clock(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 3725 → "1 h 2 min", 1500 → "25 min"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(max(m, 1)) min"
    }

    /// 12450 → "12,450"
    static func volume(_ kg: Double) -> String {
        Int(kg.rounded()).formatted(.number.grouping(.automatic))
    }

    /// One logged set as text, e.g. "30 kg × 10", "20 reps", "2:00", "22 min".
    static func set(weightKg: Double, reps: Int, seconds: Int, exercise: ExerciseDef) -> String {
        switch exercise.logType {
        case .weightReps:
            return weightKg > 0 ? "\(weight(weightKg)) kg × \(reps)" : "\(reps) reps"
        case .reps:
            return "\(reps) \(exercise.repUnit ?? "reps")"
        case .seconds:
            return clock(seconds)
        case .minutes:
            return "\(seconds / 60) min"
        }
    }
}
