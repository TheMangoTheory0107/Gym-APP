import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(ProfileKey.heightCm) private var heightCm = ProfileDefault.heightCm
    @AppStorage(ProfileKey.kcalTarget) private var kcalTarget = ProfileDefault.kcal
    @AppStorage(ProfileKey.proteinTarget) private var proteinTarget = ProfileDefault.protein
    @AppStorage(ProfileKey.carbsTarget) private var carbsTarget = ProfileDefault.carbs
    @AppStorage(ProfileKey.fatTarget) private var fatTarget = ProfileDefault.fat
    @AppStorage(ProfileKey.restSeconds) private var restSeconds = ProfileDefault.restSeconds
    @AppStorage(ProfileKey.healthSyncEnabled) private var healthSync = false

    @State private var healthStatus = ""
    @State private var notificationStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    numberRow("Height", value: $heightCm, unit: "cm", step: 0.5)
                } header: { header("Profile") }

                Section {
                    numberRow("Calories", value: $kcalTarget, unit: "kcal", step: 50)
                    numberRow("Protein", value: $proteinTarget, unit: "g", step: 5)
                    numberRow("Carbs", value: $carbsTarget, unit: "g", step: 5)
                    numberRow("Fat", value: $fatTarget, unit: "g", step: 5)
                } header: { header("Daily targets") }

                Section {
                    Stepper(value: $restSeconds, in: 30...300, step: 15) {
                        HStack {
                            Text("Default rest")
                            Spacer()
                            Text("\(restSeconds) s").foregroundStyle(Theme.textSecondary).monospacedDigit()
                        }
                    }
                } header: { header("Workout") }

                Section {
                    Toggle("Sync weight with Apple Health", isOn: $healthSync)
                        .tint(Theme.accent)
                        .onChange(of: healthSync) { _, on in
                            if on { Task { await connectHealth() } }
                        }
                    Button("Import latest weight from Health") {
                        Task { await importFromHealth() }
                    }
                    .disabled(!healthSync)
                    if !healthStatus.isEmpty {
                        Text(healthStatus).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                } header: { header("Apple Health") }

                Section {
                    Button("Allow notifications") {
                        Task {
                            let ok = await NotificationManager.shared.requestPermission()
                            notificationStatus = ok ? "Notifications allowed." : "Not allowed. Turn on in iPhone Settings → Iron Log → Notifications."
                        }
                    }
                    Button("Send test notification in 5 s") {
                        Task {
                            guard await NotificationManager.shared.isAuthorized() else {
                                notificationStatus = "Tap \"Allow notifications\" first."
                                return
                            }
                            NotificationManager.shared.sendTest(after: 5)
                            Haptics.success()
                            notificationStatus = "Sent. Lock your phone now; it should buzz in 5 seconds."
                        }
                    }
                    if !notificationStatus.isEmpty {
                        Text(notificationStatus).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                } header: { header("Notifications") }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("Exercises loaded", value: "\(Catalog.shared.exercises.count)")
                } header: { header("About") }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(.display(18)).foregroundStyle(Theme.accent)
    }

    private func numberRow(_ label: String, value: Binding<Double>, unit: String, step: Double) -> some View {
        Stepper(value: value, in: 0...10_000, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: step < 1 ? "%.1f %@" : "%.0f %@", value.wrappedValue, unit))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func connectHealth() async {
        do {
            try await HealthKitManager.shared.requestAuthorization()
            healthStatus = HealthKitManager.shared.canWriteWeight
                ? "Connected. New weigh-ins will be saved to Apple Health."
                : "Write access is off. Enable it in the Health app → Profile → Apps → Iron Log."
            Haptics.success()
        } catch {
            healthStatus = "Couldn't connect: \(error.localizedDescription)"
            healthSync = false
        }
    }

    private func importFromHealth() async {
        do {
            guard let latest = try await HealthKitManager.shared.latestWeight() else {
                healthStatus = "No weight found in Apple Health (or read access is off)."
                return
            }
            let bodyFat = try? await HealthKitManager.shared.latestBodyFat()
            context.insert(BodyMetric(date: latest.date, weightKg: latest.kg,
                                      bodyFatPercent: bodyFat?.percent, source: "health"))
            try? context.save()
            healthStatus = String(format: "Imported %.1f kg from %@.", latest.kg,
                                  latest.date.formatted(date: .abbreviated, time: .omitted))
            Haptics.success()
        } catch {
            healthStatus = "Couldn't read Health: \(error.localizedDescription)"
        }
    }
}
