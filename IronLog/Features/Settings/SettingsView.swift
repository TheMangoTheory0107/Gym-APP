import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(ProfileKey.heightCm) private var heightCm = ProfileDefault.heightCm
    @AppStorage(ProfileKey.kcalTarget) private var kcalTarget = ProfileDefault.kcal
    @AppStorage(ProfileKey.proteinTarget) private var proteinTarget = ProfileDefault.protein
    @AppStorage(ProfileKey.carbsTarget) private var carbsTarget = ProfileDefault.carbs
    @AppStorage(ProfileKey.fatTarget) private var fatTarget = ProfileDefault.fat
    @AppStorage(ProfileKey.fiberTarget) private var fiberTarget = ProfileDefault.fiber
    @AppStorage(ProfileKey.restSeconds) private var restSeconds = ProfileDefault.restSeconds
    @AppStorage(ProfileKey.healthSyncEnabled) private var healthSync = false
    @AppStorage(ProfileKey.waterTargetMl) private var waterTarget = ProfileDefault.waterTargetMl
    @AppStorage(ProfileKey.name) private var name = ProfileDefault.name
    @AppStorage(ProfileKey.onboarded) private var onboarded = true

    @State private var healthStatus = ""
    @State private var notificationStatus = ""
    @State private var backupURL: URL?
    @State private var backupStatus = ""
    @State private var importing = false
    @State private var pendingRestore: BackupService.Backup?
    @AppStorage("backup.weeklyReminder") private var weeklyBackupReminder = false
    @AppStorage(BackupService.lastBackupKey) private var lastBackup: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    numberRow("Height", value: $heightCm, unit: "cm", step: 0.5)
                } header: { header("Profile") }

                Section {
                    numberRow("Calories", value: $kcalTarget, unit: "kcal", step: 50)
                    numberRow("Protein", value: $proteinTarget, unit: "g", step: 5)
                    numberRow("Carbs", value: $carbsTarget, unit: "g", step: 5)
                    numberRow("Fat", value: $fatTarget, unit: "g", step: 5)
                    numberRow("Fibre", value: $fiberTarget, unit: "g", step: 5)
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
                    numberRow("Daily water", value: $waterTarget, unit: "ml", step: 250)
                } header: { header("Water") }

                Section {
                    Toggle("Connect Apple Health", isOn: $healthSync)
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
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("Save backup file…", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            makeBackup()
                        } label: {
                            Label("Export all data", systemImage: "externaldrive.fill")
                        }
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Import from backup", systemImage: "square.and.arrow.down")
                    }
                    Toggle("Weekly backup reminder (Sun 8 PM)", isOn: $weeklyBackupReminder)
                        .tint(Theme.accent)
                        .onChange(of: weeklyBackupReminder) { _, on in
                            Task {
                                if on { await NotificationManager.shared.requestPermission() }
                                BackupService.setWeeklyReminder(on)
                            }
                        }
                    if lastBackup > 0 {
                        Text("Last export: \(Date(timeIntervalSince1970: lastBackup).formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    if !backupStatus.isEmpty {
                        Text(backupStatus).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                } header: { header("Backup") } footer: {
                    Text("Save the file to iCloud Drive or Files. Import replaces everything currently in the app.")
                }

                Section {
                    Text("Muscle images: Z-Anatomy (CC BY-SA 4.0), based on BodyParts3D, © The Database Center for Life Science (CC BY-SA 2.1 JP). Rendered for Iron Log.")
                    Text("Exercise photos: free-exercise-db (public domain).")
                    Text("Font: Bebas Neue (SIL Open Font License).")
                } header: { header("Credits") }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("Exercises loaded", value: "\(Catalog.shared.exercises.count)")
                    Button("Show welcome screens again") { onboarded = false }
                } header: { header("About") }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do { pendingRestore = try BackupService.read(url) } catch {
                        backupStatus = "That file isn't an Iron Log backup (\(error.localizedDescription))."
                    }
                case .failure(let error):
                    backupStatus = error.localizedDescription
                }
            }
            .confirmationDialog(restoreTitle, isPresented: Binding(get: { pendingRestore != nil },
                                                                    set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible) {
                Button("Replace all data", role: .destructive) {
                    guard let b = pendingRestore else { return }
                    do {
                        try BackupService.restore(b, context: context)
                        backupStatus = "Restored \(b.sessions.count) workouts, \(b.food.count) food entries, \(b.bodyMetrics.count) weigh-ins."
                        Haptics.success()
                    } catch {
                        backupStatus = "Restore failed: \(error.localizedDescription)"
                    }
                    pendingRestore = nil
                }
            }
        }
    }

    private var restoreTitle: String {
        guard let b = pendingRestore else { return "" }
        return "Restore backup from \(b.exportedAt.formatted(date: .abbreviated, time: .shortened))? This replaces everything in the app."
    }

    private func makeBackup() {
        do {
            backupURL = try BackupService.export(context: context)
            backupStatus = "Backup ready. Tap “Save backup file…” and choose Save to Files."
            Haptics.success()
        } catch {
            backupStatus = "Export failed: \(error.localizedDescription)"
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
            await HealthData.shared.refresh()
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
