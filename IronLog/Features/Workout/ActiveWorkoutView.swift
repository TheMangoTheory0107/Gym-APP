import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    @State private var model: ActiveWorkoutModel
    @State private var detailExercise: ExerciseDef?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var summary: WorkoutSummary?
    @State private var showPicker = false
    @AppStorage("workout.listMode") private var listMode = false

    private var restTimer = RestTimer.shared

    init(session: WorkoutSession, context: ModelContext) {
        _model = State(initialValue: ActiveWorkoutModel(session: session, context: context))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    WorkoutSummaryView(summary: summary) { dismiss() }
                } else {
                    workout
                }
            }
            .screenBackground()
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { restTimer.refresh() }
        }
    }

    private var workout: some View {
        Group {
            if listMode {
                listView
            } else {
                GuidedWorkoutView(model: model,
                                  onInfo: { detailExercise = $0 },
                                  onAddExercise: { showPicker = true },
                                  onFinish: { finish() })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Minimise workout")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(model.session.dayName.uppercased())
                        .font(.display(20))
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.session.startedAt, style: .timer)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(listMode ? "Guided mode (one at a time)" : "List mode (all exercises)",
                           systemImage: listMode ? "rectangle.portrait" : "list.bullet") {
                        withAnimation(.snappy) { listMode.toggle() }
                    }
                    Button("Add exercise", systemImage: "plus") { showPicker = true }
                    Button("Finish workout", systemImage: "flag.checkered") { confirmFinish = true }
                    Button("Discard workout", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet { ex in withAnimation(.snappy) { model.addExercise(ex) } }
        }
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailView(exercise: ex)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                detailExercise = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("Close")
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(finishMessage, isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish") { finish() }
            Button("Keep going", role: .cancel) {}
        }
        .confirmationDialog("Discard this workout? Logged sets will be deleted.", isPresented: $confirmDiscard,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                model.discard()
                dismiss()
            }
        }
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    ForEach($model.blocks) { $block in
                        ExerciseBlockCard(
                            block: $block,
                            number: block.id + 1,
                            isExpanded: model.expandedBlock == block.id,
                            onToggle: {
                                Haptics.select()
                                withAnimation(.snappy) {
                                    model.expandedBlock = model.expandedBlock == block.id ? nil : block.id
                                }
                            },
                            onInfo: { detailExercise = block.exercise },
                            onComplete: { s in withAnimation(.snappy) { model.complete(block: block.id, set: s) } },
                            onUndo: { s in withAnimation(.snappy) { model.undo(block: block.id, set: s) } },
                            onAddSet: { withAnimation(.snappy) { model.addSet(block: block.id) } }
                        )
                        .id(block.id)
                    }

                    Button {
                        Haptics.tap()
                        showPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    .buttonStyle(.secondary)
                    .padding(.top, 4)

                    Button("Finish workout") { confirmFinish = true }
                        .buttonStyle(.primary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .onChange(of: model.expandedBlock) { _, new in
                guard let new else { return }
                withAnimation(.snappy) { proxy.scrollTo(new, anchor: .top) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RestTimerBar()
                .animation(.snappy, value: restTimer.isRunning)
        }
    }

    private var finishMessage: String {
        let left = model.totalSets - model.doneSets
        return left > 0 ? "\(left) sets not done. Finish anyway?" : "Finish workout?"
    }

    private func finish() {
        model.finish()
        withAnimation(.snappy) {
            summary = WorkoutStats.summary(for: model.session, context: context)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.session.startedAt, style: .timer)
                    .font(.display(34))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text("ELAPSED")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatTile(label: "Sets", value: "\(model.doneSets)/\(model.totalSets)")
            StatTile(label: "Volume", value: Fmt.volume(model.volume), unit: "kg", highlight: true)
        }
        .cardStyle()
        .padding(.top, 6)
    }
}

// MARK: - Exercise card

private struct ExerciseBlockCard: View {
    @Binding var block: ExerciseBlock
    let number: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onInfo: () -> Void
    let onComplete: (Int) -> Void
    let onUndo: (Int) -> Void
    let onAddSet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) { headerRow }
                .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(block.sets.indices, id: \.self) { i in
                        SetRow(index: i, draft: $block.sets[i], exercise: block.exercise,
                               onComplete: { onComplete(i) }, onUndo: { onUndo(i) })
                    }
                }
                Button(action: onAddSet) {
                    Label("Add set", systemImage: "plus")
                        .font(.display(18))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle(padding: 14, raised: isExpanded)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isExpanded ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5)
        )
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                if block.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: Circle())
                } else {
                    Text(String(format: "%02d", number))
                        .font(.display(26))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(block.exercise.name.uppercased())
                    .font(.display(21, relativeTo: .headline))
                    .foregroundStyle(block.isComplete ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    Text(RepScheme(block.item.scheme).summary(for: block.exercise))
                        .foregroundStyle(Theme.textSecondary)
                    if let last = block.lastTime {
                        Text("Last: \(last)")
                            .foregroundStyle(Theme.accent.opacity(0.9))
                    }
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Text("\(block.doneCount)/\(block.sets.count)")
                .font(.display(18))
                .foregroundStyle(Theme.textFaint)
                .monospacedDigit()

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Form and muscles")
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Set row

private struct SetRow: View {
    let index: Int
    @Binding var draft: SetDraft
    let exercise: ExerciseDef
    let onComplete: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: 0) {
                Text("\(index + 1)")
                    .font(.display(22))
                    .foregroundStyle(draft.isDone ? Theme.accent : Theme.textPrimary)
                if let t = draft.target {
                    Text(targetText(t))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 30)

            switch exercise.logType {
            case .weightReps:
                MiniStepper(label: "KG", text: Fmt.weight(draft.weightKg), width: 50, disabled: draft.isDone,
                            onMinus: { draft.weightKg = max(draft.weightKg - step, 0) },
                            onPlus: { draft.weightKg += step },
                            onSet: { draft.weightKg = ($0 * 4).rounded() / 4 })
                MiniStepper(label: "REPS", text: "\(draft.reps)", width: 32, disabled: draft.isDone,
                            onMinus: { draft.reps = max(draft.reps - 1, 0) },
                            onPlus: { draft.reps += 1 },
                            onSet: { draft.reps = Int($0) })
            case .reps:
                MiniStepper(label: (exercise.repUnit ?? "reps").uppercased(), text: "\(draft.reps)", width: 120,
                            disabled: draft.isDone,
                            onMinus: { draft.reps = max(draft.reps - 1, 0) },
                            onPlus: { draft.reps += 1 })
            case .seconds:
                MiniStepper(label: "HOLD", text: Fmt.clock(draft.seconds), width: 120, disabled: draft.isDone,
                            onMinus: { draft.seconds = max(draft.seconds - 5, 0) },
                            onPlus: { draft.seconds += 5 })
            case .minutes:
                MiniStepper(label: "MINUTES", text: "\(draft.seconds / 60)", width: 120, disabled: draft.isDone,
                            onMinus: { draft.seconds = max(draft.seconds - 60, 0) },
                            onPlus: { draft.seconds += 60 })
            }

            Spacer(minLength: 0)

            Button {
                draft.isDone ? onUndo() : onComplete()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(draft.isDone ? Color.white : Theme.textSecondary)
                    .frame(width: 48, height: 48)
                    .background(draft.isDone ? Theme.accent : Theme.card,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(draft.isDone ? .clear : Theme.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.isDone ? "Undo set \(index + 1)" : "Complete set \(index + 1)")
        }
        .opacity(draft.isDone ? 0.75 : 1)
    }

    private var step: Double { exercise.weightStep ?? 2.5 }

    private func targetText(_ t: RepTarget) -> String {
        switch exercise.logType {
        case .seconds: return t.low == t.high ? Fmt.clock(t.low) : "\(Fmt.clock(t.low))–\(Fmt.clock(t.high))"
        case .minutes: return "\(t.text)m"
        default: return t.text
        }
    }
}

/// Compact − value + control with 44pt-tall buttons; hold a button to repeat.
private struct MiniStepper: View {
    let label: String
    let text: String
    let width: CGFloat
    var disabled = false
    let onMinus: () -> Void
    let onPlus: () -> Void
    var onSet: ((Double) -> Void)? = nil

    @State private var typing = false
    @State private var entry = ""

    var body: some View {
        HStack(spacing: 0) {
            button("minus", action: onMinus)
            Button {
                guard onSet != nil, !disabled else { return }
                entry = ""
                typing = true
            } label: {
            VStack(spacing: -2) {
                Text(text)
                    .font(.display(24))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            .frame(width: width, height: 48)
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            button("plus", action: onPlus)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .disabled(disabled)
        .alert(label, isPresented: $typing) {
            TextField(text, text: $entry).keyboardType(.decimalPad)
            Button("Set") {
                if let v = Double(entry.replacingOccurrences(of: ",", with: ".")), v >= 0 { onSet?(v) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func button(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(disabled ? Theme.textFaint : Theme.textPrimary)
                .frame(width: 36, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }
}
