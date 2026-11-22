import SwiftUI

struct WatchFocusView: View {
    @Environment(WatchFocusTimer.self) private var timer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.session.isIdle ? timer.total : timer.session.remaining(at: context.date)
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: 1 - remaining / timer.total)
                        .stroke(timer.session.phase.isBreak ? AnyShapeStyle(Color.teal) : AnyShapeStyle(Brand.angular),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(Duration.seconds(remaining.rounded(.up)), format: .time(pattern: .minuteSecond))
                            .font(.system(.title, design: .rounded).monospacedDigit().bold())
                        Text(timer.session.phase.title).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(timer.session.isRunning ? "Pause" : "Start",
                           systemImage: timer.session.isRunning ? "pause.fill" : "play.fill") { timer.toggle() }
                        .tint(Brand.indigo)
                    Button("Skip", systemImage: "forward.end.fill") { timer.skip() }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Focus")
        .containerBackground(Brand.indigo.gradient.opacity(0.4), for: .tabView)
    }
}

struct WatchMotivationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Brand.cyan)
            Text(Motivation.line()).font(.headline)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .containerBackground(Brand.gradient, for: .tabView)
    }
}

struct WatchScoreView: View {
    @Environment(WatchFocusTimer.self) private var timer

    var body: some View {
        let score = SharedStore.score
        VStack(spacing: 6) {
            Gauge(value: Double(score), in: 0...100) {
                Text("Score")
            } currentValueLabel: {
                Text(score, format: .number)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Brand.angular)
            .scaleEffect(1.4)
            .padding(.vertical, 16)
            Text(SharedStore.tier).font(.headline)
            Text("\(timer.completedToday) focus sessions today").font(.caption2).foregroundStyle(.secondary)
        }
        .containerBackground(Brand.violet.gradient.opacity(0.4), for: .tabView)
    }
}
