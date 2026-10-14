import SwiftUI
import WatchKit

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            if let plan = store.plan {
                if plan.isRestDay && !plan.inProgress {
                    MessageView(icon: "bed.double.fill", title: "REST DAY", text: "Recover well. See you tomorrow.")
                } else if plan.inProgress {
                    WorkoutPager()
                } else {
                    StartView(plan: plan)
                }
            } else {
                MessageView(icon: "iphone", title: "OPEN IRON LOG",
                            text: "Open the app on your iPhone once to send today's workout here.")
                    .onAppear { store.requestPlan() }
            }
        }
    }
}

struct MessageView: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30, weight: .bold)).foregroundStyle(WatchTheme.accent)
            Text(title).font(.heavy(20))
            Text(text).font(.footnote).foregroundStyle(WatchTheme.faint).multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Start

struct StartView: View {
    let plan: WatchPlan
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY").font(.heavy(12)).foregroundStyle(WatchTheme.ember)
                Text(plan.dayName.uppercased()).font(.heavy(24)).lineLimit(2).minimumScaleFactor(0.6)
                Text("\(plan.exercises.count) exercises · \(plan.totalSets) sets")
                    .font(.footnote).foregroundStyle(WatchTheme.faint)

                Button {
                    WKInterfaceDevice.current().play(.start)
                    store.start()
                    Task { await workout.start() }
                } label: {
                    Label("START", systemImage: "play.fill").font(.heavy(18)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
                .padding(.vertical, 4)

                ForEach(Array(plan.exercises.enumerated()), id: \.offset) { i, ex in
                    HStack(spacing: 6) {
                        Text("\(i + 1)").font(.heavy(13)).foregroundStyle(WatchTheme.ember).frame(width: 16)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(ex.name).font(.footnote.weight(.semibold)).lineLimit(2)
                            Text("\(ex.sets.count) sets · \(ex.sets.first?.target ?? "")")
                                .font(.caption2).foregroundStyle(WatchTheme.faint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Iron Log")
    }
}

// MARK: - Workout

struct WorkoutPager: View {
    @Environment(WatchStore.self) private var store
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            ControlsView().tag(0)
            Group {
                if store.isResting { RestView() } else { SetView() }
            }
            .tag(1)
            MetricsView().tag(2)
            ExerciseListView(page: $page).tag(3)
        }
        .tabViewStyle(.verticalPage)
    }
}

struct SetView: View {
    @Environment(WatchStore.self) private var store
    @State private var weight: Double = 0
    @State private var reps: Int = 10
    @State private var seconds: Int = 60

    private struct Pos: Equatable { let e: Int; let s: Int }

    private var position: Pos? {
        guard let plan = store.plan, let e = store.currentExerciseIndex,
              let s = plan.exercises[e].sets.firstIndex(where: { !$0.done }) else { return nil }
        return Pos(e: e, s: s)
    }

    var body: some View {
        if let pos = position, let plan = store.plan {
            let ex = plan.exercises[pos.e]
            let set = ex.sets[pos.s]
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXERCISE \(pos.e + 1)/\(plan.exercises.count) · SET \(pos.s + 1)/\(ex.sets.count)")
                        .font(.heavy(11)).foregroundStyle(WatchTheme.ember)
                    Text(ex.name.uppercased()).font(.heavy(18)).lineLimit(2).minimumScaleFactor(0.6)
                    if !set.target.isEmpty {
                        Text("Target \(set.target) \(unit(ex))").font(.caption2).foregroundStyle(WatchTheme.faint)
                    }

                    switch ex.logType {
                    case "weightReps":
                        weightField(step: ex.weightStep)
                        repsField
                    case "reps":
                        repsField
                    case "minutes":
                        stepper(title: "MIN", value: "\(seconds / 60)",
                                minus: { seconds = max(60, seconds - 60) }, plus: { seconds += 60 })
                    default:
                        stepper(title: "SEC", value: "\(seconds)",
                                minus: { seconds = max(5, seconds - 5) }, plus: { seconds += 5 })
                    }

                    Button {
                        store.logSet(exercise: pos.e, set: pos.s, weightKg: weight, reps: reps, seconds: seconds)
                    } label: {
                        Label("DONE", systemImage: "checkmark").font(.heavy(18)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.accent)
                    .padding(.top, 4)
                }
            }
            .task(id: pos.e * 1000 + pos.s) {
                weight = set.weightKg
                reps = set.reps
                seconds = max(set.seconds, 5)
            }
        } else {
            AllDoneView()
        }
    }

    private func unit(_ ex: WatchExercise) -> String {
        switch ex.logType {
        case "seconds": return "sec"
        case "minutes": return "min"
        default: return "reps"
        }
    }

    private func weightField(step: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(weight.formatted(.number.precision(.fractionLength(0...1))))
                .font(.heavy(36)).monospacedDigit()
                .contentTransition(.numericText())
            Text("KG").font(.heavy(13)).foregroundStyle(WatchTheme.faint)
            Spacer()
            Image(systemName: "digitalcrown.horizontal.arrow.clockwise.fill")
                .font(.caption).foregroundStyle(WatchTheme.faint)
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .focusable()
        .digitalCrownRotation($weight, from: 0, through: 400, by: step, sensitivity: .low,
                              isContinuous: false, isHapticFeedbackEnabled: true)
    }

    private var repsField: some View {
        stepper(title: "REPS", value: "\(reps)", minus: { reps = max(0, reps - 1) }, plus: { reps += 1 })
    }

    private func stepper(title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: minus) { Image(systemName: "minus").font(.heavy(16)) }
                .buttonStyle(.bordered).frame(width: 44)
            VStack(spacing: 0) {
                Text(value).font(.heavy(26)).monospacedDigit()
                Text(title).font(.heavy(10)).foregroundStyle(WatchTheme.faint)
            }
            .frame(maxWidth: .infinity)
            Button(action: plus) { Image(systemName: "plus").font(.heavy(16)) }
                .buttonStyle(.bordered).frame(width: 44)
        }
    }
}

struct RestView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        VStack(spacing: 6) {
            Text("REST").font(.heavy(14)).foregroundStyle(WatchTheme.ember)
            if let end = store.restEndsAt {
                Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                    .font(.heavy(48)).monospacedDigit()
            }
            if let plan = store.plan, let e = store.currentExerciseIndex {
                let ex = plan.exercises[e]
                let s = (ex.sets.firstIndex { !$0.done } ?? 0) + 1
                Text("NEXT: \(ex.name) · set \(s)").font(.caption2).foregroundStyle(WatchTheme.faint)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            HStack {
                Button("+30s") { store.addRest(30) }.buttonStyle(.bordered)
                Button("Skip") { store.skipRest() }.buttonStyle(.borderedProminent).tint(WatchTheme.accent)
            }
        }
    }
}

struct AllDoneView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill").font(.system(size: 28)).foregroundStyle(WatchTheme.ember)
            Text("ALL SETS DONE").font(.heavy(20))
            Button {
                store.finish()
                Task { await workout.end() }
            } label: {
                Text("FINISH").font(.heavy(18)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.accent)
        }
    }
}

struct MetricsView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let start = workout.startDate ?? store.plan?.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.heavy(34)).monospacedDigit().foregroundStyle(WatchTheme.ember)
            }
            Label("\(Int(workout.heartRate)) BPM", systemImage: "heart.fill")
                .font(.heavy(20)).foregroundStyle(.white)
            Label("\(Int(workout.activeKcal)) KCAL", systemImage: "flame.fill")
                .font(.heavy(20)).foregroundStyle(.white)
            if let plan = store.plan {
                Text("\(plan.doneSets)/\(plan.totalSets) sets done").font(.footnote).foregroundStyle(WatchTheme.faint)
                ProgressView(value: Double(plan.doneSets), total: Double(max(plan.totalSets, 1)))
                    .tint(WatchTheme.accent)
            }
            if !workout.isRunning {
                Button("Track heart rate") { Task { await workout.start() } }
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExerciseListView: View {
    @Binding var page: Int
    @Environment(WatchStore.self) private var store

    var body: some View {
        List {
            if let plan = store.plan {
                ForEach(Array(plan.exercises.enumerated()), id: \.offset) { i, ex in
                    let done = ex.sets.filter(\.done).count
                    Button {
                        store.focusIndex = i
                        page = 1
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ex.name).font(.footnote.weight(.semibold)).lineLimit(2)
                                Text("\(done)/\(ex.sets.count) sets").font(.caption2).foregroundStyle(WatchTheme.faint)
                            }
                            Spacer()
                            if done == ex.sets.count {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(WatchTheme.accent)
                            } else if i == store.currentExerciseIndex {
                                Image(systemName: "arrow.right.circle.fill").foregroundStyle(WatchTheme.ember)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ControlsView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                confirm = true
            } label: {
                Label("END WORKOUT", systemImage: "xmark").font(.heavy(16)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.accent)
            Text("Saves your sets on the iPhone and the workout to Apple Health.")
                .font(.caption2).foregroundStyle(WatchTheme.faint).multilineTextAlignment(.center)
        }
        .confirmationDialog("End this workout?", isPresented: $confirm) {
            Button("End workout", role: .destructive) {
                store.finish()
                Task { await workout.end() }
            }
        }
    }
}
