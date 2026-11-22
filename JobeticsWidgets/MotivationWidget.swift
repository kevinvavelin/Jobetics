import SwiftUI
import WidgetKit

struct MotivationEntry: TimelineEntry {
    var date: Date
    var line: String
    var score: Int
    var tier: String
}

struct MotivationProvider: TimelineProvider {
    func placeholder(in context: Context) -> MotivationEntry {
        MotivationEntry(date: .now, line: Motivation.line(), score: 92, tier: FreelancerScore.Tier.topRated.title)
    }

    func getSnapshot(in context: Context, completion: @escaping (MotivationEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MotivationEntry>) -> Void) {
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [entry(for: .now), entry(for: tomorrow)], policy: .atEnd))
    }

    private func entry(for date: Date) -> MotivationEntry {
        MotivationEntry(date: date, line: Motivation.line(for: date), score: SharedStore.score, tier: SharedStore.tier)
    }
}

struct MotivationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: MotivationEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Today", systemImage: "sparkles").font(.caption2.weight(.bold))
                Text(entry.line).font(.caption).lineLimit(3)
            }
        case .accessoryInline:
            Text(entry.line)
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                    Spacer()
                    if entry.score > 0 && family != .systemSmall {
                        Label("\(entry.score) · \(entry.tier)", systemImage: "gauge.with.dots.needle.67percent")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
                Text(entry.line)
                    .font(family == .systemSmall ? .subheadline.bold() : .title3.bold())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MotivationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MotivationWidget", provider: MotivationProvider()) { entry in
            MotivationWidgetView(entry: entry)
                .containerBackground(for: .widget) { Brand.gradient }
        }
        .configurationDisplayName("Daily motivation")
        .description("A new motivational line every morning.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
