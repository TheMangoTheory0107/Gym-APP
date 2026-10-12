import Foundation
import SwiftData

/// A personal record set during a workout.
struct PersonalRecord: Identifiable, Hashable {
    let id = UUID()
    let exerciseName: String
    let headline: String
    let detail: String
}

struct WorkoutSummary {
    let dayName: String
    let duration: TimeInterval
    let volume: Double
    let setCount: Int
    let exerciseCount: Int
    let records: [PersonalRecord]
}

/// History lookups and PR detection.
enum WorkoutStats {
    /// All sets for an exercise from *finished* workouts (other than `excluding`), newest first.
    static func history(exerciseId: String, excluding sessionId: UUID?, context: ModelContext) -> [SetLog] {
        let id = exerciseId
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.exerciseId == id },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { log in
            guard let s = log.session, s.finishedAt != nil else { return false }
            return s.id != sessionId
        }
    }

    /// The sets from the most recent finished workout that included this exercise, in set order.
    static func lastTime(exerciseId: String, excluding sessionId: UUID?, context: ModelContext) -> [SetLog] {
        let all = history(exerciseId: exerciseId, excluding: sessionId, context: context)
        guard let lastSession = all.first?.session?.id else { return [] }
        return all.filter { $0.session?.id == lastSession }.sorted { $0.setIndex < $1.setIndex }
    }

    /// "Last: 30 kg × 10" style text from the top set of last time.
    static func lastSummary(_ sets: [SetLog], exercise: ExerciseDef) -> String? {
        let top: SetLog?
        switch exercise.logType {
        case .weightReps:
            top = sets.max { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) }
        case .reps:
            top = sets.max { $0.reps < $1.reps }
        case .seconds, .minutes:
            top = sets.max { $0.seconds < $1.seconds }
        }
        guard let top else { return nil }
        return Fmt.set(weightKg: top.weightKg, reps: top.reps, seconds: top.seconds, exercise: exercise)
    }

    static func summary(for session: WorkoutSession, context: ModelContext) -> WorkoutSummary {
        let end = session.finishedAt ?? .now
        let byExercise = Dictionary(grouping: session.sets, by: \.exerciseId)
        return WorkoutSummary(
            dayName: session.dayName,
            duration: end.timeIntervalSince(session.startedAt),
            volume: session.totalVolume,
            setCount: session.sets.count,
            exerciseCount: byExercise.count,
            records: records(for: session, context: context)
        )
    }

    /// Compares each exercise in this workout with all earlier finished workouts.
    /// Exercises done for the first time don't count as PRs.
    static func records(for session: WorkoutSession, context: ModelContext) -> [PersonalRecord] {
        let catalog = Catalog.shared
        var result: [PersonalRecord] = []
        let byExercise = Dictionary(grouping: session.sets, by: \.exerciseId)

        for (exerciseId, sets) in byExercise {
            guard let ex = catalog.exercise(exerciseId) else { continue }
            let previous = history(exerciseId: exerciseId, excluding: session.id, context: context)
                .filter { ($0.session?.startedAt ?? .distantFuture) < session.startedAt }
            guard !previous.isEmpty else { continue }

            switch ex.logType {
            case .weightReps:
                let bestNow = sets.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }
                let bestBefore = previous.map(\.estimatedOneRepMax).max() ?? 0
                let heaviestNow = sets.map(\.weightKg).max() ?? 0
                let heaviestBefore = previous.map(\.weightKg).max() ?? 0
                if let bestNow, bestNow.estimatedOneRepMax > bestBefore + 0.01 {
                    result.append(PersonalRecord(
                        exerciseName: ex.name,
                        headline: "\(Fmt.weight(bestNow.weightKg)) kg × \(bestNow.reps)",
                        detail: "Strength PR · est. 1RM \(Fmt.weight((bestNow.estimatedOneRepMax * 10).rounded() / 10)) kg"
                    ))
                } else if heaviestNow > heaviestBefore + 0.01 {
                    result.append(PersonalRecord(
                        exerciseName: ex.name,
                        headline: "\(Fmt.weight(heaviestNow)) kg",
                        detail: "Heaviest weight ever"
                    ))
                }
            case .reps:
                let now = sets.map(\.reps).max() ?? 0
                let before = previous.map(\.reps).max() ?? 0
                if now > before {
                    result.append(PersonalRecord(exerciseName: ex.name,
                                                 headline: "\(now) \(ex.repUnit ?? "reps")",
                                                 detail: "Most in one set"))
                }
            case .seconds:
                let now = sets.map(\.seconds).max() ?? 0
                let before = previous.map(\.seconds).max() ?? 0
                if now > before {
                    result.append(PersonalRecord(exerciseName: ex.name,
                                                 headline: Fmt.clock(now),
                                                 detail: "Longest hold"))
                }
            case .minutes:
                continue
            }
        }
        return result.sorted { $0.exerciseName < $1.exerciseName }
    }

    /// Monday 00:00 of the week containing `date`.
    static func startOfWeek(_ date: Date = .now) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date.startOfDay
    }
}
