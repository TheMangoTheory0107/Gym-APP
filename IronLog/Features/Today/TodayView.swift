import SwiftData
import SwiftUI

struct TodayView: View {
    private let catalog = Catalog.shared
    private let todayWeekday = Calendar.current.component(.weekday, from: .now)

    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var selectedWeekday = Calendar.current.component(.weekday, from: .now)
    @State private var showSettings = false
    @State private var activeSession: WorkoutSession?

    private var openSession: WorkoutSession? { sessions.first { !$0.isFinished } }

    /// A finished workout for the selected split day, done today.
    private var doneToday: WorkoutSession? {
        sessions.first { $0.isFinished && $0.splitWeekday == selectedWeekday && $0.startedAt >= Date.now.startOfDay }
    }

    private var day: SplitDay? { catalog.splitDay(weekday: selectedWeekday) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !catalog.loadErrors.isEmpty {
                        DataErrorBanner(errors: catalog.loadErrors)
                    }

                    ScreenTitle(title: day?.name ?? "No plan", kicker: kicker)

                    DaySwitcher(selected: $selectedWeekday, today: todayWeekday)

                    if let open = openSession {
                        Button {
                            Haptics.thud()
                            activeSession = open
                        } label: {
                            Label("Resume · \(open.dayName)", systemImage: "play.fill")
                        }
                        .buttonStyle(.primary)
                    }

                    if let day, !day.isRest {
                        if let done = doneToday {
                            CompletedCard(session: done)
                        } else if openSession == nil {
                            Button {
                                start(day)
                            } label: {
                                Label("Start workout", systemImage: "bolt.fill")
                            }
                            .buttonStyle(.primary)
                        }
                        workoutList(day)
                    } else {
                        RestDayCard()
                        WeeklySummaryCard(sessions: sessions)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(item: $activeSession) { session in
                ActiveWorkoutView(session: session, context: context)
            }
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
        }
    }

    private func start(_ day: SplitDay) {
        Haptics.thud()
        let session = WorkoutSession(dayName: day.name, splitWeekday: selectedWeekday)
        context.insert(session)
        try? context.save()
        activeSession = session
        Task { await NotificationManager.shared.requestPermission() }
    }

    private var kicker: String {
        let dayName = Catalog.weekdayNames[selectedWeekday - 1]
        if selectedWeekday == todayWeekday {
            return "Today · " + Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
        return "\(dayName)'s session"
    }

    @ViewBuilder
    private func workoutList(_ day: SplitDay) -> some View {
        let items = day.items.compactMap { item in catalog.exercise(item.exercise).map { (item, $0) } }

        HStack(spacing: 12) {
            StatTile(label: "Exercises", value: "\(items.count)")
            StatTile(label: "Sets", value: "\(items.reduce(0) { $0 + RepScheme($1.0.scheme).setCount })")
            StatTile(label: "Focus", value: focusLabel(items.map(\.1)), highlight: true)
        }
        .cardStyle()

        SectionLabel(text: "Today's work")

        VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, pair in
                NavigationLink(value: pair.1) {
                    ExerciseRow(number: index + 1, exercise: pair.1, item: pair.0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func focusLabel(_ exercises: [ExerciseDef]) -> String {
        let groups = exercises.flatMap(\.primary).compactMap { catalog.muscle($0)?.group }
        let counts = Dictionary(groups.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key ?? "—"
    }
}

// MARK: - Pieces

private struct ExerciseRow: View {
    let number: Int
    let exercise: ExerciseDef
    let item: SplitItem

    var body: some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", number))
                .font(.display(28))
                .foregroundStyle(Theme.accent)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name.uppercased())
                    .font(.display(22, relativeTo: .headline))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(RepScheme(item.scheme).summary(for: exercise))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                if !exercise.primary.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Catalog.shared.muscleNames(exercise.primary), id: \.self) { Tag(text: $0) }
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .cardStyle(padding: 14)
        .contentShape(Rectangle())
    }
}

/// Seven big day buttons. Tapping one loads that day's session (for when you miss a day).
private struct DaySwitcher: View {
    @Binding var selected: Int
    let today: Int

    // Monday-first order
    private let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let isSelected = weekday == selected
                Button {
                    Haptics.select()
                    withAnimation(.snappy) { selected = weekday }
                } label: {
                    VStack(spacing: 2) {
                        Text(String(Catalog.weekdayNames[weekday - 1].prefix(3)).uppercased())
                            .font(.display(18))
                        Circle()
                            .fill(weekday == today ? (isSelected ? Color.white : Theme.accent) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                    .background(isSelected ? Theme.accent : Theme.card,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Catalog.weekdayNames[weekday - 1])
            }
        }
    }
}

private struct RestDayCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("RECOVERY DAY")
                .font(.display(30))
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 8) {
                Label("Sleep 7–9 hours", systemImage: "moon.fill")
                Label("Hit 180 g protein anyway", systemImage: "fork.knife")
                Label("Walk 20–30 min, light stretching", systemImage: "figure.walk")
                Label("Take creatine (streak counts today too)", systemImage: "pills.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .cardStyle(padding: 20)
    }
}

/// Today's session is already done.
private struct CompletedCard: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("SESSION DONE")
                    .font(.display(24))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(session.sets.count) sets · \(Fmt.volume(session.totalVolume)) kg · \(Fmt.duration((session.finishedAt ?? .now).timeIntervalSince(session.startedAt)))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .cardStyle()
    }
}

/// Shown when a JSON data file has a mistake, so you know exactly what to fix.
struct DataErrorBanner: View {
    let errors: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("DATA FILE PROBLEM", systemImage: "exclamationmark.triangle.fill")
                .font(.display(20))
                .foregroundStyle(Theme.accent)
            ForEach(errors, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.textSecondary) }
        }
        .cardStyle()
    }
}
