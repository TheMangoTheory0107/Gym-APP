import SwiftData
import SwiftUI

/// Daily supplement checklist with optional reminders and a creatine streak.
struct SupplementsCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SupplementCheck.takenAt, order: .reverse) private var checks: [SupplementCheck]
    @State private var reminders: [String: Bool] = [:]

    private let supplements = FoodDatabase.shared.supplements
    private var today: String { Date.now.dayKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Supplements", accent: true)
                Spacer()
                if let creatine = supplements.first(where: { $0.trackStreak == true }) {
                    let streak = Self.streak(for: creatine.id, checks: checks)
                    Label("\(streak) day\(streak == 1 ? "" : "s")", systemImage: "flame.fill")
                        .font(.display(18))
                        .foregroundStyle(streak > 0 ? Theme.accent : Theme.textFaint)
                        .accessibilityLabel("Creatine streak \(streak) days")
                }
            }

            ForEach(supplements) { s in
                let taken = checks.contains { $0.dayKey == today && $0.supplementId == s.id }
                HStack(spacing: 12) {
                    Button {
                        toggle(s, taken: taken)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                            .opacity(taken ? 1 : 0)
                            .frame(width: 40, height: 40)
                            .background(taken ? Theme.accent : Theme.cardRaised,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(taken ? .clear : Theme.stroke))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name.uppercased() + (s.optional == true ? " · OPTIONAL" : ""))
                            .font(.display(19))
                            .foregroundStyle(taken ? Theme.textSecondary : Theme.textPrimary)
                        Text("\(s.when) · \(String(format: "%d:%02d", s.hour, s.minute))")
                            .font(.caption)
                            .foregroundStyle(Theme.textFaint)
                    }
                    Spacer()
                    Button {
                        toggleReminder(s)
                    } label: {
                        Image(systemName: reminders[s.id] == true ? "bell.fill" : "bell.slash")
                            .foregroundStyle(reminders[s.id] == true ? Theme.accent : Theme.textFaint)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reminder for \(s.name)")
                }
            }
        }
        .cardStyle()
        .onAppear {
            for s in supplements { reminders[s.id] = UserDefaults.standard.bool(forKey: Self.reminderKey(s.id)) }
        }
    }

    static func reminderKey(_ id: String) -> String { "supp.reminder.\(id)" }

    private func toggle(_ s: SupplementDef, taken: Bool) {
        if taken {
            for c in checks where c.dayKey == today && c.supplementId == s.id { context.delete(c) }
            Haptics.tap()
        } else {
            context.insert(SupplementCheck(dayKey: today, supplementId: s.id))
            Haptics.success()
        }
        try? context.save()
    }

    private func toggleReminder(_ s: SupplementDef) {
        let on = !(reminders[s.id] ?? false)
        reminders[s.id] = on
        UserDefaults.standard.set(on, forKey: Self.reminderKey(s.id))
        let id = "supp-\(s.id)"
        if on {
            Task {
                await NotificationManager.shared.requestPermission()
                NotificationManager.shared.scheduleDaily(id: id, title: s.name.uppercased(), body: s.when,
                                                         hour: s.hour, minute: s.minute)
            }
        } else {
            NotificationManager.shared.cancel(id: id)
        }
        Haptics.select()
    }

    /// Consecutive days taken, counting back from today (or yesterday if today isn't ticked yet).
    static func streak(for id: String, checks: [SupplementCheck]) -> Int {
        let days = Set(checks.filter { $0.supplementId == id }.map(\.dayKey))
        var date = Date.now
        if !days.contains(date.dayKey) { date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date }
        var count = 0
        while days.contains(date.dayKey) {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }
}
