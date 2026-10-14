import Foundation
import SwiftData
import WatchConnectivity

extension Notification.Name {
    /// Posted on the main thread after the Watch saved a set, so an open workout screen can refresh.
    static let watchLoggedSet = Notification.Name("watchLoggedSet")
}

/// Keeps the Apple Watch app in sync: sends today's workout, saves sets ticked off on the Watch.
@MainActor
final class PhoneWatchBridge: NSObject {
    static let shared = PhoneWatchBridge()

    private var container: ModelContainer?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func configure(container: ModelContainer) {
        self.container = container
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: Sending

    /// Safe to call from anywhere; hops to the main thread.
    nonisolated static func sync() {
        Task { @MainActor in shared.sendPlan() }
    }

    /// Sends the latest plan. Cheap; call after anything that changes today's workout.
    func sendPlan() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let plan = makePlan(), let data = WatchMessage.encode(plan) else { return }
        try? session.updateApplicationContext([WatchMessage.plan: data])
        if session.isReachable {
            session.sendMessage([WatchMessage.plan: data], replyHandler: nil, errorHandler: nil)
        }
    }

    private func makePlan() -> WatchPlan? {
        guard let context = container?.mainContext else { return nil }
        let open = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])))?.first
        let weekday = open?.splitWeekday ?? Calendar.current.component(.weekday, from: .now)
        let day = Catalog.shared.splitDay(weekday: weekday)
        let restSeconds = UserDefaults.standard.object(forKey: ProfileKey.restSeconds) as? Int ?? ProfileDefault.restSeconds

        guard let day, !day.isRest || open != nil else {
            return WatchPlan(dayName: day?.name ?? "Rest day", splitWeekday: weekday, isRestDay: true, inProgress: false,
                             startedAt: nil, restSeconds: restSeconds, exercises: [], sentAt: .now)
        }

        // Build the same blocks the iPhone workout screen shows (pre-filled from last time).
        let session = open ?? WorkoutSession(dayName: day.name, splitWeekday: weekday)
        let model = ActiveWorkoutModel(session: session, context: context)
        let exercises = model.blocks.map { block in
            WatchExercise(
                id: block.exercise.id,
                name: block.exercise.name,
                logType: block.exercise.logType.rawValue,
                weightStep: block.exercise.weightStep ?? 2.5,
                muscles: Catalog.shared.muscleNames(block.exercise.primary).joined(separator: ", "),
                sets: block.sets.enumerated().map { i, s in
                    WatchSet(index: i, target: s.target?.text ?? "", weightKg: s.weightKg, reps: s.reps,
                             seconds: s.seconds, done: s.isDone)
                })
        }
        return WatchPlan(dayName: open?.dayName ?? day.name, splitWeekday: weekday, isRestDay: false,
                         inProgress: open != nil, startedAt: open?.effectiveStart, restSeconds: restSeconds,
                         exercises: exercises, sentAt: .now)
    }

    // MARK: Receiving

    private func handle(_ message: [String: Any]) {
        guard let context = container?.mainContext else { return }
        if let log = WatchMessage.decode(WatchSetLog.self, from: message[WatchMessage.logSet]) {
            let session: WorkoutSession
            if let open = openSession(context: context) {
                session = open
            } else {
                session = WorkoutSession(dayName: log.dayName, splitWeekday: log.splitWeekday)
                context.insert(session)
            }
            if session.isPaused { session.resume() }
            let exists = session.sets.contains { $0.exerciseId == log.exerciseId && $0.setIndex == log.setIndex }
            if !exists {
                let set = SetLog(exerciseId: log.exerciseId, setIndex: log.setIndex, weightKg: log.weightKg,
                                 reps: log.reps, seconds: log.seconds)
                context.insert(set)
                set.session = session
            }
            try? context.save()
            NotificationCenter.default.post(name: .watchLoggedSet, object: nil)
        } else if message[WatchMessage.start] != nil {
            if openSession(context: context) == nil {
                let weekday = Calendar.current.component(.weekday, from: .now)
                if let day = Catalog.shared.splitDay(weekday: weekday), !day.isRest {
                    context.insert(WorkoutSession(dayName: day.name, splitWeekday: weekday))
                    try? context.save()
                    NotificationCenter.default.post(name: .watchLoggedSet, object: nil)
                }
            }
        } else if message[WatchMessage.finish] != nil {
            if let open = openSession(context: context) {
                if open.isPaused { open.resume() }
                if open.sets.isEmpty { context.delete(open) } else { open.finishedAt = .now }
                try? context.save()
                WidgetSync.update(context: context)
                NotificationCenter.default.post(name: .watchLoggedSet, object: nil)
            }
        }
        sendPlan()
    }

    private func openSession(context: ModelContext) -> WorkoutSession? {
        (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])))?.first
    }
}

extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.sendPlan() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendPlan() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let copy = Self.sendable(message)
        Task { @MainActor in self.handle(copy.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let copy = Self.sendable(userInfo)
        Task { @MainActor in self.handle(copy.value) }
    }

    /// WatchConnectivity dictionaries only hold property-list values, so they're safe to hop threads.
    private struct Box: @unchecked Sendable { let value: [String: Any] }
    private nonisolated static func sendable(_ dict: [String: Any]) -> Box { Box(value: dict) }
}
