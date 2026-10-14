import Foundation
import HealthKit

/// Today's movement from Apple Health (iPhone + Apple Watch + any connected app).
struct ActivitySummary: Equatable {
    var steps: Double = 0
    var activeKcal: Double = 0
    var exerciseMinutes: Double = 0
    var distanceKm: Double = 0
}

/// A workout recorded by the Fitness app, Apple Watch or another app.
struct HealthWorkout: Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbol: String
    let start: Date
    let minutes: Int
    let kcal: Int
    let source: String
    let isCardio: Bool
}

/// Reads and writes Apple Health data: weight, body fat, water, steps, activity and workouts.
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)
    private let bodyFat = HKQuantityType(.bodyFatPercentage)
    private let water = HKQuantityType(.dietaryWater)
    private let steps = HKQuantityType(.stepCount)
    private let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private let exerciseTime = HKQuantityType(.appleExerciseTime)
    private let distance = HKQuantityType(.distanceWalkingRunning)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Apple Health permission sheet (only the first time; afterwards iOS remembers the choice).
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(
            toShare: [bodyMass, bodyFat, water],
            read: [bodyMass, bodyFat, water, steps, activeEnergy, exerciseTime, distance, HKObjectType.workoutType()]
        )
    }

    // MARK: Water

    func saveWater(ml: Double, date: Date = .now) async throws {
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml)
        try await store.save(HKQuantitySample(type: water, quantity: quantity, start: date, end: date))
    }

    // MARK: Activity

    func activity(on day: Date = .now) async -> ActivitySummary {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        async let s = sum(steps, .count(), start, end)
        async let k = sum(activeEnergy, .kilocalorie(), start, end)
        async let e = sum(exerciseTime, .minute(), start, end)
        async let d = sum(distance, .meterUnit(with: .kilo), start, end)
        return ActivitySummary(steps: await s, activeKcal: await k, exerciseMinutes: await e, distanceKm: await d)
    }

    /// Steps per day for the last `days` days, oldest first.
    func dailySteps(days: Int) async -> [(Date, Double)] {
        var out: [(Date, Double)] = []
        let today = Calendar.current.startOfDay(for: .now)
        for offset in (0..<days).reversed() {
            guard let start = Calendar.current.date(byAdding: .day, value: -offset, to: today),
                  let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { continue }
            out.append((start, await sum(steps, .count(), start, end)))
        }
        return out
    }

    private func sum(_ type: HKQuantityType, _ unit: HKUnit, _ start: Date, _ end: Date) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate),
                                                     options: .cumulativeSum)
        let stats = try? await descriptor.result(for: store)
        return stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    // MARK: Workouts

    /// Workouts recorded elsewhere (Fitness app, Apple Watch, Strava...) since `start`, newest first.
    func workouts(since start: Date) async -> [HealthWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 100
        )
        let results = (try? await descriptor.result(for: store)) ?? []
        return results.map { w in
            let info = HealthKitManager.describe(w.workoutActivityType)
            let kcal = w.statistics(for: activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            return HealthWorkout(id: w.uuid, name: info.name, symbol: info.symbol, start: w.startDate,
                                 minutes: Int((w.duration / 60).rounded()), kcal: Int(kcal.rounded()),
                                 source: w.sourceRevision.source.name, isCardio: info.cardio)
        }
    }

    static func describe(_ type: HKWorkoutActivityType) -> (name: String, symbol: String, cardio: Bool) {
        switch type {
        case .running: return ("Run", "figure.run", true)
        case .walking: return ("Walk", "figure.walk", true)
        case .cycling: return ("Cycling", "figure.outdoor.cycle", true)
        case .elliptical: return ("Elliptical", "figure.elliptical", true)
        case .rowing: return ("Rowing", "figure.rower", true)
        case .stairClimbing, .stairs: return ("Stair climber", "figure.stair.stepper", true)
        case .swimming: return ("Swim", "figure.pool.swim", true)
        case .highIntensityIntervalTraining: return ("HIIT", "figure.highintensity.intervaltraining", true)
        case .jumpRope: return ("Jump rope", "figure.jumprope", true)
        case .hiking: return ("Hike", "figure.hiking", true)
        case .mixedCardio: return ("Cardio", "figure.mixed.cardio", true)
        case .traditionalStrengthTraining: return ("Strength training", "figure.strengthtraining.traditional", false)
        case .functionalStrengthTraining: return ("Functional strength", "figure.strengthtraining.functional", false)
        case .coreTraining: return ("Core training", "figure.core.training", false)
        case .yoga: return ("Yoga", "figure.yoga", false)
        case .flexibility: return ("Flexibility", "figure.flexibility", false)
        case .cricket: return ("Cricket", "figure.cricket", true)
        case .badminton: return ("Badminton", "figure.badminton", true)
        case .tennis: return ("Tennis", "figure.tennis", true)
        case .soccer: return ("Football", "figure.soccer", true)
        case .basketball: return ("Basketball", "figure.basketball", true)
        case .boxing, .kickboxing: return ("Boxing", "figure.boxing", true)
        case .socialDance, .cardioDance: return ("Dance", "figure.dance", true)
        default: return ("Workout", "figure.mixed.cardio", true)
        }
    }

    /// Whether the user allowed writing weight. (iOS never reveals read permission, by design.)
    var canWriteWeight: Bool {
        store.authorizationStatus(for: bodyMass) == .sharingAuthorized
    }

    func saveWeight(kg: Double, date: Date = .now) async throws {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        try await store.save(HKQuantitySample(type: bodyMass, quantity: quantity, start: date, end: date))
    }

    func saveBodyFat(percent: Double, date: Date = .now) async throws {
        let quantity = HKQuantity(unit: .percent(), doubleValue: percent / 100)
        try await store.save(HKQuantitySample(type: bodyFat, quantity: quantity, start: date, end: date))
    }

    /// Most recent weight in Apple Health (from any app or smart scale).
    func latestWeight() async throws -> (kg: Double, date: Date)? {
        guard let sample = try await latestSample(of: bodyMass) else { return nil }
        return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.endDate)
    }

    /// Most recent body fat percentage in Apple Health, as 0–100.
    func latestBodyFat() async throws -> (percent: Double, date: Date)? {
        guard let sample = try await latestSample(of: bodyFat) else { return nil }
        return (sample.quantity.doubleValue(for: .percent()) * 100, sample.endDate)
    }

    private func latestSample(of type: HKQuantityType) async throws -> HKQuantitySample? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first
    }

    enum HealthError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Apple Health isn't available on this device." }
    }
}
