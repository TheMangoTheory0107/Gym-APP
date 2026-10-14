import SwiftData
import SwiftUI

/// Today's water with quick-add buttons and optional reminders.
struct WaterCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WaterLog.date, order: .reverse) private var logs: [WaterLog]
    @AppStorage(ProfileKey.waterTargetMl) private var target = ProfileDefault.waterTargetMl
    @AppStorage(ProfileKey.waterReminders) private var reminders = false

    private var today: [WaterLog] {
        let start = Date.now.startOfDay
        return logs.filter { $0.date >= start }
    }
    private var total: Double { today.reduce(0) { $0 + $1.ml } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("WATER", systemImage: "drop.fill")
                    .font(.display(19))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "%.1f", total / 1000))
                    .font(.display(30))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ \(String(format: "%.1f", target / 1000)) L")
                    .font(.display(18))
                    .foregroundStyle(Theme.textFaint)
            }

            // One drop per ~ 1/10 of the target.
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { i in
                    let filled = total >= target * Double(i + 1) / 10 - 1
                    Image(systemName: filled ? "drop.fill" : "drop")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(filled ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.textFaint))
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                addButton(250, "Glass")
                addButton(500, "Bottle")
                Button {
                    if let last = today.first {
                        context.delete(last)
                        try? context.save()
                        Haptics.tap()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .disabled(today.isEmpty)
                .accessibilityLabel("Undo last water")

                Button {
                    reminders.toggle()
                    Haptics.select()
                    Task {
                        if reminders { await NotificationManager.shared.requestPermission() }
                        WaterService.setReminders(reminders)
                    }
                } label: {
                    Image(systemName: reminders ? "bell.fill" : "bell.slash")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(reminders ? Theme.ember : Theme.textSecondary)
                .accessibilityLabel(reminders ? "Water reminders on" : "Water reminders off")
            }
            if reminders {
                Text("Reminders every 2 hours, 9 AM – 9 PM.")
                    .font(.caption)
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .cardStyle()
    }

    private func addButton(_ ml: Double, _ label: String) -> some View {
        Button {
            withAnimation(.snappy) { WaterService.log(ml: ml, context: context) }
        } label: {
            VStack(spacing: 0) {
                Text("+\(Int(ml)) ML").font(.display(19))
                Text(label.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
    }
}

/// Steps, active calories and exercise minutes from Apple Health, plus workouts recorded elsewhere.
struct ActivityCard: View {
    var health = HealthData.shared
    @AppStorage(ProfileKey.healthSyncEnabled) private var connected = false
    @State private var connecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ACTIVITY", systemImage: "figure.walk.motion")
                    .font(.display(19))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if connected {
                    Text("APPLE HEALTH")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.textFaint)
                }
            }
            if connected {
                HStack(spacing: 10) {
                    metric("figure.walk", Int(health.today.steps).formatted(), "Steps", progress: health.today.steps / 10_000)
                    metric("flame.fill", "\(Int(health.today.activeKcal))", "Active kcal", progress: health.today.activeKcal / 600)
                    metric("timer", "\(Int(health.today.exerciseMinutes))", "Exercise min", progress: health.today.exerciseMinutes / 30)
                }
                ForEach(health.todaysWorkouts) { w in
                    HStack(spacing: 12) {
                        Image(systemName: w.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.ember)
                            .frame(width: 38, height: 38)
                            .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.name.uppercased()).font(.display(19)).foregroundStyle(Theme.textPrimary)
                            Text("\(w.minutes) min · \(w.kcal) kcal · \(w.source)")
                                .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ember)
                    }
                }
            } else {
                Text("See steps, calories and workouts from your iPhone and Apple Watch here automatically.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    connect()
                } label: {
                    Label(connecting ? "Connecting…" : "Connect Apple Health", systemImage: "heart.fill")
                }
                .buttonStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func metric(_ icon: String, _ value: String, _ label: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ember)
            Text(value).font(.display(26)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            GradientBar(progress: progress, height: 4)
            Text(label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connect() {
        connecting = true
        Task {
            do {
                try await HealthKitManager.shared.requestAuthorization()
                connected = true
                await HealthData.shared.refresh()
                Haptics.success()
            } catch {
                Haptics.warning()
            }
            connecting = false
        }
    }
}
