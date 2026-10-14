import SwiftData
import SwiftUI

/// One exercise at a time, built for people who don't know what to do next.
struct GuidedWorkoutView: View {
    let model: ActiveWorkoutModel
    let onInfo: (ExerciseDef) -> Void
    let onAddExercise: () -> Void
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(ProfileKey.restSeconds) private var restSeconds = ProfileDefault.restSeconds
    private var restTimer = RestTimer.shared
    private var health = HealthData.shared

    init(model: ActiveWorkoutModel, onInfo: @escaping (ExerciseDef) -> Void,
         onAddExercise: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.model = model
        self.onInfo = onInfo
        self.onAddExercise = onAddExercise
        self.onFinish = onFinish
    }

    private var index: Int {
        if let e = model.expandedBlock, model.blocks.indices.contains(e) { return e }
        return model.blocks.firstIndex { !$0.isComplete } ?? max(model.blocks.count - 1, 0)
    }

    var body: some View {
        ZStack {
            if model.blocks.isEmpty {
                EmptyStateCard(icon: "dumbbell", title: "No exercises", message: "Add an exercise to get started.")
                    .padding()
            } else {
                content(block: index)
            }
            if restTimer.isRunning {
                RestScreen(nextUp: restTimer.nextUp)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: restTimer.isRunning)
    }

    private func content(block b: Int) -> some View {
        let block = model.blocks[b]
        let ex = block.exercise
        let setIndex = block.sets.firstIndex { !$0.isDone } ?? max(block.sets.count - 1, 0)
        let allDone = model.doneSets == model.totalSets

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Progress
                HStack(spacing: 10) {
                    GradientBar(progress: Double(model.doneSets) / Double(max(model.totalSets, 1)), height: 6)
                    Text("\(b + 1) / \(model.blocks.count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }

                // Media: big 3D muscle model + medium form demo
                GuidedMediaView(exercise: ex, onInfo: { onInfo(ex) })
                    .id(ex.id)

                // Title
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXERCISE \(b + 1) · WORKS \(Catalog.shared.muscleNames(ex.primary).joined(separator: ", ").uppercased())")
                        .font(.display(16)).tracking(1.5).foregroundStyle(Theme.ember)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(ex.name.uppercased())
                        .font(.display(36)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.6)
                }

                // Coach tip
                if let tip = ex.cues?.first ?? ex.instructions?.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("COACH TIP", systemImage: "lightbulb.fill")
                            .font(.system(size: 12, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.ember)
                        Text(tip).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Full how-to and common mistakes") { onInfo(ex) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(0.25)))
                }

                // Set header
                HStack(alignment: .firstTextBaseline) {
                    Text(block.isComplete ? "ALL SETS DONE" : "SET \(setIndex + 1) OF \(block.sets.count)")
                        .font(.display(26)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let t = block.sets[setIndex].target {
                        Text(aimText(t, ex)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    HelpButton(term: "set")
                }

                // Big inputs
                if !block.isComplete {
                    inputs(block: b, set: setIndex, exercise: ex)
                    hint(for: ex)
                    healthImport(block: b, set: setIndex, exercise: ex)
                } else {
                    doneSets(block)
                }

                // Main action
                if allDone {
                    Button { onFinish() } label: { Label("Finish workout", systemImage: "flag.checkered") }
                        .buttonStyle(.primary)
                } else if block.isComplete {
                    Button {
                        Haptics.tap()
                        model.expandedBlock = model.blocks.firstIndex { !$0.isComplete }
                    } label: { Label("Next exercise", systemImage: "arrow.right") }
                    .buttonStyle(.primary)
                } else {
                    let lastSetOverall = model.totalSets - model.doneSets == 1
                    Button {
                        withAnimation(.snappy) { model.complete(block: b, set: setIndex) }
                    } label: {
                        Label(lastSetOverall || ex.logType == .minutes ? "Done" : "Done · start \(restSeconds)s rest",
                              systemImage: "checkmark")
                    }
                    .buttonStyle(.primary)
                }

                // Navigation
                HStack {
                    Button {
                        Haptics.select()
                        model.expandedBlock = max(b - 1, 0)
                    } label: { Label("Previous", systemImage: "chevron.left") }
                    .disabled(b == 0)
                    Spacer()
                    Button { onAddExercise() } label: { Label("Add", systemImage: "plus") }
                    Spacer()
                    Button {
                        Haptics.select()
                        model.expandedBlock = min(b + 1, model.blocks.count - 1)
                    } label: { Label("Skip", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle()) }
                    .disabled(b >= model.blocks.count - 1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
    }

    private func aimText(_ t: RepTarget, _ ex: ExerciseDef) -> String {
        switch ex.logType {
        case .seconds: return "Hold \(Fmt.clock(t.high))"
        case .minutes: return "Aim for \(t.text) min"
        default: return "Aim for \(t.text) \(ex.unitLabel)"
        }
    }

    @ViewBuilder
    private func inputs(block b: Int, set s: Int, exercise ex: ExerciseDef) -> some View {
        let draft = model.blocks[b].sets[s]
        let last = model.blocks[b].lastTime
        switch ex.logType {
        case .weightReps:
            HStack(spacing: 10) {
                BigStepper(title: ex.equipment == "dumbbell" ? "Weight (each hand)" : "Weight",
                           value: Fmt.weight(draft.weightKg), unit: "kg", footnote: last.map { "Last: \($0)" },
                           onMinus: { model.blocks[b].sets[s].weightKg = max(draft.weightKg - (ex.weightStep ?? 2.5), 0) },
                           onPlus: { model.blocks[b].sets[s].weightKg = draft.weightKg + (ex.weightStep ?? 2.5) },
                           onSet: { model.blocks[b].sets[s].weightKg = ($0 * 4).rounded() / 4 })
                BigStepper(title: "Reps", value: "\(draft.reps)", unit: nil, footnote: nil,
                           onMinus: { model.blocks[b].sets[s].reps = max(draft.reps - 1, 0) },
                           onPlus: { model.blocks[b].sets[s].reps = draft.reps + 1 },
                           onSet: { model.blocks[b].sets[s].reps = Int($0) })
            }
        case .reps:
            BigStepper(title: (ex.repUnit ?? "reps").capitalized, value: "\(draft.reps)", unit: nil, footnote: last.map { "Last: \($0)" },
                       onMinus: { model.blocks[b].sets[s].reps = max(draft.reps - 1, 0) },
                       onPlus: { model.blocks[b].sets[s].reps = draft.reps + 1 },
                       onSet: { model.blocks[b].sets[s].reps = Int($0) })
        case .seconds:
            BigStepper(title: "Hold time", value: Fmt.clock(draft.seconds), unit: nil, footnote: last.map { "Last: \($0)" },
                       onMinus: { model.blocks[b].sets[s].seconds = max(draft.seconds - 5, 0) },
                       onPlus: { model.blocks[b].sets[s].seconds = draft.seconds + 5 },
                       onSet: { model.blocks[b].sets[s].seconds = Int($0) })
        case .minutes:
            BigStepper(title: "Minutes", value: "\(draft.seconds / 60)", unit: "min", footnote: last.map { "Last: \($0)" },
                       onMinus: { model.blocks[b].sets[s].seconds = max(draft.seconds - 60, 0) },
                       onPlus: { model.blocks[b].sets[s].seconds = draft.seconds + 60 },
                       onSet: { model.blocks[b].sets[s].seconds = Int($0) * 60 })
        }
    }

    @ViewBuilder
    private func hint(for ex: ExerciseDef) -> some View {
        if ex.logType == .weightReps {
            VStack(alignment: .leading, spacing: 4) {
                Label("Felt easy with 3+ reps left? Add \(Fmt.weight(ex.weightStep ?? 2.5)) kg next set.",
                      systemImage: "arrow.up.circle.fill")
                Label("Form breaking down? Drop the weight, it's not a failure.", systemImage: "arrow.down.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    /// For cardio: use a workout already recorded by Apple Watch / Fitness.
    @ViewBuilder
    private func healthImport(block b: Int, set s: Int, exercise ex: ExerciseDef) -> some View {
        if ex.logType == .minutes, let w = health.todaysWorkouts.first(where: \.isCardio) {
            Button {
                model.blocks[b].sets[s].seconds = w.minutes * 60
                Haptics.success()
            } label: {
                Label("Use \(w.name) from \(w.source): \(w.minutes) min", systemImage: "applewatch")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ember)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func doneSets(_ block: ExerciseBlock) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(block.sets.enumerated()), id: \.offset) { i, s in
                HStack {
                    Text("SET \(i + 1)").font(.display(18)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(Fmt.set(weightKg: s.weightKg, reps: s.reps, seconds: s.seconds, exercise: block.exercise))
                        .font(.display(20)).foregroundStyle(Theme.textPrimary)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ember)
                }
            }
        }
        .cardStyle(padding: 14)
    }
}

/// Big value with chunky −/+ buttons (hold to repeat).
struct BigStepper: View {
    let title: String
    let value: String
    let unit: String?
    let footnote: String?
    let onMinus: () -> Void
    let onPlus: () -> Void
    /// Called with a typed value when you tap the number and enter it.
    var onSet: ((Double) -> Void)? = nil

    @State private var typing = false
    @State private var entry = ""

    var body: some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Theme.textFaint)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                button("minus", onMinus)
                Button {
                    guard onSet != nil else { return }
                    entry = ""
                    typing = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value).font(.display(44)).foregroundStyle(Theme.textPrimary)
                            .monospacedDigit().contentTransition(.numericText())
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if let unit { Text(unit.uppercased()).font(.display(15)).foregroundStyle(Theme.textSecondary) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(onSet != nil ? "Double-tap to type a value" : "")
                button("plus", onPlus)
            }
            if let footnote {
                Text(footnote).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            if onSet != nil {
                Text("TAP NUMBER TO TYPE").font(.system(size: 8, weight: .bold)).tracking(0.5).foregroundStyle(Theme.textFaint)
            }
        }
        .cardStyle(padding: 10)
        .alert(title, isPresented: $typing) {
            TextField(value, text: $entry).keyboardType(.decimalPad)
            Button("Set") {
                if let v = Double(entry.replacingOccurrences(of: ",", with: ".")), v >= 0 {
                    Haptics.tap()
                    onSet?(v)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(unit.map { "Enter \($0)" } ?? "Enter a number")
        }
    }

    private func button(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 52)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }
}

/// Full-screen rest countdown with a quick water button.
struct RestScreen: View {
    let nextUp: String
    var timer = RestTimer.shared
    @Environment(\.modelContext) private var context

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let end = timer.endDate ?? .now
            let remaining = max(end.timeIntervalSince(ctx.date), 0)
            let progress = timer.totalSeconds > 0 ? remaining / Double(timer.totalSeconds) : 0
            VStack(spacing: 22) {
                Spacer()
                Text("REST").font(.display(22)).tracking(4).foregroundStyle(Theme.ember)
                ZStack {
                    Circle().stroke(Theme.cardRaised, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(Fmt.clock(Int(remaining.rounded(.up))))
                        .font(.display(84)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                }
                .frame(width: 240, height: 240)

                HStack(spacing: 12) {
                    restButton("−15 s") { timer.adjust(by: -15) }
                    restButton("+15 s") { timer.adjust(by: 15) }
                    restButton("+250 ML", icon: "drop.fill") { WaterService.log(ml: 250, context: context) }
                }
                if !nextUp.isEmpty {
                    VStack(spacing: 2) {
                        Text("UP NEXT").font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(Theme.textFaint)
                        Text(nextUp.uppercased()).font(.display(22)).foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                }
                Text("Breathe slowly. Shake out your arms. Sip water.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    Haptics.tap()
                    timer.skip()
                } label: { Label("Skip rest", systemImage: "forward.fill") }
                .buttonStyle(.secondary)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.opacity(0.97).ignoresSafeArea())
        }
    }

    private func restButton(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)) }
                Text(title).font(.display(18))
            }
            .frame(minWidth: 86, minHeight: 48)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
    }
}

/// Puts the icon after the text ("Skip >").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - Media

/// Large rotatable 3D body with the worked muscles lit, plus a medium form-demo window in the corner.
struct GuidedMediaView: View {
    let exercise: ExerciseDef
    let onInfo: () -> Void
    @State private var bodyView: BodyView
    @State private var token = 0
    @State private var loaded = false

    init(exercise: ExerciseDef, onInfo: @escaping () -> Void) {
        self.exercise = exercise
        self.onInfo = onInfo
        _bodyView = State(initialValue: exercise.preferredSide == .back ? .back : .front)
    }

    private var hasModel: Bool { Bundle.main.url(forResource: "MuscleBody", withExtension: "usdz") != nil }

    var body: some View {
        ZStack {
            if hasModel {
                Muscle3DView(primary: exercise.primary, secondary: exercise.secondary,
                             view: bodyView, viewToken: token, loaded: $loaded)
                if !loaded { ProgressView().tint(Theme.accent) }
            } else if let image = BundledImage.load("muscles_\(exercise.id)_\(exercise.preferredSide.rawValue)") {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            if hasModel {
                HStack(spacing: 4) {
                    ForEach(BodyView.allCases) { v in
                        Button {
                            Haptics.select()
                            bodyView = v
                            token += 1
                        } label: {
                            Text(v.rawValue.uppercased())
                                .font(.display(15)).tracking(1)
                                .padding(.horizontal, 10).frame(minHeight: 32)
                                .foregroundStyle(bodyView == v ? Color.white : Theme.textSecondary)
                                .background(bodyView == v ? Theme.accent : Color.black.opacity(0.55),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onInfo) {
                Image(systemName: "info")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Exercise details")
        }
        .overlay(alignment: .bottomTrailing) {
            if BundledImage.load("form_\(exercise.id)_0") != nil {
            FormDemoView(exercise: exercise)
                .frame(width: 170)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                .padding(10)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}
