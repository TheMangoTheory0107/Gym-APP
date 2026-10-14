import Foundation
import Observation
import SwiftData

/// Editable values for one set before (and after) it's ticked off.
struct SetDraft: Identifiable {
    let id = UUID()
    var target: RepTarget?
    var weightKg: Double
    var reps: Int
    /// Seconds for planks; total seconds for cardio (shown as minutes).
    var seconds: Int
    var log: SetLog?

    var isDone: Bool { log != nil }
}

/// One exercise in the active workout with its sets.
struct ExerciseBlock: Identifiable {
    let id: Int
    let item: SplitItem
    let exercise: ExerciseDef
    var sets: [SetDraft]
    /// e.g. "30 kg × 10"
    let lastTime: String?

    var doneCount: Int { sets.filter(\.isDone).count }
    var isComplete: Bool { doneCount == sets.count }
}

/// Drives the workout screen: pre-fills from last time, saves sets as you tick them, starts the rest timer.
@Observable
final class ActiveWorkoutModel {
    let session: WorkoutSession
    var blocks: [ExerciseBlock] = []
    var expandedBlock: Int?

    @ObservationIgnored private let context: ModelContext

    init(session: WorkoutSession, context: ModelContext) {
        self.session = session
        self.context = context
        self.blocks = buildBlocks()
        self.expandedBlock = blocks.first { !$0.isComplete }?.id
    }

    var doneSets: Int { blocks.reduce(0) { $0 + $1.doneCount } }
    var totalSets: Int { blocks.reduce(0) { $0 + $1.sets.count } }
    var volume: Double { session.totalVolume }

    /// Re-reads saved sets, e.g. after sets were ticked off on the Apple Watch.
    func reload() {
        blocks = buildBlocks()
        if let e = expandedBlock, blocks.indices.contains(e), !blocks[e].isComplete { return }
        expandedBlock = blocks.first { !$0.isComplete }?.id
    }

    // MARK: Building

    private func buildBlocks() -> [ExerciseBlock] {
        let catalog = Catalog.shared
        var blocks: [ExerciseBlock] = []
        if let day = catalog.splitDay(weekday: session.splitWeekday) {
            for item in day.items {
                guard let ex = catalog.exercise(item.exercise) else { continue }
                blocks.append(makeBlock(id: blocks.count, item: item, exercise: ex))
            }
        }
        // Exercises you added during this workout (restored when resuming).
        let planned = Set(blocks.map(\.exercise.id))
        let extras = Dictionary(grouping: session.sets.filter { !planned.contains($0.exerciseId) }, by: \.exerciseId)
            .sorted { ($0.value.map(\.completedAt).min() ?? .now) < ($1.value.map(\.completedAt).min() ?? .now) }
        for (id, _) in extras {
            guard let ex = catalog.exercise(id) else { continue }
            blocks.append(makeBlock(id: blocks.count, item: Self.defaultItem(for: ex), exercise: ex))
        }
        return blocks
    }

    private func makeBlock(id: Int, item: SplitItem, exercise ex: ExerciseDef) -> ExerciseBlock {
        let scheme = RepScheme(item.scheme)
        let last = WorkoutStats.lastTime(exerciseId: ex.id, excluding: session.id, context: context)
        let saved = session.sets.filter { $0.exerciseId == ex.id }
        let count = max(scheme.setCount, (saved.map(\.setIndex).max() ?? -1) + 1, 1)

        let drafts: [SetDraft] = (0..<count).map { i -> SetDraft in
            let target: RepTarget? = i < scheme.sets.count ? scheme.sets[i] : scheme.sets.last
            if let log = saved.first(where: { $0.setIndex == i }) {
                return SetDraft(target: target, weightKg: log.weightKg, reps: log.reps, seconds: log.seconds, log: log)
            }
            let prev: SetLog? = i < last.count ? last[i] : last.last
            return SetDraft(
                target: target,
                weightKg: prev?.weightKg ?? 0,
                reps: prev?.reps ?? target?.suggested ?? 10,
                seconds: prev?.seconds ?? Self.defaultSeconds(for: ex, target: target),
                log: nil
            )
        }
        return ExerciseBlock(id: id, item: item, exercise: ex, sets: drafts,
                             lastTime: WorkoutStats.lastSummary(last, exercise: ex))
    }

    /// Sensible starting sets for an exercise that isn't in your split.
    static func defaultItem(for ex: ExerciseDef) -> SplitItem {
        let scheme: String
        switch ex.logType {
        case .weightReps: scheme = "3x8-12"
        case .reps: scheme = "3x12"
        case .seconds: scheme = "3x45"
        case .minutes: scheme = "1x20"
        }
        return SplitItem(exercise: ex.id, scheme: scheme, note: nil)
    }

    /// Add any exercise to today's workout.
    func addExercise(_ ex: ExerciseDef) {
        if let existing = blocks.first(where: { $0.exercise.id == ex.id }) {
            expandedBlock = existing.id
            return
        }
        blocks.append(makeBlock(id: blocks.count, item: Self.defaultItem(for: ex), exercise: ex))
        expandedBlock = blocks.count - 1
    }

    private static func defaultSeconds(for ex: ExerciseDef, target: RepTarget?) -> Int {
        switch ex.logType {
        case .seconds: return target?.high ?? 60
        case .minutes: return (target?.high ?? 20) * 60
        default: return 0
        }
    }

    // MARK: Actions

    /// Tick a set: save it, move on, start the rest timer.
    func complete(block b: Int, set s: Int) {
        guard blocks.indices.contains(b), blocks[b].sets.indices.contains(s), !blocks[b].sets[s].isDone else { return }
        let draft = blocks[b].sets[s]
        let ex = blocks[b].exercise
        let log = SetLog(exerciseId: ex.id, setIndex: s,
                         weightKg: ex.logType == .weightReps ? draft.weightKg : 0,
                         reps: (ex.logType == .weightReps || ex.logType == .reps) ? draft.reps : 0,
                         seconds: (ex.logType == .seconds || ex.logType == .minutes) ? draft.seconds : 0)
        context.insert(log)
        log.session = session
        try? context.save()
        blocks[b].sets[s].log = log
        Haptics.success()

        // Carry the values forward to the next set if it hasn't been touched yet.
        if s + 1 < blocks[b].sets.count, !blocks[b].sets[s + 1].isDone {
            blocks[b].sets[s + 1].weightKg = draft.weightKg
        }

        if blocks[b].isComplete {
            expandedBlock = blocks.first { !$0.isComplete }?.id
        }

        // Rest after every set except cardio and the very last set of the workout.
        if ex.logType != .minutes, doneSets < totalSets {
            let seconds = UserDefaults.standard.object(forKey: ProfileKey.restSeconds) as? Int ?? ProfileDefault.restSeconds
            RestTimer.shared.start(seconds: seconds, nextUp: nextUpLabel(), workoutName: session.dayName)
        } else {
            RestTimer.shared.skip()
        }
        PhoneWatchBridge.sync()
    }

    /// Un-tick a set to edit it.
    func undo(block b: Int, set s: Int) {
        guard let log = blocks[b].sets[s].log else { return }
        context.delete(log)
        try? context.save()
        blocks[b].sets[s].log = nil
        Haptics.tap()
        PhoneWatchBridge.sync()
    }

    func addSet(block b: Int) {
        guard let last = blocks[b].sets.last else { return }
        blocks[b].sets.append(SetDraft(target: last.target, weightKg: last.weightKg, reps: last.reps,
                                       seconds: last.seconds, log: nil))
        expandedBlock = b
        Haptics.tap()
    }

    func finish() {
        RestTimer.shared.skip()
        session.finishedAt = .now
        try? context.save()
        WidgetSync.update(context: context)
        Haptics.success()
        PhoneWatchBridge.sync()
    }

    func discard() {
        RestTimer.shared.skip()
        context.delete(session)
        try? context.save()
        PhoneWatchBridge.sync()
    }

    private func nextUpLabel() -> String {
        guard let b = blocks.first(where: { !$0.isComplete }) else { return "" }
        let setNumber = b.doneCount + 1
        return "\(b.exercise.name) · set \(setNumber)"
    }
}
