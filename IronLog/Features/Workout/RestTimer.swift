import ActivityKit
import Observation
import SwiftUI

/// Rest countdown between sets. The end time is stored as a date, so it stays correct while the
/// phone is locked; a local notification fires at the end even if the app is in the background.
@Observable
final class RestTimer {
    static let shared = RestTimer()
    private static let notificationId = "rest-end"

    private(set) var endDate: Date?
    private(set) var totalSeconds = 0
    private(set) var nextUp = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var activity: Activity<RestActivityAttributes>?
    @ObservationIgnored private var workoutName = ""

    var isRunning: Bool { endDate != nil }

    func start(seconds: Int, nextUp: String, workoutName: String = "") {
        self.nextUp = nextUp
        if !workoutName.isEmpty { self.workoutName = workoutName }
        totalSeconds = seconds
        endDate = Date.now.addingTimeInterval(TimeInterval(seconds))
        reschedule()
    }

    func adjust(by seconds: Int) {
        guard let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > .now else { skip(); return }
        endDate = newEnd
        totalSeconds = max(totalSeconds + seconds, 1)
        Haptics.tap()
        reschedule()
    }

    func skip() {
        task?.cancel()
        task = nil
        endDate = nil
        NotificationManager.shared.cancel(id: Self.notificationId)
        endActivity()
    }

    /// Called when the app comes back to the foreground: clear a timer that ended while locked.
    func refresh() {
        if let end = endDate, end <= .now { finish(buzz: false) }
    }

    private func reschedule() {
        guard let end = endDate else { return }
        let remaining = end.timeIntervalSinceNow
        NotificationManager.shared.schedule(
            id: Self.notificationId,
            title: "REST OVER",
            body: nextUp.isEmpty ? "Time for your next set." : "Next: \(nextUp)",
            after: remaining
        )
        updateActivity(end: end)
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(remaining, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finish(buzz: true) }
        }
    }

    private func finish(buzz: Bool) {
        task?.cancel()
        task = nil
        endDate = nil
        endActivity()
        if buzz { Haptics.thud(); Haptics.success() }
    }

    // MARK: Live Activity (Lock Screen + Dynamic Island)

    private func updateActivity(end: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestActivityAttributes.ContentState(endDate: end, totalSeconds: totalSeconds, nextUp: nextUp)
        let content = ActivityContent(state: state, staleDate: end.addingTimeInterval(30))
        if let activity {
            Task { await activity.update(content) }
        } else {
            activity = try? Activity.request(attributes: RestActivityAttributes(workoutName: workoutName),
                                             content: content, pushType: nil)
        }
    }

    private func endActivity() {
        guard let current = activity else { return }
        activity = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }
}

/// Bottom bar showing the rest countdown with -15 / +15 / skip.
struct RestTimerBar: View {
    var timer = RestTimer.shared

    var body: some View {
        if let end = timer.endDate {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = max(end.timeIntervalSince(context.date), 0)
                let progress = timer.totalSeconds > 0 ? remaining / Double(timer.totalSeconds) : 0

                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.cardRaised)
                            Capsule().fill(Theme.accent).frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("REST")
                                .font(.display(16))
                                .tracking(2)
                                .foregroundStyle(Theme.accent)
                            Text(Fmt.clock(Int(remaining.rounded(.up))))
                                .font(.display(44))
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                        }
                        Spacer()
                        barButton("−15") { timer.adjust(by: -15) }
                        barButton("+15") { timer.adjust(by: 15) }
                        barButton("SKIP", filled: true) { Haptics.tap(); timer.skip() }
                    }
                    if !timer.nextUp.isEmpty {
                        Text("NEXT: \(timer.nextUp.uppercased())")
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                .padding(14)
                .background(Theme.surface)
                .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func barButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.display(20))
                .foregroundStyle(filled ? Color.white : Theme.textPrimary)
                .frame(width: 64, height: 52)
                .background(filled ? Theme.accent : Theme.cardRaised,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
