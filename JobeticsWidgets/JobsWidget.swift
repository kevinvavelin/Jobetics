import SwiftUI
import WidgetKit

struct JobsEntry: TimelineEntry {
    var date: Date
    var count: Int
    var jobs: [JobSnapshot]
}

struct JobsProvider: TimelineProvider {
    static let sample = JobsEntry(date: .now, count: 12, jobs: [
        JobSnapshot(id: "1", title: "Redesign our iOS banking app for Liquid Glass", disciplineSymbol: "paintpalette.fill", budget: "€9,500", postedAt: .now),
        JobSnapshot(id: "2", title: "Design system lead for a health startup", disciplineSymbol: "paintpalette.fill", budget: "€90/h", postedAt: .now),
        JobSnapshot(id: "3", title: "Build interactive widgets & a watchOS companion", disciplineSymbol: "chevron.left.forwardslash.chevron.right", budget: "€12,000", postedAt: .now),
    ])

    func placeholder(in context: Context) -> JobsEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping (JobsEntry) -> Void) {
        completion(context.isPreview || SharedStore.matchedJobs.isEmpty ? Self.sample : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JobsEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(1800))))
    }

    private func current() -> JobsEntry {
        JobsEntry(date: .now, count: SharedStore.openJobCount, jobs: SharedStore.matchedJobs)
    }
}

struct JobsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: JobsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "briefcase.fill").font(.title3).foregroundStyle(Brand.gradient)
                Spacer()
                Text(entry.count, format: .number).font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("jobs for you").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "jobetics://jobs"))
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Matched for you", systemImage: "briefcase.fill").font(.caption.weight(.bold)).foregroundStyle(Brand.gradient)
                    Spacer()
                    Text("\(entry.count) open").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(entry.jobs.prefix(family == .systemLarge ? 5 : 2)) { job in
                    Link(destination: URL(string: "jobetics://jobs/\(job.id)")!) {
                        HStack(spacing: 10) {
                            Image(systemName: job.disciplineSymbol)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Brand.gradient, in: .rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(job.title).font(.caption.weight(.semibold)).lineLimit(1)
                                Text(job.budget).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct JobsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JobsWidget", provider: JobsProvider()) { entry in
            JobsWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Jobs for you")
        .description("New paid jobs matching your skills.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
