import Charts
import SwiftData
import SwiftUI

/// Daily and weekly calories/protein, and which days protein target was hit.
struct NutritionHistoryView: View {
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @AppStorage(ProfileKey.kcalTarget) private var kcalTarget = ProfileDefault.kcal
    @AppStorage(ProfileKey.proteinTarget) private var proteinTarget = ProfileDefault.protein

    private struct DayPoint: Identifiable {
        let date: Date
        let macros: Macros
        var id: Date { date }
    }

    private func days(_ count: Int) -> [DayPoint] {
        let totals = FoodLogStore.dailyTotals(entries)
        return (0..<count).reversed().compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date.now.startOfDay) else { return nil }
            return DayPoint(date: d, macros: totals[d.dayKey] ?? Macros())
        }
    }

    private var weeks: [DayPoint] {
        let totals = FoodLogStore.dailyTotals(entries)
        let thisWeek = WorkoutStats.startOfWeek()
        return (0..<8).reversed().compactMap { w in
            guard let start = Calendar.current.date(byAdding: .weekOfYear, value: -w, to: thisWeek) else { return nil }
            let logged = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
                .compactMap { totals[$0.dayKey] }
            guard !logged.isEmpty else { return DayPoint(date: start, macros: Macros()) }
            let sum = logged.reduce(Macros(), +)
            let n = Double(logged.count)
            return DayPoint(date: start, macros: Macros(kcal: sum.kcal / n, protein: sum.protein / n,
                                                        carbs: sum.carbs / n, fat: sum.fat / n))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(title: "History", kicker: "Nutrition")

                chartCard("Calories · last 14 days", data: days(14), value: \.kcal, target: kcalTarget, unit: "kcal")
                chartCard("Protein · last 14 days", data: days(14), value: \.protein, target: proteinTarget, unit: "g")
                chartCard("Weekly average calories", data: weeks, value: \.kcal, target: kcalTarget, unit: "kcal", weekly: true)
                chartCard("Weekly average protein", data: weeks, value: \.protein, target: proteinTarget, unit: "g", weekly: true)

                proteinCalendar
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chartCard(_ title: String, data: [DayPoint], value: KeyPath<Macros, Double>, target: Double,
                           unit: String, weekly: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            Chart {
                ForEach(data) { p in
                    BarMark(x: .value("Day", p.date, unit: weekly ? .weekOfYear : .day),
                            y: .value(unit, p.macros[keyPath: value]))
                        .foregroundStyle(p.macros[keyPath: value] >= target ? Theme.accent : Theme.textFaint)
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Theme.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("TARGET \(Int(target))").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: weekly ? .weekOfYear : .day, count: weekly ? 2 : 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textFaint)
                }
            }
            .frame(height: 180)
        }
        .cardStyle()
    }

    /// Last 28 days: red = protein target hit, grey = missed, empty = nothing logged.
    private var proteinCalendar: some View {
        let data = days(28)
        let hit = data.filter { $0.macros.protein >= proteinTarget }.count
        let logged = data.filter { $0.macros.kcal > 0 }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Protein target · 28 days")
                Spacer()
                Text("\(hit)/\(logged) days").font(.display(20)).foregroundStyle(Theme.accent)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(data) { p in
                    let isHit = p.macros.protein >= proteinTarget
                    let hasData = p.macros.kcal > 0
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHit ? Theme.accent : hasData ? Theme.cardRaised : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.stroke, lineWidth: hasData ? 0 : 1))
                        .overlay(Text("\(Calendar.current.component(.day, from: p.date))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isHit ? Color.white : Theme.textFaint))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .cardStyle()
    }
}
