import Charts
import SwiftData
import SwiftUI

struct ProgressTabView: View {
    enum ProgressSection: String, CaseIterable, Identifiable {
        case body = "Body", strength = "Strength", reports = "Reports"
        var id: String { rawValue }
    }

    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @State private var section: ProgressSection = .body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenTitle(title: "Progress", kicker: "Body & strength")

                    HStack(spacing: 6) {
                        ForEach(ProgressSection.allCases) { s in
                            Button {
                                Haptics.select()
                                withAnimation(.snappy) { section = s }
                            } label: {
                                Text(s.rawValue.uppercased())
                                    .font(.display(19))
                                    .tracking(1)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(section == s ? Color.white : Theme.textSecondary)
                                    .background(section == s ? Theme.accent : Theme.card,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    switch section {
                    case .body: BodySection(metrics: metrics)
                    case .strength: StrengthSection(sessions: sessions)
                    case .reports: ReportsSection()
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .screenBackground()
        }
    }
}

// MARK: - Body

private struct BodySection: View {
    let metrics: [BodyMetric]
    @AppStorage(ProfileKey.heightCm) private var heightCm = ProfileDefault.heightCm
    @State private var showWeighIn = false
    @State private var range = 90

    private var latest: BodyMetric? { metrics.first }
    private var latestBodyFat: Double? { metrics.lazy.compactMap(\.bodyFatPercent).first }

    private var chartData: [BodyMetric] {
        let from = Calendar.current.date(byAdding: .day, value: -range, to: .now) ?? .distantPast
        return metrics.filter { $0.date >= from }.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let latest { bodyCard(latest) }

            Button {
                Haptics.tap()
                showWeighIn = true
            } label: {
                Label("Log weigh-in", systemImage: "scalemass.fill")
            }
            .buttonStyle(.primary)

            if chartData.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel(text: "Body weight")
                        Spacer()
                        Picker("Range", selection: $range) {
                            Text("30D").tag(30)
                            Text("90D").tag(90)
                            Text("1Y").tag(365)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                    let values = chartData.map(\.weightKg)
                    let lo = (values.min() ?? 0) - 1, hi = (values.max() ?? 0) + 1
                    Chart(chartData) { m in
                        LineMark(x: .value("Date", m.date), y: .value("kg", m.weightKg))
                            .foregroundStyle(Theme.accent)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", m.date), y: .value("kg", m.weightKg))
                            .foregroundStyle(Theme.accent)
                            .symbolSize(24)
                    }
                    .chartYScale(domain: lo...hi)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(Theme.stroke)
                            AxisValueLabel().foregroundStyle(Theme.textFaint)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textFaint) }
                    }
                    .frame(height: 200)
                    if let first = chartData.first, let last = chartData.last {
                        let change = last.weightKg - first.weightKg
                        Text("\(change >= 0 ? "+" : "−")\(Fmt.weight(abs((change * 10).rounded() / 10))) kg in this period")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .cardStyle()
            }

            if !metrics.isEmpty {
                SectionLabel(text: "Recent weigh-ins")
                VStack(spacing: 8) {
                    ForEach(metrics.prefix(8)) { m in
                        HStack {
                            Text(m.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            if m.source == "health" {
                                Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Theme.accent)
                            }
                            Spacer()
                            if let bf = m.bodyFatPercent {
                                Text(String(format: "%.1f%%", bf))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            Text(String(format: "%.1f kg", m.weightKg))
                                .font(.display(22))
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                        }
                        .cardStyle(padding: 12)
                    }
                }
            }
        }
        .sheet(isPresented: $showWeighIn) {
            WeighInSheet(lastWeight: latest?.weightKg ?? ProfileDefault.startWeightKg, lastBodyFat: latestBodyFat)
                .presentationDetents([.medium, .large])
        }
    }

    private func bodyCard(_ m: BodyMetric) -> some View {
        let bmi = BodyMath.bmi(weightKg: m.weightKg, heightCm: heightCm)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                StatTile(label: "Weight", value: String(format: "%.1f", m.weightKg), unit: "kg")
                StatTile(label: "Body fat", value: latestBodyFat.map { String(format: "%.1f", $0) } ?? "—", unit: "%")
            }
            Divider().overlay(Theme.stroke)
            HStack {
                StatTile(label: "BMI · " + BodyMath.bmiCategory(bmi), value: String(format: "%.1f", bmi), highlight: true)
                if let bf = latestBodyFat {
                    StatTile(label: "FFMI", value: String(format: "%.1f", BodyMath.ffmi(weightKg: m.weightKg, bodyFatPercent: bf, heightCm: heightCm)),
                             highlight: true)
                }
            }
            if let bf = latestBodyFat {
                HStack {
                    StatTile(label: "Lean mass", value: String(format: "%.1f", BodyMath.leanMass(weightKg: m.weightKg, bodyFatPercent: bf)), unit: "kg")
                    StatTile(label: "Fat mass", value: String(format: "%.1f", m.weightKg * bf / 100), unit: "kg")
                }
            }
            Text("BMI ignores muscle, so lifters often read \"overweight\". FFMI and body fat are the better guides for you.")
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
        }
        .cardStyle(padding: 18)
    }
}

// MARK: - Strength

private struct StrengthSection: View {
    let sessions: [WorkoutSession]
    @State private var exerciseId = ""

    private var loggedExercises: [ExerciseDef] {
        let ids = Set(TrainingStats.finished(sessions).flatMap { $0.sets.map(\.exerciseId) })
        return Catalog.shared.exercises.filter { ids.contains($0.id) && $0.logType != .minutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            streakCard

            if loggedExercises.isEmpty {
                EmptyStateCard(icon: "dumbbell.fill", title: "No lifts yet",
                               message: "Finish your first workout and your strength charts, PRs and weekly volume show up here.")
            } else {
                exerciseChart
                volumeChart
                prList
            }
        }
        .onAppear {
            if exerciseId.isEmpty || !loggedExercises.contains(where: { $0.id == exerciseId }) {
                exerciseId = loggedExercises.first { $0.logType == .weightReps }?.id ?? loggedExercises.first?.id ?? ""
            }
        }
    }

    private var streakCard: some View {
        let days = TrainingStats.trainedDays(sessions)
        let weekStart = WorkoutStats.startOfWeek()
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -11, to: weekStart) ?? weekStart
        let cells = (0..<84).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Workout streak")
                Spacer()
                Text("\(TrainingStats.streak(sessions))").font(.display(40)).foregroundStyle(Theme.accent)
                Text("DAYS").font(.display(16)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(.caption2.weight(.bold)).foregroundStyle(Theme.textFaint).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells, id: \.self) { d in
                    let done = days.contains(d.dayKey)
                    let future = d > .now
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(done ? Theme.accent : future ? Color.clear : Theme.cardRaised)
                        .frame(height: 16)
                }
            }
            Text("Last 12 weeks · Sundays never break your streak")
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
        }
        .cardStyle()
    }

    private var exerciseChart: some View {
        let ex = Catalog.shared.exercise(exerciseId)
        let points = TrainingStats.history(for: exerciseId, sessions: sessions)
        return VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(loggedExercises) { e in Button(e.name) { exerciseId = e.id } }
            } label: {
                HStack {
                    Text((ex?.name ?? "Pick exercise").uppercased()).font(.display(22)).foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
            if let ex, points.count >= 1 {
                Chart(points) { p in
                    switch ex.logType {
                    case .weightReps:
                        LineMark(x: .value("Date", p.date), y: .value("kg", p.topWeight), series: .value("Series", "Top set"))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", p.date), y: .value("kg", p.topWeight))
                            .foregroundStyle(Theme.accent)
                        LineMark(x: .value("Date", p.date), y: .value("kg", p.estimatedMax), series: .value("Series", "Est. 1RM"))
                            .foregroundStyle(Theme.textSecondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    case .reps:
                        LineMark(x: .value("Date", p.date), y: .value("reps", p.bestReps)).foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", p.date), y: .value("reps", p.bestReps)).foregroundStyle(Theme.accent)
                    case .seconds, .minutes:
                        LineMark(x: .value("Date", p.date), y: .value("sec", p.bestSeconds)).foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", p.date), y: .value("sec", p.bestSeconds)).foregroundStyle(Theme.accent)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel().foregroundStyle(Theme.textFaint)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textFaint) }
                }
                .frame(height: 200)
                if ex.logType == .weightReps {
                    HStack(spacing: 14) {
                        Label("Top set", systemImage: "circle.fill").foregroundStyle(Theme.accent)
                        Label("Est. 1RM", systemImage: "line.diagonal").foregroundStyle(Theme.textSecondary)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .cardStyle()
    }

    private var volumeChart: some View {
        let data = TrainingStats.groupVolume(sessions: sessions, weeksBack: [1, 0])
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Weekly sets per muscle group")
            Chart(data) { v in
                BarMark(x: .value("Group", v.group), y: .value("Sets", v.sets))
                    .foregroundStyle(by: .value("Week", v.week))
                    .position(by: .value("Week", v.week))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Last week": Theme.textFaint, "This week": Theme.accent])
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textFaint)
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
            .chartLegend(position: .bottom)
            .frame(height: 200)
            Text("Primary muscle = 1 set, helper muscle = ½ set. Cardio not counted.")
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
        }
        .cardStyle()
    }

    private var prList: some View {
        let bests = TrainingStats.bests(sessions: sessions)
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Personal records", accent: true)
            ForEach(bests) { b in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.exercise.name.uppercased()).font(.display(18)).foregroundStyle(Theme.textPrimary)
                        Text(b.date.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.caption2).foregroundStyle(Theme.textFaint)
                    }
                    Spacer()
                    Text(b.headline).font(.display(20)).foregroundStyle(Theme.accent).monospacedDigit()
                }
                .padding(.vertical, 4)
                if b.id != bests.last?.id { Divider().overlay(Theme.stroke) }
            }
        }
        .cardStyle()
    }
}
