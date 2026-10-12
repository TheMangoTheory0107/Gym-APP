import SwiftData
import SwiftUI

/// Stage 1: body stats (weight, body fat, BMI, FFMI) and weigh-ins.
/// Stage 5 adds lift charts, PRs, weekly volume, streak calendar and reports.
struct ProgressTabView: View {
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]
    @AppStorage(ProfileKey.heightCm) private var heightCm = ProfileDefault.heightCm
    @State private var showWeighIn = false

    private var latest: BodyMetric? { metrics.first }
    /// Latest body fat reading, even if the latest weigh-in didn't include one.
    private var latestBodyFat: Double? { metrics.lazy.compactMap(\.bodyFatPercent).first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenTitle(title: "Progress", kicker: "Body & strength")

                    if let latest {
                        bodyCard(latest)
                    }

                    Button {
                        Haptics.tap()
                        showWeighIn = true
                    } label: {
                        Label("Log weigh-in", systemImage: "scalemass.fill")
                    }
                    .buttonStyle(.primary)

                    if metrics.count > 0 {
                        SectionLabel(text: "Recent weigh-ins")
                        VStack(spacing: 8) {
                            ForEach(metrics.prefix(10)) { m in
                                HStack {
                                    Text(m.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    if let bf = m.bodyFatPercent {
                                        Text(String(format: "%.1f%%", bf))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.textFaint)
                                    }
                                    Text(String(format: "%.1f kg", m.weightKg))
                                        .font(.display(22))
                                        .foregroundStyle(Theme.textPrimary)
                                        .monospacedDigit()
                                }
                                .cardStyle(padding: 12)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .sheet(isPresented: $showWeighIn) {
                WeighInSheet(lastWeight: latest?.weightKg ?? ProfileDefault.startWeightKg,
                             lastBodyFat: latestBodyFat)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func bodyCard(_ m: BodyMetric) -> some View {
        let bmi = BodyMath.bmi(weightKg: m.weightKg, heightCm: heightCm)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                StatTile(label: "Weight", value: String(format: "%.1f", m.weightKg), unit: "kg")
                StatTile(label: "Body fat", value: latestBodyFat.map { String(format: "%.1f", $0) } ?? "—", unit: "%")
            }
            Divider().overlay(Theme.stroke)
            HStack {
                StatTile(label: "BMI · " + BodyMath.bmiCategory(bmi), value: String(format: "%.1f", bmi), highlight: true)
                if let bf = latestBodyFat {
                    StatTile(label: "FFMI", value: String(format: "%.1f",
                                                          BodyMath.ffmi(weightKg: m.weightKg, bodyFatPercent: bf, heightCm: heightCm)),
                             highlight: true)
                }
            }
            if let bf = latestBodyFat {
                HStack {
                    StatTile(label: "Lean mass",
                             value: String(format: "%.1f", BodyMath.leanMass(weightKg: m.weightKg, bodyFatPercent: bf)),
                             unit: "kg")
                    StatTile(label: "Fat mass",
                             value: String(format: "%.1f", m.weightKg * bf / 100),
                             unit: "kg")
                }
            }
            Text("BMI ignores muscle, so lifters often read \"overweight\". FFMI and body fat are the better guides for you.")
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
        }
        .cardStyle(padding: 18)
    }
}

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
