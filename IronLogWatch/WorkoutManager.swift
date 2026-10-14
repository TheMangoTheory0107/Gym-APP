import Foundation
import HealthKit
import Observation

/// Runs a strength-training workout on the Watch: live heart rate and calories, saved to Apple Health.
@Observable
@MainActor
final class WorkoutManager: NSObject {
    var isRunning = false
    var heartRate: Double = 0
    var activeKcal: Double = 0
    var startDate: Date?

    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
    }

    func start() async {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }
        await requestAuthorization()
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date.now
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            startDate = now
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    /// Ends the workout and saves it to Apple Health.
    func end() async {
        guard let session, let builder else { return }
        session.end()
        try? await builder.endCollection(at: .now)
        _ = try? await builder.finishWorkout()
        self.session = nil
        self.builder = nil
        isRunning = false
        heartRate = 0
        activeKcal = 0
        startDate = nil
    }

    fileprivate func update(heartRate: Double?, kcal: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let kcal { self.activeKcal = kcal }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: bpm)
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in self.update(heartRate: hr, kcal: kcal) }
    }
}
