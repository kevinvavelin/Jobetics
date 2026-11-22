import ActivityKit
import SwiftUI
import WidgetKit

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            HStack(spacing: 16) {
                ZStack {
                    ProgressView(timerInterval: context.state.startDate...context.state.endDate, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: context.state.phase.symbol)
                    }
                    .progressViewStyle(.circular)
                    .tint(context.state.phase.isBreak ? .teal : Brand.cyan)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.phase.title).font(.headline)
                    Text(context.attributes.taskTitle ?? String(localized: "Deep work"))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text("\(context.state.completedToday)/\(context.attributes.dailyGoal) today")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.35))
            .widgetURL(URL(string: "jobetics://focus"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phase.title, systemImage: context.state.phase.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.phase.isBreak ? .teal : Brand.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                        .font(.title3.monospacedDigit().bold())
                        .frame(maxWidth: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(timerInterval: context.state.startDate...context.state.endDate, countsDown: true) {
                            Text(context.attributes.taskTitle ?? String(localized: "Deep work")).font(.caption)
                        } currentValueLabel: { EmptyView() }
                        .tint(context.state.phase.isBreak ? .teal : Brand.cyan)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase.symbol).foregroundStyle(context.state.phase.isBreak ? .teal : Brand.cyan)
            } compactTrailing: {
                Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Brand.cyan)
            }
            .widgetURL(URL(string: "jobetics://focus"))
        }
    }
}
