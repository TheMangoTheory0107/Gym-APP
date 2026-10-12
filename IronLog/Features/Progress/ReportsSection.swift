import SwiftData
import SwiftUI
import UIKit

/// Weekly / monthly progress report with a short "focus next" list worked out from your own data.
struct ProgressReport {
    enum Period: String, CaseIterable, Identifiable {
        case week = "Weekly", month = "Monthly"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    let period: Period
    let start: Date
    let end: Date

    // Training
    var workoutsDone = 0
    var workoutsPlanned = 0
    var totalSets = 0
    var volume: Double = 0
    var volumeChange: Double?
    var newPRs: [String] = []
    var leastTrained: [(String, Double)] = []
    var stalled: [String] = []

    // Nutrition
    var daysLogged = 0
    var avgKcal: Double = 0
    var avgProtein: Double = 0
    var proteinHitDays = 0
    var creatineDays = 0
    var supplementPercent: Double = 0

    // Body
    var weightStart: Double?
    var weightEnd: Double?
    var bmiEnd: Double?
    var bodyFatEnd: Double?
    var ffmiEnd: Double?

    var focus: [String] = []
}

enum ReportBuilder {
    static func build(_ period: ProgressReport.Period, sessions: [WorkoutSession], food: [FoodEntry],
                      metrics: [BodyMetric], checks: [SupplementCheck], heightCm: Double,
                      kcalTarget: Double, proteinTarget: Double) -> ProgressReport {
        let end = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -period.days, to: end.startOfDay.endOfDay) ?? end
        let prevStart = Calendar.current.date(byAdding: .day, value: -period.days, to: start) ?? start
        var r = ProgressReport(period: period, start: start, end: end)
        let catalog = Catalog.shared

        // Training
        let finished = sessions.filter(\.isFinished)
        let inPeriod = finished.filter { $0.startedAt >= start }
        let previous = finished.filter { $0.startedAt >= prevStart && $0.startedAt < start }
        r.workoutsDone = inPeriod.count
        r.workoutsPlanned = (0..<period.days).filter { offset in
            let d = Calendar.current.date(byAdding: .day, value: -offset, to: end) ?? end
            return Calendar.current.component(.weekday, from: d) != 1
        }.count
        r.totalSets = inPeriod.reduce(0) { $0 + $1.sets.count }
        r.volume = inPeriod.reduce(0) { $0 + $1.totalVolume }
        let prevVolume = previous.reduce(0) { $0 + $1.totalVolume }
        if prevVolume > 0 { r.volumeChange = (r.volume - prevVolume) / prevVolume }

        // PRs: best e1RM in period beats everything before the period
        var stalled: [String] = []
        let exerciseIds = Set(inPeriod.flatMap { $0.sets.map(\.exerciseId) })
        for id in exerciseIds {
            guard let ex = catalog.exercise(id), ex.logType == .weightReps else { continue }
            let now = inPeriod.flatMap { $0.sets.filter { $0.exerciseId == id } }.map(\.estimatedOneRepMax).max() ?? 0
            let before = finished.filter { $0.startedAt < start }
                .flatMap { $0.sets.filter { $0.exerciseId == id } }.map(\.estimatedOneRepMax).max()
            if let before, now > before + 0.01 { r.newPRs.append(ex.name) }
            // Stalled: no e1RM improvement over the last 3 weeks vs the 3 weeks before (needs history).
            let threeWeeks = Calendar.current.date(byAdding: .day, value: -21, to: end) ?? end
            let sixWeeks = Calendar.current.date(byAdding: .day, value: -42, to: end) ?? end
            let recent = finished.filter { $0.startedAt >= threeWeeks }
                .flatMap { $0.sets.filter { $0.exerciseId == id } }.map(\.estimatedOneRepMax).max()
            let older = finished.filter { $0.startedAt >= sixWeeks && $0.startedAt < threeWeeks }
                .flatMap { $0.sets.filter { $0.exerciseId == id } }.map(\.estimatedOneRepMax).max()
            if let recent, let older, recent <= older { stalled.append(ex.name) }
        }
        r.newPRs.sort()
        r.stalled = stalled.sorted()

        let weeksBack = period == .week ? [0] : [0, 1, 2, 3]
        let volume = TrainingStats.groupVolume(sessions: sessions, weeksBack: weeksBack)
        var perGroup: [String: Double] = [:]
        for v in volume { perGroup[v.group, default: 0] += v.sets }
        let weeks = Double(weeksBack.count)
        r.leastTrained = perGroup.map { ($0.key, $0.value / weeks) }.sorted { $0.1 < $1.1 }.prefix(2).map { $0 }

        // Nutrition
        let totals = FoodLogStore.dailyTotals(food.filter { $0.date >= start })
        r.daysLogged = totals.count
        if !totals.isEmpty {
            r.avgKcal = totals.values.reduce(0) { $0 + $1.kcal } / Double(totals.count)
            r.avgProtein = totals.values.reduce(0) { $0 + $1.protein } / Double(totals.count)
            r.proteinHitDays = totals.values.filter { $0.protein >= proteinTarget }.count
        }
        let periodChecks = checks.filter { $0.takenAt >= start }
        r.creatineDays = Set(periodChecks.filter { $0.supplementId == "creatine" }.map(\.dayKey)).count
        let required = FoodDatabase.shared.supplements.filter { $0.optional != true }.count
        if required > 0 {
            let takenPairs = Set(periodChecks.map { "\($0.dayKey)|\($0.supplementId)" }).count
            r.supplementPercent = min(Double(takenPairs) / Double(required * period.days), 1)
        }

        // Body
        let inRange = metrics.filter { $0.date >= start }.sorted { $0.date < $1.date }
        let beforeRange = metrics.filter { $0.date < start }.max { $0.date < $1.date }
        r.weightStart = (beforeRange ?? inRange.first)?.weightKg
        let latest = metrics.max { $0.date < $1.date }
        r.weightEnd = latest?.weightKg
        if let w = latest?.weightKg { r.bmiEnd = BodyMath.bmi(weightKg: w, heightCm: heightCm) }
        r.bodyFatEnd = metrics.sorted { $0.date > $1.date }.lazy.compactMap(\.bodyFatPercent).first
        if let w = r.weightEnd, let bf = r.bodyFatEnd { r.ffmiEnd = BodyMath.ffmi(weightKg: w, bodyFatPercent: bf, heightCm: heightCm) }

        // Focus list (most important first, max 3)
        var focus: [String] = []
        let missedProtein = r.daysLogged - r.proteinHitDays
        if r.daysLogged > 0, missedProtein >= 2 {
            focus.append("Protein missed on \(missedProtein) of \(r.daysLogged) logged days. Add a scoop of whey or 150 g chicken on those days.")
        }
        if r.workoutsDone < r.workoutsPlanned {
            let missed = r.workoutsPlanned - r.workoutsDone
            focus.append("\(missed) session\(missed == 1 ? "" : "s") missed. Use the day switcher on TODAY to catch up the next free day.")
        }
        if let s = r.stalled.first {
            focus.append("\(s) hasn't progressed in 3 weeks. Add 2.5 kg, or 1 more rep per set before adding weight.")
        }
        if let low = r.leastTrained.first, low.1 < 8, r.workoutsDone > 0 {
            focus.append("\(low.0) got only \(Fmt.weight((low.1 * 10).rounded() / 10)) sets a week. Aim for 10+.")
        }
        if r.daysLogged >= 3, abs(r.avgKcal - kcalTarget) / kcalTarget > 0.1 {
            let dir = r.avgKcal > kcalTarget ? "above" : "below"
            focus.append("Calories averaged \(Int(r.avgKcal)), \(dir) your \(Int(kcalTarget)) target.")
        }
        if r.daysLogged == 0 {
            focus.append("No food logged in this period. Tap “Ate as planned” after each meal; it takes one second.")
        }
        if r.creatineDays < min(period.days, 5) {
            focus.append("Creatine taken \(r.creatineDays) of \(period.days) days. It only works if taken daily.")
        }
        r.focus = Array(focus.prefix(3))
        return r
    }
}

struct ReportsSection: View {
    @Environment(\.displayScale) private var displayScale
    @Query private var sessions: [WorkoutSession]
    @Query private var food: [FoodEntry]
    @Query private var metrics: [BodyMetric]
    @Query private var checks: [SupplementCheck]
    @AppStorage(ProfileKey.heightCm) private var heightCm = ProfileDefault.heightCm
    @AppStorage(ProfileKey.kcalTarget) private var kcalTarget = ProfileDefault.kcal
    @AppStorage(ProfileKey.proteinTarget) private var proteinTarget = ProfileDefault.protein

    @State private var period: ProgressReport.Period = .week

    private var report: ProgressReport {
        ReportBuilder.build(period, sessions: sessions, food: food, metrics: metrics, checks: checks,
                            heightCm: heightCm, kcalTarget: kcalTarget, proteinTarget: proteinTarget)
    }

    var body: some View {
        let r = report
        VStack(alignment: .leading, spacing: 14) {
            Picker("Period", selection: $period) {
                ForEach(ProgressReport.Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            ReportCard(report: r, proteinTarget: proteinTarget)

            if let image = renderImage(r) {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("Iron Log \(r.period.rawValue) report", image: Image(uiImage: image))) {
                    Label("Share as image", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.secondary)
            }
        }
    }

    @MainActor
    private func renderImage(_ r: ProgressReport) -> UIImage? {
        let renderer = ImageRenderer(content:
            ReportCard(report: r, proteinTarget: proteinTarget)
                .padding(16)
                .frame(width: 390)
                .background(Theme.background)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = displayScale
        return renderer.uiImage
    }
}

struct ReportCard: View {
    let report: ProgressReport
    let proteinTarget: Double

    var body: some View {
        let r = report
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(r.period.rawValue.uppercased()) REPORT")
                    .font(.display(18)).tracking(2).foregroundStyle(Theme.accent)
                Text("\(r.start.formatted(.dateTime.day().month(.abbreviated))) – \(r.end.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.display(34)).foregroundStyle(Theme.textPrimary)
            }

            group("Training") {
                HStack {
                    StatTile(label: "Workouts", value: "\(r.workoutsDone)/\(r.workoutsPlanned)", highlight: true)
                    StatTile(label: "Sets", value: "\(r.totalSets)")
                    StatTile(label: "Volume", value: Fmt.volume(r.volume), unit: "kg")
                }
                if let change = r.volumeChange {
                    line("Volume vs previous \(r.period == .week ? "week" : "month")",
                         "\(change >= 0 ? "+" : "−")\(Int(abs(change * 100)))%")
                }
                line("New PRs", r.newPRs.isEmpty ? "—" : r.newPRs.joined(separator: ", "))
                if !r.leastTrained.isEmpty {
                    line("Least trained", r.leastTrained.map { "\($0.0) (\(Fmt.weight(($0.1 * 10).rounded() / 10)) sets/wk)" }.joined(separator: ", "))
                }
            }

            group("Nutrition") {
                HStack {
                    StatTile(label: "Avg kcal", value: r.daysLogged > 0 ? "\(Int(r.avgKcal))" : "—")
                    StatTile(label: "Avg protein", value: r.daysLogged > 0 ? "\(Int(r.avgProtein))" : "—", unit: "g")
                    StatTile(label: "Protein hit", value: "\(r.proteinHitDays)/\(r.daysLogged)", highlight: true)
                }
                line("Creatine", "\(r.creatineDays) days")
                line("Supplements taken", "\(Int(r.supplementPercent * 100))%")
            }

            group("Body") {
                HStack {
                    StatTile(label: "Weight", value: r.weightEnd.map { String(format: "%.1f", $0) } ?? "—", unit: "kg")
                    StatTile(label: "BMI", value: r.bmiEnd.map { String(format: "%.1f", $0) } ?? "—")
                    StatTile(label: "FFMI", value: r.ffmiEnd.map { String(format: "%.1f", $0) } ?? "—")
                }
                if let a = r.weightStart, let b = r.weightEnd {
                    line("Weight change", "\(b - a >= 0 ? "+" : "−")\(String(format: "%.1f", abs(b - a))) kg")
                }
                if let bf = r.bodyFatEnd { line("Body fat (latest)", String(format: "%.1f%%", bf)) }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Focus next \(r.period == .week ? "week" : "month")", accent: true)
                if r.focus.isEmpty {
                    Text("All on track. Keep doing exactly this.").font(.subheadline).foregroundStyle(Theme.textPrimary)
                }
                ForEach(Array(r.focus.enumerated()), id: \.offset) { i, f in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(.display(22)).foregroundStyle(Theme.accent).frame(width: 18)
                        Text(f).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .cardStyle()
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.accent.opacity(0.6)))
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            content()
        }
        .cardStyle()
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
