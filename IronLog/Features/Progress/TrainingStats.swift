import Foundation

/// Calculations for the Progress tab (all from finished workouts).
enum TrainingStats {
    struct ExercisePoint: Identifiable {
        let date: Date
        let topWeight: Double
        let estimatedMax: Double
        let bestReps: Int
        let bestSeconds: Int
        var id: Date { date }
    }

    struct Best: Identifiable {
        let exercise: ExerciseDef
        let headline: String
        let date: Date
        var id: String { exercise.id }
    }

    struct GroupVolume: Identifiable {
        let group: String
        let week: String
        let sets: Double
        var id: String { group + week }
    }

    static func finished(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.filter(\.isFinished)
    }

    /// One point per workout for an exercise: heaviest set and best estimated 1RM.
    static func history(for exerciseId: String, sessions: [WorkoutSession]) -> [ExercisePoint] {
        finished(sessions)
            .compactMap { s -> ExercisePoint? in
                let sets = s.sets.filter { $0.exerciseId == exerciseId }
                guard !sets.isEmpty else { return nil }
                return ExercisePoint(date: s.startedAt,
                                     topWeight: sets.map(\.weightKg).max() ?? 0,
                                     estimatedMax: sets.map(\.estimatedOneRepMax).max() ?? 0,
                                     bestReps: sets.map(\.reps).max() ?? 0,
                                     bestSeconds: sets.map(\.seconds).max() ?? 0)
            }
            .sorted { $0.date < $1.date }
    }

    /// All-time best for every exercise you've logged.
    static func bests(sessions: [WorkoutSession]) -> [Best] {
        let catalog = Catalog.shared
        var bySet: [String: (SetLog, Date)] = [:]
        for s in finished(sessions) {
            for set in s.sets {
                guard let ex = catalog.exercise(set.exerciseId) else { continue }
                let current = bySet[set.exerciseId]
                if current == nil || score(set, ex) > score(current!.0, ex) {
                    bySet[set.exerciseId] = (set, s.startedAt)
                }
            }
        }
        return bySet.compactMap { id, pair in
            guard let ex = catalog.exercise(id), ex.logType != .minutes else { return nil }
            return Best(exercise: ex,
                        headline: Fmt.set(weightKg: pair.0.weightKg, reps: pair.0.reps, seconds: pair.0.seconds, exercise: ex),
                        date: pair.1)
        }
        .sorted { $0.exercise.name < $1.exercise.name }
    }

    private static func score(_ s: SetLog, _ ex: ExerciseDef) -> Double {
        switch ex.logType {
        case .weightReps: return s.weightKg > 0 ? s.estimatedOneRepMax : Double(s.reps) / 100
        case .reps: return Double(s.reps)
        case .seconds, .minutes: return Double(s.seconds)
        }
    }

    /// Hard sets per muscle group (primary muscle = 1 set, secondary = ½) for the given weeks.
    static func groupVolume(sessions: [WorkoutSession], weeksBack: [Int]) -> [GroupVolume] {
        let catalog = Catalog.shared
        let thisWeek = WorkoutStats.startOfWeek()
        var out: [GroupVolume] = []
        for w in weeksBack {
            guard let start = Calendar.current.date(byAdding: .weekOfYear, value: -w, to: thisWeek),
                  let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { continue }
            let label = w == 0 ? "This week" : w == 1 ? "Last week" : "\(w) weeks ago"
            var sets: [String: Double] = [:]
            for s in finished(sessions) where s.startedAt >= start && s.startedAt < end {
                for set in s.sets {
                    guard let ex = catalog.exercise(set.exerciseId), ex.logType != .minutes else { continue }
                    for g in Set(ex.primary.compactMap { catalog.muscle($0)?.group }) { sets[g, default: 0] += 1 }
                    for g in Set(ex.secondary.compactMap { catalog.muscle($0)?.group })
                    where !ex.primary.contains(where: { catalog.muscle($0)?.group == g }) {
                        sets[g, default: 0] += 0.5
                    }
                }
            }
            for g in groups { out.append(GroupVolume(group: g, week: label, sets: sets[g] ?? 0)) }
        }
        return out
    }

    static let groups = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"]

    /// Days with a finished workout.
    static func trainedDays(_ sessions: [WorkoutSession]) -> Set<String> {
        Set(finished(sessions).map { $0.startedAt.dayKey })
    }

    /// Consecutive training days (Mon–Sat) completed, counting back from today. Sundays never break it;
    /// today doesn't break it until the day is over.
    static func streak(_ sessions: [WorkoutSession], extraDays: Set<String> = []) -> Int {
        let days = trainedDays(sessions).union(extraDays)
        var date = Date.now
        var count = 0
        var first = true
        for _ in 0..<400 {
            let weekday = Calendar.current.component(.weekday, from: date)
            if days.contains(date.dayKey) {
                count += 1
            } else if weekday != 1 && !first {
                break
            }
            first = false
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }
}
