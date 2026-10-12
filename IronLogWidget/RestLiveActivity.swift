import ActivityKit
import SwiftUI
import WidgetKit

/// Rest countdown on the Lock Screen and in the Dynamic Island.
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            LockScreenRestView(state: context.state, workout: context.attributes.workoutName)
                .activityBackgroundTint(WStyle.background)
                .activitySystemActionForegroundColor(WStyle.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("REST", systemImage: "timer")
                        .font(WStyle.display(18))
                        .foregroundStyle(WStyle.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state.endDate)
                        .font(WStyle.display(30))
                        .foregroundStyle(WStyle.text)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("NEXT: \(context.state.nextUp.uppercased())")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WStyle.dim)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(WStyle.accent)
            } compactTrailing: {
                countdown(context.state.endDate)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(WStyle.text)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(WStyle.accent)
            }
            .keylineTint(WStyle.accent)
        }
    }
}

/// Self-updating countdown text (the system animates it; no app updates needed).
@ViewBuilder
func countdown(_ end: Date) -> some View {
    let now = Date.now
    Text(timerInterval: min(now, end)...end, countsDown: true)
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
}

private struct LockScreenRestView: View {
    let state: RestActivityAttributes.ContentState
    let workout: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REST · \(workout.uppercased())")
                    .font(WStyle.display(15))
                    .tracking(1)
                    .foregroundStyle(WStyle.accent)
                    .lineLimit(1)
                countdown(state.endDate)
                    .font(WStyle.display(46))
                    .foregroundStyle(WStyle.text)
                    .multilineTextAlignment(.leading)
                Text("NEXT: \(state.nextUp.uppercased())")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WStyle.dim)
                    .lineLimit(1)
            }
            Spacer()
            ProgressView(timerInterval: min(Date.now, state.endDate)...state.endDate, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(WStyle.accent)
            .frame(width: 54, height: 54)
        }
        .padding(16)
    }
}
