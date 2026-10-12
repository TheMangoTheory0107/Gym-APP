import SwiftData
import SwiftUI

/// Weight entry with big +/- buttons. Optionally also saves to Apple Health.
struct WeighInSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProfileKey.healthSyncEnabled) private var healthSync = false

    @State private var weight: Double
    @State private var includeBodyFat: Bool
    @State private var bodyFat: Double
    @State private var errorText: String?

    init(lastWeight: Double, lastBodyFat: Double?) {
        _weight = State(initialValue: (lastWeight * 10).rounded() / 10)
        _includeBodyFat = State(initialValue: false)
        _bodyFat = State(initialValue: lastBodyFat ?? ProfileDefault.startBodyFat)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    BigNumberStepper(label: "Weight", value: $weight, step: 0.1, unit: "kg", range: 30...250)

                    Toggle(isOn: $includeBodyFat) {
                        Text("ADD BODY FAT %").font(.display(20)).foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .cardStyle(padding: 14)

                    if includeBodyFat {
                        BigNumberStepper(label: "Body fat", value: $bodyFat, step: 0.1, unit: "%", range: 3...60)
                    }

                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Theme.accent)
                    }

                    Button("Save", action: save).buttonStyle(.primary)
                }
                .padding(Theme.gutter)
            }
            .screenBackground()
            .navigationTitle("WEIGH-IN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func save() {
        let bf = includeBodyFat ? bodyFat : nil
        context.insert(BodyMetric(weightKg: weight, bodyFatPercent: bf))
        try? context.save()
        Haptics.success()
        if healthSync {
            let w = weight
            Task {
                do {
                    try await HealthKitManager.shared.saveWeight(kg: w)
                    if let bf { try await HealthKitManager.shared.saveBodyFat(percent: bf) }
                } catch {
                    // The weigh-in is already saved in the app; Health sync is best-effort.
                    print("Health save failed: \(error)")
                }
            }
        }
        dismiss()
    }
}

/// Large value with chunky − / + buttons, built for one-handed use.
struct BigNumberStepper: View {
    let label: String
    @Binding var value: Double
    let step: Double
    let unit: String
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 6) {
            SectionLabel(text: label)
            HStack(spacing: 12) {
                stepButton("minus", delta: -step)
                Text(String(format: step < 1 ? "%.1f" : "%.0f", value))
                    .font(.display(56))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .overlay(alignment: .bottomTrailing) {
                        Text(unit.uppercased()).font(.display(16)).foregroundStyle(Theme.textSecondary)
                    }
                stepButton("plus", delta: step)
            }
        }
        .cardStyle(padding: 14)
    }

    private func stepButton(_ icon: String, delta: Double) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) {
                value = min(max(((value + delta) * 10).rounded() / 10, range.lowerBound), range.upperBound)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 60, height: 60)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }
}
