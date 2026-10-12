import SwiftData
import SwiftUI

/// Stage 1: target rings for today. Stage 4 adds the food parser, diet plan, supplements and history.
struct NutritionView: View {
    @Query private var todaysFood: [FoodEntry]

    @AppStorage(ProfileKey.kcalTarget) private var kcalTarget = ProfileDefault.kcal
    @AppStorage(ProfileKey.proteinTarget) private var proteinTarget = ProfileDefault.protein
    @AppStorage(ProfileKey.carbsTarget) private var carbsTarget = ProfileDefault.carbs
    @AppStorage(ProfileKey.fatTarget) private var fatTarget = ProfileDefault.fat

    init() {
        let start = Date.now.startOfDay
        let end = Date.now.endOfDay
        _todaysFood = Query(filter: #Predicate<FoodEntry> { $0.date >= start && $0.date < end },
                            sort: \FoodEntry.date)
    }

    private var kcal: Double { todaysFood.reduce(0) { $0 + $1.kcal } }
    private var protein: Double { todaysFood.reduce(0) { $0 + $1.protein } }
    private var carbs: Double { todaysFood.reduce(0) { $0 + $1.carbs } }
    private var fat: Double { todaysFood.reduce(0) { $0 + $1.fat } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenTitle(title: "Nutrition",
                                kicker: Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))

                    calorieCard

                    HStack(spacing: 10) {
                        MacroRing(name: "Protein", value: protein, target: proteinTarget, emphasised: true)
                        MacroRing(name: "Carbs", value: carbs, target: carbsTarget)
                        MacroRing(name: "Fat", value: fat, target: fatTarget)
                    }

                    if todaysFood.isEmpty {
                        EmptyStateCard(icon: "fork.knife",
                                       title: "Nothing logged yet",
                                       message: "Food logging, your diet plan and supplements arrive in Stage 4.")
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .screenBackground()
        }
    }

    private var calorieCard: some View {
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: kcal / max(kcalTarget, 1), lineWidth: 18)
                VStack(spacing: -4) {
                    Text("\(Int(max(kcalTarget - kcal, 0)))")
                        .font(.display(40))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text("KCAL LEFT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 12) {
                StatTile(label: "Eaten", value: "\(Int(kcal))", unit: "kcal")
                StatTile(label: "Target", value: "\(Int(kcalTarget))", unit: "kcal")
            }
        }
        .cardStyle(padding: 18)
    }
}

private struct MacroRing: View {
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
                    Text("\(Int(max(target - value, 0)))")
                        .font(.display(24))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text("G LEFT")
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
