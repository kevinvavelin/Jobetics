import SwiftData
import SwiftUI

/// "Today": where you work, what you work on, and logging it in one tap.
struct TodayCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workspace.name) private var workspaces: [Workspace]
    @Query(filter: #Predicate<Mission> { $0.statusRaw == "active" }, sort: \Mission.endDate) private var missions: [Mission]

    private var checkedIn: Workspace? { workspaces.first(where: \.isCheckedInToday) }

    var body: some View {
        Card {
            HStack {
                Label("Today", systemImage: "sun.max.fill")
                    .font(.headline)
                Spacer()
                if let checkedIn {
                    Label(checkedIn.name, systemImage: checkedIn.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !workspaces.isEmpty {
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(workspaces) { workspace in
                                let selected = workspace.isCheckedInToday
                                Button {
                                    withAnimation(.snappy) { WorkspaceCheckIn.checkIn(workspace, context: context) }
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    Label(workspace.name, systemImage: workspace.kind.symbol)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .selectableCapsule(selected)
                                .accessibilityHint("Check in here today")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }

            if missions.isEmpty {
                Text("No active mission. Your pipeline and the web search are in Missions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(missions.prefix(3)) { mission in
                Divider()
                TodayMissionRow(mission: mission, onSite: checkedIn?.kind == .clientSite)
            }
        }
    }
}

private struct TodayMissionRow: View {
    @Environment(\.modelContext) private var context
    var mission: Mission
    var onSite: Bool

    private var today: WorkLog? { (mission.logs ?? []).first { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: mission) {
                HStack(spacing: 12) {
                    Image(systemName: mission.symbol)
                        .foregroundStyle(Color.named(mission.colorName))
                        .frame(width: 34, height: 34)
                        .background(Color.named(mission.colorName).opacity(0.14), in: .rect(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mission.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(mission.clientName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if mission.needsTravel && (onSite || mission.location == .onSite), mission.commuteMinutes > 0 {
                let arrival = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
                Label {
                    Text("\(Int(mission.commuteMinutes)) min by \(mission.transport.title.lowercased()) · leave by \(CommuteService.departureTime(arrival: arrival, commuteMinutes: mission.commuteMinutes).formatted(date: .omitted, time: .shortened))")
                } icon: {
                    Image(systemName: mission.transport.symbol)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if mission.billingMode != .hourly {
                HStack(spacing: 8) {
                    logButton("Full day", days: 1)
                    logButton("Half day", days: 0.5)
                    if today != nil && today?.isLocked == false {
                        Button("Clear", systemImage: "xmark") {
                            if let today { withAnimation { context.delete(today) } }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                    }
                }
                .controlSize(.small)
            } else {
                Stepper(value: Binding(get: { today?.hours ?? 0 }, set: setHours), in: 0...12, step: 0.5) {
                    Text("Today: \((today?.hours ?? 0).formatted()) h").font(.subheadline.monospacedDigit())
                }
            }
        }
    }

    private func logButton(_ title: LocalizedStringKey, days: Double) -> some View {
        let selected = today?.days == days
        return Button {
            withAnimation(.snappy) { log(days: days) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .selectableCapsule(selected)
        .disabled(today?.isLocked == true)
    }

    private func log(days: Double) {
        if let today {
            today.days = days
            today.hours = days * 7
            today.onSite = onSite || mission.location == .onSite
        } else {
            let entry = WorkLog(date: Calendar.current.startOfDay(for: .now), days: days, onSite: onSite || mission.location == .onSite)
            entry.mission = mission
            context.insert(entry)
        }
    }

    private func setHours(_ hours: Double) {
        if let today {
            if hours == 0 { context.delete(today) } else { today.hours = hours }
        } else if hours > 0 {
            let entry = WorkLog(date: Calendar.current.startOfDay(for: .now), days: 0, hours: hours)
            entry.mission = mission
            context.insert(entry)
        }
    }
}

/// Calm, early notice when a long mission ends and the pipeline is thin.
struct RunwayCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppRouter.self) private var router
    @Query(sort: \Mission.endDate) private var missions: [Mission]

    var body: some View {
        let pipeline = missions.filter { $0.status.isPipeline }
        if let ending = missions.first(where: { $0.status == .active && $0.isLong && $0.daysRemaining <= settings.settings.endOfMissionWarningDays }) {
            Card {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(Brand.warning)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(ending.title) ends in ^[\(ending.daysRemaining) day](inflect: true)")
                            .font(.headline)
                        Text(pipeline.isEmpty
                             ? String(localized: "Your pipeline is empty. There's time: a few calm searches this week are enough.")
                             : String(localized: "\(pipeline.count) leads in your pipeline. Follow up on one this week."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button(pipeline.isEmpty ? "Find missions" : "Open pipeline") { router.tab = .missions }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

/// Gentle nudge when the week gets too long.
struct WellbeingCard: View {
    @Environment(SettingsStore.self) private var settings
    @Query private var logs: [WorkLog]

    var body: some View {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now)
        let hours = logs.filter { week?.contains($0.date) == true }.reduce(0) { $0 + $1.hours }
        if hours > settings.settings.weeklyHoursCap {
            Card {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(hours.formatted()) hours this week").font(.headline)
                        Text("That's above your \(settings.settings.weeklyHoursCap.formatted())-hour limit. Your clients need you rested more than tired.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "leaf.fill").foregroundStyle(Brand.positive)
                }
            }
        }
    }
}

/// "What made today meaningful?" One line in the journal.
struct MeaningCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var editing: JournalEntry?

    var body: some View {
        let today = entries.first { Calendar.current.isDateInToday($0.date) }
        let last = entries.first { !$0.impact.isEmpty }
        Button {
            if let today { editing = today } else {
                let entry = JournalEntry(text: "")
                context.insert(entry)
                editing = entry
            }
        } label: {
            Card {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: today == nil ? "heart.text.square" : "heart.text.square.fill")
                        .font(.title2)
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(today == nil ? "What made today meaningful?" : "Today's journal").font(.headline)
                        Text(today?.impact.isEmpty == false ? today!.impact
                             : last.map { String(localized: "Last time: \($0.impact)") }
                             ?? String(localized: "One line about who your work helped. Only you can read it."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "square.and.pencil").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $editing) { JournalEditorView(entry: $0) }
    }
}
