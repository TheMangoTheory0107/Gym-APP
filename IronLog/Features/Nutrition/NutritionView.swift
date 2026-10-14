import SwiftData
import SwiftUI
import UIKit

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var allFood: [FoodEntry]
    @Query(sort: \CustomFood.name) private var customFoods: [CustomFood]

    @AppStorage(ProfileKey.kcalTarget) private var kcalTarget = ProfileDefault.kcal
    @AppStorage(ProfileKey.proteinTarget) private var proteinTarget = ProfileDefault.protein
    @AppStorage(ProfileKey.carbsTarget) private var carbsTarget = ProfileDefault.carbs
    @AppStorage(ProfileKey.fatTarget) private var fatTarget = ProfileDefault.fat
    @AppStorage(ProfileKey.fiberTarget) private var fiberTarget = ProfileDefault.fiber

    @State private var text = ""
    @State private var review: ReviewRequest?
    @State private var toast: String?
    @FocusState private var inputFocused: Bool
    @State private var dictation = SpeechDictation()
    @State private var spokenPrefix = ""

    private let db = FoodDatabase.shared

    private var todaysFood: [FoodEntry] {
        let start = Date.now.startOfDay
        return allFood.filter { $0.date >= start }
    }

    private var eaten: Macros {
        todaysFood.reduce(Macros()) { $0 + Macros(kcal: $1.kcal, protein: $1.protein, carbs: $1.carbs, fat: $1.fat, fiber: $1.fiber) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !db.loadErrors.isEmpty { DataErrorBanner(errors: db.loadErrors) }

                    foodHeader.revealOnAppear()
                    macroBars.revealOnAppear(delay: 0.06)
                    nextMealCard.revealOnAppear(delay: 0.12)
                    mealChips
                    WaterCard()
                    logBox

                    SectionLabel(text: "Full diet plan", accent: true)
                        .padding(.top, 6)
                    ForEach(db.plan) { meal in
                        PlanMealCard(meal: meal,
                                     logged: todaysFood.contains { $0.meal == meal.name },
                                     onAte: { ateAsPlanned(meal) },
                                     onAdjust: { review = ReviewRequest(items: FoodLogStore.parsedItems(for: meal),
                                                                        meal: meal.name, title: meal.name) },
                                     onUndo: { undo(meal) })
                    }
                    PlanVsTargetCard(plan: db.planTotal,
                                     target: Macros(kcal: kcalTarget, protein: proteinTarget, carbs: carbsTarget, fat: fatTarget))

                    SupplementsCard()

                    if !todaysFood.isEmpty {
                        SectionLabel(text: "Today's log")
                        TodayLogList(entries: todaysFood)
                    }

                    NavigationLink {
                        NutritionHistoryView()
                    } label: {
                        Label("History & charts", systemImage: "chart.bar.fill")
                    }
                    .buttonStyle(.secondary)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: todaysFood.count) { _, _ in WidgetSync.update(context: context) }
            .sheet(item: $review) { r in
                FoodReviewSheet(items: r.items, meal: r.meal, title: r.title)
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Header

    private var foodHeader: some View {
        let left = kcalTarget - eaten.kcal
        return VStack(alignment: .leading, spacing: 0) {
            Text("FOOD · " + Date.now.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.display(17)).tracking(2).foregroundStyle(Theme.ember)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(abs(left)).formatted())")
                    .font(.display(52)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                    .contentTransition(.numericText())
                Text(left >= 0 ? "KCAL TO GO" : "KCAL OVER")
                    .font(.display(24)).foregroundStyle(left >= 0 ? Theme.textSecondary : Theme.ember)
            }
            GradientBar(progress: eaten.kcal / max(kcalTarget, 1), height: 6)
                .padding(.top, 2)
            Text("\(Int(eaten.kcal)) eaten of \(Int(kcalTarget)) kcal")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textFaint).padding(.top, 6)
        }
        .padding(.top, 4)
    }

    private var macroBars: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                macroTile("Protein", eaten.protein, proteinTarget, emphasised: true)
                macroTile("Carbs", eaten.carbs, carbsTarget)
            }
            HStack(spacing: 8) {
                macroTile("Fat", eaten.fat, fatTarget)
                macroTile("Fibre", eaten.fiber, fiberTarget)
            }
        }
    }

    private func macroTile(_ name: String, _ value: Double, _ target: Double, emphasised: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(name.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Theme.textFaint)
                Spacer(minLength: 0)
                HelpButton(term: name.lowercased()).frame(width: 20, height: 20)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value))").font(.display(30))
                    .foregroundStyle(emphasised ? Theme.ember : Theme.textPrimary).monospacedDigit()
                Text("/ \(Int(target)) G").font(.display(15)).foregroundStyle(Theme.textSecondary)
            }
            GradientBar(progress: value / max(target, 1), height: 5, muted: !emphasised)
        }
        .cardStyle(padding: 12)
    }

    /// The first planned meal not logged yet today.
    private var nextMeal: PlanMeal? {
        db.plan.first { meal in !todaysFood.contains { $0.meal == meal.name } }
    }

    @ViewBuilder
    private var nextMealCard: some View {
        if let meal = nextMeal {
            let m = db.macros(of: meal)
            VStack(alignment: .leading, spacing: 10) {
                Text("NEXT MEAL · \(meal.time.uppercased())").font(.display(16)).tracking(2).foregroundStyle(Theme.ember)
                Text(meal.name.uppercased()).font(.display(40)).foregroundStyle(Theme.textPrimary)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(meal.items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Circle().fill(Theme.ember).frame(width: 5, height: 5)
                            Text(planItemText(item)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                HStack(spacing: 6) {
                    InfoPill(icon: "flame", text: "\(Int(m.kcal)) kcal")
                    InfoPill(icon: "bolt.fill", text: "\(Int(m.protein)) g protein", highlight: true)
                }
                Button {
                    ateAsPlanned(meal)
                } label: {
                    Label("I ate this", systemImage: "checkmark")
                }
                .buttonStyle(.primary)
                HStack(spacing: 8) {
                    Button {
                        review = ReviewRequest(items: FoodLogStore.parsedItems(for: meal), meal: meal.name, title: meal.name)
                    } label: {
                        Label("Adjust", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.secondary)
                    Button {
                        Haptics.tap()
                        inputFocused = true
                    } label: {
                        Label("Ate else", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.secondary)
                }
            }
            .heroCardStyle()
        } else {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(Theme.ember)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ALL MEALS LOGGED").font(.display(24)).foregroundStyle(Theme.textPrimary)
                    Text("Nice work. Anything extra? Log it below.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            .heroCardStyle()
        }
    }

    private var mealChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(db.plan) { meal in
                    let logged = todaysFood.contains { $0.meal == meal.name }
                    HStack(spacing: 5) {
                        Image(systemName: logged ? "checkmark" : "clock").font(.system(size: 10, weight: .heavy))
                        Text(meal.name).font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .foregroundStyle(logged ? Theme.ember : Theme.textSecondary)
                    .background(logged ? Theme.accent.opacity(0.15) : Theme.card, in: Capsule())
                }
            }
        }
    }

    private func planItemText(_ item: PlanItem) -> String {
        let name = db.food(item.food)?.name ?? item.food
        let unit = ["g", "ml"].contains(item.unit) ? item.unit : " \(item.unit)"
        return "\(Fmt.weight(item.qty))\(unit) \(name.lowercased())"
    }

    // MARK: Log box

    private var logBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Log something else")
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("e.g. 2 rotis, 1 bowl dal, 150g paneer, 1 banana")
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 8).padding(.leading, 5)
                }
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($inputFocused)
                    .padding(.vertical, 8)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 10)
            .padding(.trailing, 44)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button {
                    inputFocused = false
                    if !dictation.isListening { spokenPrefix = text.isEmpty ? "" : text + ", " }
                    Task { await dictation.toggle() }
                } label: {
                    Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(dictation.isListening ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card),
                                    in: Circle())
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: dictation.isListening ? 0 : 1))
                        .symbolEffect(.pulse, isActive: dictation.isListening)
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(dictation.isListening ? "Stop listening" : "Speak your food")
            }
            .onChange(of: dictation.transcript) { _, spoken in
                if dictation.isListening || !spoken.isEmpty { text = spokenPrefix + spoken }
            }

            if let error = dictation.errorMessage {
                Text(error).font(.caption).foregroundStyle(Theme.ember)
            } else {
                Text(dictation.isListening ? "Listening… say it like you'd text it, then tap stop."
                                           : "Type or tap the mic and say it, e.g. \"do roti, ek katori dal\".")
                    .font(.caption)
                    .foregroundStyle(dictation.isListening ? Theme.ember : Theme.textFaint)
            }

            Button {
                dictation.stop()
                parse()
            } label: {
                Label("Log food", systemImage: "plus")
            }
            .buttonStyle(.primary)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .cardStyle()
    }

    private func parse() {
        inputFocused = false
        let foods = db.foods + customFoods.map(FoodItem.init(custom:))
        let items = FoodParser.parse(text, foods: foods)
        guard !items.isEmpty else { return }
        review = ReviewRequest(items: items, meal: FoodLogStore.defaultMeal(), title: "Check & save")
        text = ""
    }

    private func ateAsPlanned(_ meal: PlanMeal) {
        FoodLogStore.logPlanMeal(meal, context: context)
        Haptics.success()
        flash("\(meal.name) logged")
    }

    private func undo(_ meal: PlanMeal) {
        for e in todaysFood where e.meal == meal.name { context.delete(e) }
        try? context.save()
        Haptics.tap()
    }

    private func flash(_ message: String) {
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.snappy) { toast = nil }
        }
    }

    // MARK: Rings

    private var calorieCard: some View {
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: eaten.kcal / max(kcalTarget, 1), lineWidth: 18)
                VStack(spacing: -4) {
                    Text("\(Int(max(kcalTarget - eaten.kcal, 0)))")
                        .font(.display(40))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text(eaten.kcal > kcalTarget ? "KCAL OVER" : "KCAL LEFT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 12) {
                StatTile(label: "Eaten", value: "\(Int(eaten.kcal))", unit: "kcal")
                StatTile(label: "Target", value: "\(Int(kcalTarget))", unit: "kcal")
            }
        }
        .cardStyle(padding: 18)
    }
}

struct ReviewRequest: Identifiable {
    let id = UUID()
    let items: [ParsedFood]
    let meal: String
    let title: String
}

// MARK: - Pieces

struct MacroRing: View {
    let name: String
    let value: Double
    let target: Double
    var emphasised = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ProgressRing(progress: value / max(target, 1), lineWidth: 9,
                             color: emphasised ? Theme.accent : Theme.textSecondary)
                VStack(spacing: -2) {
                    Text("\(Int(abs(target - value)))")
                        .font(.display(24))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text(value > target ? "G OVER" : "G LEFT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .frame(width: 78, height: 78)
            Text(name.uppercased())
                .font(.display(17))
                .foregroundStyle(emphasised ? Theme.accent : Theme.textSecondary)
            Text("\(Int(value)) / \(Int(target)) g")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textFaint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 12)
    }
}

private struct PlanMealCard: View {
    let meal: PlanMeal
    let logged: Bool
    let onAte: () -> Void
    let onAdjust: () -> Void
    let onUndo: () -> Void

    var body: some View {
        let m = FoodDatabase.shared.macros(of: meal)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name.uppercased()).font(.display(24)).foregroundStyle(Theme.textPrimary)
                    Text(meal.time + (meal.note.map { " · \($0)" } ?? ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(m.kcal)) kcal").font(.display(20)).foregroundStyle(Theme.textPrimary)
                    Text("P \(Int(m.protein)) · C \(Int(m.carbs)) · F \(Int(m.fat))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            Text(meal.items.map(itemText).joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            if logged {
                HStack {
                    Label("LOGGED", systemImage: "checkmark.circle.fill")
                        .font(.display(20))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Button("Undo", action: onUndo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                }
            } else {
                HStack(spacing: 10) {
                    Button(action: onAte) {
                        Label("Ate as planned", systemImage: "checkmark")
                    }
                    .buttonStyle(.primary)
                    Button("Adjust", action: onAdjust)
                        .buttonStyle(.secondary)
                        .frame(width: 110)
                }
            }
        }
        .cardStyle()
    }

    private func itemText(_ item: PlanItem) -> String {
        let name = FoodDatabase.shared.food(item.food)?.name ?? item.food
        let unit = ["g", "ml"].contains(item.unit) ? item.unit : " \(item.unit)"
        return "\(Fmt.weight(item.qty))\(unit) \(name.lowercased())"
    }
}

private struct PlanVsTargetCard: View {
    let plan: Macros
    let target: Macros

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Plan vs targets")
            row("Calories", plan.kcal, target.kcal, "kcal")
            row("Protein", plan.protein, target.protein, "g")
            row("Carbs", plan.carbs, target.carbs, "g")
            row("Fat", plan.fat, target.fat, "g")
            Text("Calculated from the food database, not the meal estimates.")
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
        }
        .cardStyle()
    }

    private func row(_ label: String, _ value: Double, _ goal: Double, _ unit: String) -> some View {
        let diff = value - goal
        let off = goal > 0 && abs(diff) / goal > 0.05
        return HStack {
            Text(label.uppercased()).font(.display(18)).foregroundStyle(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text("\(Int(value)) / \(Int(goal)) \(unit)").font(.subheadline.weight(.semibold)).monospacedDigit()
            Spacer()
            Text((diff >= 0 ? "+" : "−") + "\(Int(abs(diff)))")
                .font(.display(20))
                .foregroundStyle(off ? Theme.accent : Theme.textSecondary)
        }
    }
}

private struct TodayLogList: View {
    @Environment(\.modelContext) private var context
    let entries: [FoodEntry]

    var body: some View {
        let groups = Dictionary(grouping: entries, by: \.meal)
        let order = FoodLogStore.mealNames + groups.keys.filter { !FoodLogStore.mealNames.contains($0) }.sorted()
        VStack(spacing: 10) {
            ForEach(order.filter { groups[$0] != nil }, id: \.self) { meal in
                let items = groups[meal] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(meal.uppercased()).font(.display(20)).foregroundStyle(Theme.accent)
                        Spacer()
                        Text("\(Int(items.reduce(0) { $0 + $1.kcal })) kcal · P \(Int(items.reduce(0) { $0 + $1.protein }))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(items) { e in
                        HStack {
                            Text(e.name).font(.subheadline)
                            Text("\(Fmt.weight((e.grams).rounded())) g").font(.caption).foregroundStyle(Theme.textFaint)
                            Spacer()
                            Text("\(Int(e.kcal))").font(.subheadline.weight(.semibold)).monospacedDigit()
                            Button {
                                context.delete(e)
                                try? context.save()
                                Haptics.tap()
                            } label: {
                                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.textFaint)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .cardStyle(padding: 14)
            }
        }
    }
}
