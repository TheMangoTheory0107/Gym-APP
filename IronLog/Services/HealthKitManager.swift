import Foundation
import HealthKit

/// Reads and writes body weight and body fat with Apple Health.
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)
    private let bodyFat = HKQuantityType(.bodyFatPercentage)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Apple Health permission sheet (only the first time; afterwards iOS remembers the choice).
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: [bodyMass, bodyFat], read: [bodyMass, bodyFat])
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
