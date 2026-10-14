import SwiftData
import SwiftUI

/// The dashboard: greeting, today's workout, activity, water and a simple daily checklist.
struct HomeView: View {
    private let catalog = Catalog.shared
    private let todayWeekday = Calendar.current.component(.weekday, from: .now)

    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \FoodEntry.date, order: .reverse) private var food: [FoodEntry]
    @Query(sort: \SupplementCheck.takenAt, order: .reverse) private var checks: [SupplementCheck]
    @AppStorage(ProfileKey.name) private var name = ProfileDefault.name
    @AppStorage(ProfileKey.proteinTarget) private var proteinTarget = ProfileDefault.protein

    @State private var selectedWeekday = Calendar.current.component(.weekday, from: .now)
    @State private var showSettings = false
    @State private var showExercises = true
    @State private var activeSession: WorkoutSession?
    private var health = HealthData.shared

    private var day: SplitDay? { catalog.splitDay(weekday: selectedWeekday) }
    private var openSession: WorkoutSession? { sessions.first { !$0.isFinished } }
    private var doneToday: WorkoutSession? {
        sessions.first { $0.isFinished && $0.splitWeekday == selectedWeekday && $0.startedAt >= Date.now.startOfDay }
    }
    private var todaysFood: [FoodEntry] { food.filter { $0.date >= Date.now.startOfDay } }
    private var streak: Int { TrainingStats.streak(sessions, extraDays: health.workoutDays) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !catalog.loadErrors.isEmpty { DataErrorBanner(errors: catalog.loadErrors) }

                    header.revealOnAppear()

                    if let open = openSession {
                        resumeCard(open)
                    }

                    Group {
                        if let day, !day.isRest {
                            workoutHero(day)
                        } else {
                            restHero
                            WeeklySummaryCard(sessions: sessions)
                        }
                    }
                    .revealOnAppear(delay: 0.06)

                    ActivityCard().revealOnAppear(delay: 0.12)
                    WaterCard().revealOnAppear(delay: 0.18)
                    checklist.revealOnAppear(delay: 0.24)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .refreshable { await health.refresh() }
            .task { await health.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
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

    // MARK: Header

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: return "Good morning"
        case ..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(greeting), \(name)".uppercased())
                    .font(.display(17))
                    .tracking(2)
                    .foregroundStyle(Theme.ember)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased())
                    .font(.display(36))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if streak > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                    Text("\(streak) DAY\(streak == 1 ? "" : "S")")
                }
                .font(.display(17))
                .foregroundStyle(Theme.ember)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.accent.opacity(0.15), in: Capsule())
                .accessibilityLabel("\(streak) day streak")
            }
        }
        .padding(.top, 4)
    }

    // MARK: Workout hero

    private func heroImage(_ day: SplitDay) -> UIImage? {
        for item in day.items {
            guard let ex = catalog.exercise(item.exercise) else { continue }
            if let img = BundledImage.load("muscles_\(ex.id)_\(ex.preferredSide.rawValue)") { return img }
        }
        return nil
    }

    private func workoutHero(_ day: SplitDay) -> some View {
        let items = day.items.compactMap { item in catalog.exercise(item.exercise).map { (item, $0) } }
        let sets = items.reduce(0) { $0 + RepScheme($1.0.scheme).setCount }
        let cardio = items.filter { $0.1.logType == .minutes }.reduce(0) { $0 + (RepScheme($1.0.scheme).sets.first?.high ?? 0) }
        let minutes = sets * 2 + cardio + 5

        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let img = heroImage(day) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 220, height: 250)
                        .clipped()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedWeekday == todayWeekday ? "TODAY'S WORKOUT" : "\(Catalog.weekdayNames[selectedWeekday - 1].uppercased())'S WORKOUT")
                        .font(.display(16)).tracking(2).foregroundStyle(Theme.ember)
                    Text(day.name.uppercased().replacingOccurrences(of: " & ", with: "\n& "))
                        .font(.display(46))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 200, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        InfoPill(icon: "clock", text: "~\(minutes) min")
                        InfoPill(icon: "list.bullet", text: "\(items.count) exercises · \(sets) sets")
                    }
                }
                .padding(18)
            }
            .frame(height: 250)

            VStack(spacing: 10) {
                if let done = doneToday {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(Theme.ember)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("SESSION COMPLETE").font(.display(22)).foregroundStyle(Theme.textPrimary)
                            Text("\(done.sets.count) sets · \(Fmt.volume(done.totalVolume)) kg moved")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                } else if openSession == nil {
                    Button {
                        start(day, guided: false)
                    } label: {
                        Label("Start workout", systemImage: "play.fill")
                    }
                    .buttonStyle(.primary)
                    Button {
                        start(day, guided: true)
                    } label: {
                        Label("Guided mode · one exercise at a time", systemImage: "figure.strengthtraining.traditional")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ember)
                }

                HStack {
                    Button {
                        withAnimation(.snappy) { showExercises.toggle() }
                    } label: {
                        Label(showExercises ? "Hide exercises" : "See exercises", systemImage: showExercises ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Menu {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                            Button {
                                selectedWeekday = wd
                                Haptics.select()
                            } label: {
                                let d = catalog.splitDay(weekday: wd)
                                Text("\(Catalog.weekdayNames[wd - 1]) · \(d?.name ?? "—")")
                            }
                        }
                    } label: {
                        Label("Change day", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 32)

                if showExercises {
                    VStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, pair in
                            NavigationLink(value: pair.1) {
                                HStack(spacing: 12) {
                                    Text(String(format: "%02d", index + 1))
                                        .font(.display(20)).foregroundStyle(Theme.ember).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(pair.1.name.uppercased()).font(.display(18)).foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1).minimumScaleFactor(0.7)
                                        Text(RepScheme(pair.0.scheme).summary(for: pair.1))
                                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textFaint)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var restHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECOVERY DAY").font(.display(16)).tracking(2).foregroundStyle(Theme.ember)
            Text("REST. EAT. GROW.").font(.display(44)).foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 8) {
                Label("Sleep 7–9 hours", systemImage: "moon.zzz.fill")
                Label("Still hit your protein target", systemImage: "fork.knife")
                Label("Easy 20–30 min walk", systemImage: "figure.walk")
                Label("Take creatine, it counts today too", systemImage: "pills.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            Menu {
                ForEach([2, 3, 4, 5, 6, 7], id: \.self) { wd in
                    Button("\(Catalog.weekdayNames[wd - 1]) · \(catalog.splitDay(weekday: wd)?.name ?? "")") {
                        selectedWeekday = wd
                    }
                }
            } label: {
                Label("Train anyway: pick a day", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ember)
            }
            .padding(.top, 4)
        }
        .heroCardStyle()
    }

    private func resumeCard(_ open: WorkoutSession) -> some View {
        Button {
            Haptics.thud()
            activeSession = open
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("WORKOUT IN PROGRESS").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(.white.opacity(0.8))
                    Text("RESUME \(open.dayName.uppercased())").font(.display(22)).foregroundStyle(.white)
                }
                Spacer()
                Text(open.startedAt, style: .timer).font(.display(20)).foregroundStyle(.white).monospacedDigit()
            }
            .padding(16)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.accentGlow, radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Checklist

    private var checklist: some View {
        let protein = todaysFood.reduce(0) { $0 + $1.protein }
        let creatineTaken = checks.contains { $0.dayKey == Date.now.dayKey && $0.supplementId == "creatine" }
        let workoutDone = doneToday != nil || !health.todaysWorkouts.filter { !$0.isCardio }.isEmpty
        let isRest = day?.isRest ?? true

        return VStack(alignment: .leading, spacing: 10) {
            Text("TODAY'S CHECKLIST").font(.display(18)).tracking(1.5).foregroundStyle(Theme.textSecondary)
            VStack(spacing: 0) {
                ForEach(FoodDatabase.shared.plan) { meal in
                    let logged = todaysFood.contains { $0.meal == meal.name }
                    checkRow(done: logged, title: meal.name, subtitle: meal.time,
                             trailing: "\(Int(FoodDatabase.shared.macros(of: meal).kcal)) kcal") {
                        if logged {
                            for e in todaysFood where e.meal == meal.name { context.delete(e) }
                            try? context.save()
                        } else {
                            FoodLogStore.logPlanMeal(meal, context: context)
                        }
                    }
                    Divider().overlay(Theme.stroke)
                }
                if !isRest {
                    checkRow(done: workoutDone, title: "Workout", subtitle: day?.name ?? "",
                             trailing: workoutDone ? "Done" : "Next", action: nil)
                    Divider().overlay(Theme.stroke)
                }
                checkRow(done: protein >= proteinTarget, title: "Hit \(Int(proteinTarget)) g protein",
                         subtitle: "\(Int(protein)) g so far", trailing: "\(Int(min(protein / max(proteinTarget, 1), 1) * 100))%",
                         action: nil)
                Divider().overlay(Theme.stroke)
                checkRow(done: creatineTaken, title: "Creatine 5 g", subtitle: "Any time", trailing: creatineTaken ? "Taken" : "Tap") {
                    if creatineTaken {
                        for c in checks where c.dayKey == Date.now.dayKey && c.supplementId == "creatine" { context.delete(c) }
                    } else {
                        context.insert(SupplementCheck(dayKey: Date.now.dayKey, supplementId: "creatine"))
                    }
                    try? context.save()
                }
            }
            .padding(.horizontal, 14)
            .cardStyle(padding: 0)
        }
    }

    private func checkRow(done: Bool, title: String, subtitle: String, trailing: String, action: (() -> Void)?) -> some View {
        Button {
            guard let action else { return }
            Haptics.success()
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(done ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(done ? Color.clear : Theme.stroke, lineWidth: 2)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textFaint)
                }
                Spacer()
                Text(trailing.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(!done && trailing == "Next" ? Theme.ember : Theme.textFaint)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func start(_ day: SplitDay, guided: Bool) {
        Haptics.thud()
        UserDefaults.standard.set(!guided, forKey: "workout.listMode")
        let session = WorkoutSession(dayName: day.name, splitWeekday: selectedWeekday)
        context.insert(session)
        try? context.save()
        activeSession = session
        Task { await NotificationManager.shared.requestPermission() }
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
