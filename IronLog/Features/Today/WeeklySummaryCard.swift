import SwiftUI

/// This week (Mon–Sun) at a glance: which days were trained, total sets and volume.
struct WeeklySummaryCard: View {
    let sessions: [WorkoutSession]

    private var weekStart: Date { WorkoutStats.startOfWeek() }

    private var thisWeek: [WorkoutSession] {
        sessions.filter { $0.isFinished && $0.startedAt >= weekStart }
    }

    /// Calendar weekdays (1 = Sun … 7 = Sat) of split days completed this week.
    private var doneWeekdays: Set<Int> { Set(thisWeek.map(\.splitWeekday)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "This week", accent: true)

            HStack(spacing: 6) {
                ForEach([2, 3, 4, 5, 6, 7], id: \.self) { weekday in
                    let done = doneWeekdays.contains(weekday)
                    VStack(spacing: 4) {
                        Image(systemName: done ? "checkmark" : "minus")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(done ? Color.white : Theme.textFaint)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(done ? Theme.accent : Theme.cardRaised,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(String(Catalog.weekdayNames[weekday - 1].prefix(3)).uppercased())
                            .font(.display(14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            HStack {
                StatTile(label: "Workouts", value: "\(thisWeek.count)/6", highlight: true)
                StatTile(label: "Sets", value: "\(thisWeek.reduce(0) { $0 + $1.sets.count })")
                StatTile(label: "Volume", value: Fmt.volume(thisWeek.reduce(0) { $0 + $1.totalVolume }), unit: "kg")
            }
        }
        .cardStyle(padding: 18)
    }
}
