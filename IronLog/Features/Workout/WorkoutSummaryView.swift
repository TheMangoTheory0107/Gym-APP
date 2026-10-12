import SwiftUI

/// Shown after tapping Finish: volume, duration, sets and any PRs.
struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("WORKOUT COMPLETE")
                        .font(.display(20))
                        .tracking(2)
                        .foregroundStyle(Theme.accent)
                    Text(summary.dayName.uppercased())
                        .font(.display(52))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .padding(.top, 20)

                VStack(spacing: 16) {
                    HStack {
                        StatTile(label: "Total volume", value: Fmt.volume(summary.volume), unit: "kg", highlight: true)
                        StatTile(label: "Duration", value: Fmt.duration(summary.duration))
                    }
                    HStack {
                        StatTile(label: "Sets", value: "\(summary.setCount)")
                        StatTile(label: "Exercises", value: "\(summary.exerciseCount)")
                    }
                }
                .cardStyle(padding: 18)

                if summary.records.isEmpty {
                    EmptyStateCard(icon: "flame.fill", title: "Work banked",
                                   message: "No new records this time. Beat today's numbers next week.")
                } else {
                    SectionLabel(text: "Personal records · \(summary.records.count)", accent: true)
                    ForEach(Array(summary.records.enumerated()), id: \.element.id) { index, pr in
                        HStack(spacing: 14) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pr.exerciseName.uppercased())
                                    .font(.display(20))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(pr.detail)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(pr.headline)
                                .font(.display(24))
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                        }
                        .cardStyle(padding: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1)
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15 * Double(index)), value: appeared)
                    }
                }

                Button("Done", action: onDone)
                    .buttonStyle(.primary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .onAppear {
            appeared = true
            if !summary.records.isEmpty { Haptics.success() }
        }
    }
}
