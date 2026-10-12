import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let workoutName: String
    let kcalLeft: Int?
    let proteinLeft: Int?
    let workoutDone: Bool
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, workoutName: "Chest & Abs", kcalLeft: 1450, proteinLeft: 96, workoutDone: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 + 60)
        // Refresh at midnight for the new day's workout; the app also reloads after each log.
        completion(Timeline(entries: [entry(for: now)], policy: .after(min(midnight, now.addingTimeInterval(3600)))))
    }

    private func entry(for date: Date) -> TodayEntry {
        let planned = WidgetSnapshot.plannedWorkout(on: date)
        if let s = WidgetSnapshot.load(), Calendar.current.isDate(s.date, inSameDayAs: date) {
            return TodayEntry(date: date, workoutName: s.workoutName.isEmpty ? planned : s.workoutName,
                              kcalLeft: s.kcalLeft, proteinLeft: s.proteinLeft, workoutDone: s.workoutDone)
        }
        // New day (or no shared data): full targets left.
        let shared = WidgetSnapshot.load() != nil
        return TodayEntry(date: date, workoutName: planned, kcalLeft: shared ? 2400 : nil,
                          proteinLeft: shared ? 180 : nil, workoutDone: false)
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.workoutDone ? "DONE TODAY" : "TODAY")
                .font(WStyle.display(13))
                .tracking(1.5)
                .foregroundStyle(WStyle.accent)
            Text((entry.workoutName.isEmpty ? "Rest" : entry.workoutName).uppercased())
                .font(WStyle.display(family == .systemSmall ? 24 : 28))
                .foregroundStyle(WStyle.text)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let kcal = entry.kcalLeft, let protein = entry.proteinLeft {
                HStack(spacing: 14) {
                    stat("\(kcal)", "KCAL LEFT")
                    stat("\(protein)g", "PROTEIN LEFT", highlight: true)
                }
            } else {
                Text("Open Iron Log to log meals")
                    .font(.caption2)
                    .foregroundStyle(WStyle.dim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WStyle.background, for: .widget)
    }

    private func stat(_ value: String, _ label: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(WStyle.display(22))
                .foregroundStyle(highlight ? WStyle.accent : WStyle.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(WStyle.dim)
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Today's workout and calories / protein left.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
