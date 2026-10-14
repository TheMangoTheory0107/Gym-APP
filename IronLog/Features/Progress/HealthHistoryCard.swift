import Charts
import SwiftUI

/// Steps for the last 7 days and workouts recorded by Apple Watch / Fitness / other apps.
struct HealthHistoryCard: View {
    var health = HealthData.shared

    var body: some View {
        if health.isConnected && (!health.weekSteps.isEmpty || !health.recentWorkouts.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "From Apple Health")
                    Spacer()
                    Image(systemName: "heart.fill").foregroundStyle(Theme.ember)
                }
                if !health.weekSteps.isEmpty {
                    let avg = health.weekSteps.reduce(0) { $0 + $1.1 } / Double(health.weekSteps.count)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Int(avg).formatted()).font(.display(30)).foregroundStyle(Theme.textPrimary)
                        Text("AVG STEPS / DAY").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textFaint)
                    }
                    Chart(health.weekSteps, id: \.0) { point in
                        BarMark(x: .value("Day", point.0, unit: .day), y: .value("Steps", point.1))
                            .foregroundStyle(point.1 >= 10_000 ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.textFaint))
                            .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 110)
                }
                if !health.recentWorkouts.isEmpty {
                    Divider().overlay(Theme.stroke)
                    ForEach(health.recentWorkouts.prefix(6)) { w in
                        HStack(spacing: 12) {
                            Image(systemName: w.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.ember)
                                .frame(width: 34, height: 34)
                                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(w.name.uppercased()).font(.display(18)).foregroundStyle(Theme.textPrimary)
                                Text("\(w.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(w.source)")
                                    .font(.caption).foregroundStyle(Theme.textFaint).lineLimit(1)
                            }
                            Spacer()
                            Text("\(w.minutes) MIN · \(w.kcal) KCAL").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .cardStyle()
        }
    }
}
