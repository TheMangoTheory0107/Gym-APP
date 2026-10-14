import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Holds today's workout from the iPhone and sends ticked-off sets back.
@Observable
@MainActor
final class WatchStore: NSObject {
    var plan: WatchPlan?
    /// When the current rest ends (nil = not resting).
    var restEndsAt: Date?
    /// Exercise picked from the list, overriding "next exercise".
    var focusIndex: Int?
    var phoneReachable = false

    @ObservationIgnored private var restTask: Task<Void, Never>?
    private static let storeKey = "watch.plan"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode(WatchPlan.self, from: data),
           Calendar.current.isDateInToday(saved.sentAt) || saved.inProgress {
            plan = saved
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
            session.activate()
        } else {
            requestPlan()
        }
    }

    // MARK: Derived

    var currentExerciseIndex: Int? {
        guard let plan else { return nil }
        if let f = focusIndex, plan.exercises.indices.contains(f), plan.exercises[f].sets.contains(where: { !$0.done }) {
            return f
        }
        return plan.nextExerciseIndex
    }

    var isResting: Bool { (restEndsAt ?? .distantPast) > .now }

    // MARK: Actions

    func start() {
        guard var p = plan else { return }
        if !p.inProgress {
            p.inProgress = true
            p.startedAt = .now
            plan = p
            save()
            send([WatchMessage.start: true])
        }
    }

    func logSet(exercise e: Int, set s: Int, weightKg: Double, reps: Int, seconds: Int) {
        guard var p = plan, p.exercises.indices.contains(e), p.exercises[e].sets.indices.contains(s) else { return }
        let ex = p.exercises[e]
        p.exercises[e].sets[s].done = true
        p.exercises[e].sets[s].weightKg = weightKg
        p.exercises[e].sets[s].reps = reps
        p.exercises[e].sets[s].seconds = seconds
        // Carry the weight to the next set.
        if s + 1 < p.exercises[e].sets.count, !p.exercises[e].sets[s + 1].done {
            p.exercises[e].sets[s + 1].weightKg = weightKg
        }
        if !p.inProgress { p.inProgress = true; p.startedAt = .now }
        plan = p
        save()
        WKInterfaceDevice.current().play(.success)

        let log = WatchSetLog(exerciseId: ex.id, setIndex: s,
                              weightKg: ex.logType == "weightReps" ? weightKg : 0,
                              reps: (ex.logType == "weightReps" || ex.logType == "reps") ? reps : 0,
                              seconds: (ex.logType == "seconds" || ex.logType == "minutes") ? seconds : 0,
                              dayName: p.dayName, splitWeekday: p.splitWeekday)
        if let data = WatchMessage.encode(log) { send([WatchMessage.logSet: data], reliable: true) }

        if ex.logType != "minutes", p.doneSets < p.totalSets {
            startRest(seconds: p.restSeconds)
        }
    }

    func startRest(seconds: Int) {
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(seconds))
        restTask?.cancel()
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.restEndsAt = nil
            WKInterfaceDevice.current().play(.stop)
            try? await Task.sleep(for: .milliseconds(600))
            WKInterfaceDevice.current().play(.start)
        }
    }

    func addRest(_ seconds: Int) {
        guard let end = restEndsAt else { return }
        let remaining = Int(end.timeIntervalSinceNow.rounded(.up)) + seconds
        startRest(seconds: max(remaining, 1))
    }

    func skipRest() {
        restTask?.cancel()
        restEndsAt = nil
    }

    func finish() {
        skipRest()
        focusIndex = nil
        if var p = plan {
            p.inProgress = false
            p.startedAt = nil
            plan = p
            save()
        }
        send([WatchMessage.finish: true], reliable: true)
    }

    func requestPlan() {
        send([WatchMessage.requestPlan: true])
    }

    // MARK: Plumbing

    private func save() {
        if let plan, let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    /// Instant when the iPhone is reachable; `reliable` messages fall back to a queued transfer.
    private func send(_ message: [String: Any], reliable: Bool = false) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                if reliable { session.transferUserInfo(message) }
            }
        } else if reliable {
            session.transferUserInfo(message)
        }
    }

    fileprivate func receive(_ dict: [String: Any]) {
        guard let incoming = WatchMessage.decode(WatchPlan.self, from: dict[WatchMessage.plan]) else { return }
        // Don't let an older plan undo a set just ticked here before the iPhone confirmed it.
        if let current = plan, current.sentAt > incoming.sentAt { return }
        plan = incoming
        save()
    }
}

extension WatchStore: WCSessionDelegate {
    private struct Box: @unchecked Sendable { let value: [String: Any] }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = Box(value: session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            self.phoneReachable = reachable
            self.receive(context.value)
            self.requestPlan()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.phoneReachable = reachable
            if reachable { self.requestPlan() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let box = Box(value: applicationContext)
        Task { @MainActor in self.receive(box.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let box = Box(value: message)
        Task { @MainActor in self.receive(box.value) }
    }
}
