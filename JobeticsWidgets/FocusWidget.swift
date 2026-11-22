import AppIntents
import SwiftUI
import WidgetKit

struct FocusEntry: TimelineEntry {
    var date: Date
    var session: FocusSession
    var completed: Int
    var goal: Int
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: .now, session: FocusSession(), completed: 3, goal: 8)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) { completion(current()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let entry = current()
        // Refresh right after the running phase ends so the widget flips back to "Start".
        let refresh = entry.session.endDate.map { $0.addingTimeInterval(1) } ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func current() -> FocusEntry {
        FocusEntry(date: .now, session: SharedStore.focusSession, completed: SharedStore.focusCompletedToday,
                   goal: SharedStore.focusSettings.dailyGoal)
    }
}

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FocusEntry

    private var running: Bool { (entry.session.endDate ?? .distantPast) > entry.date }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.completed), in: 0...Double(max(1, entry.goal))) {
                Image(systemName: "timer")
            } currentValueLabel: {
                Text(entry.completed, format: .number)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(URL(string: "jobetics://focus"))
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: entry.session.phase.symbol).foregroundStyle(Brand.gradient)
                    Text(entry.session.phase.title).font(.caption.weight(.bold))
                    Spacer()
                }
                Spacer(minLength: 0)
                if running, let end = entry.session.endDate {
                    Text(timerInterval: entry.date...end, countsDown: true)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    if let task = entry.session.taskTitle {
                        Text(task).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text("\(entry.completed)/\(entry.goal)")
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    Button(intent: StartFocusIntent()) {
                        Label("Start focus", systemImage: "play.fill").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.indigo)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusWidget", provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Focus timer")
        .description("Start a Pomodoro and follow your daily focus goal.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

/// Control Center / Lock Screen / Action button control.
struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "fr.vavelinkevin.Jobetics.FocusControl") {
            ControlWidgetButton(action: StartFocusIntent()) {
                Label("Start Focus", systemImage: "timer")
            }
        }
        .displayName("Start Focus")
        .description("Start a Jobetics Pomodoro session.")
    }
}
