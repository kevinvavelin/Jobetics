import SwiftData
import SwiftUI

/// All missions: what's running now, what's coming (pipeline) and what's done.
struct MissionsView: View {
    var embedded = false

    var body: some View {
        if embedded { MissionsContent() } else { NavigationStack { MissionsContent() } }
    }
}

struct MissionsContent: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Mission.endDate) private var missions: [Mission]
    @State private var scope: Scope = .active
    @State private var editing: Mission?
    @State private var query = ""

    enum Scope: String, CaseIterable, Identifiable {
        case active, pipeline, past
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .active: "Active"
            case .pipeline: "Pipeline"
            case .past: "Past"
            }
        }
    }

    private var filtered: [Mission] {
        missions.filter { mission in
            let inScope = switch scope {
            case .active: mission.status == .active || mission.status == .paused
            case .pipeline: mission.status.isPipeline
            case .past: mission.status == .done || mission.status == .lost
            }
            return inScope && (query.isEmpty || mission.title.localizedStandardContains(query)
                               || mission.clientName.localizedStandardContains(query))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if scope == .active {
                let long = filtered.filter(\.isLong)
                let short = filtered.filter { !$0.isLong }
                if !long.isEmpty {
                    Section("Long missions") { rows(long) }
                }
                if !short.isEmpty {
                    Section("Short missions") { rows(short) }
                }
            } else {
                Section { rows(filtered) }
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView {
                    Label(scope == .pipeline ? "No leads yet" : "No missions", systemImage: scope == .pipeline ? "sparkle.magnifyingglass" : "briefcase")
                } description: {
                    Text(scope == .pipeline ? "Save missions you find on the web or through referrals to follow them calmly."
                                            : "Add your first mission to track time, travel and invoices in one place.")
                } actions: {
                    Button("New mission") { editing = newMission() }.buttonStyle(.gradientCapsule)
                }
            }
        }
        .searchable(text: $query, prompt: "Missions, clients")
        .navigationTitle("Missions")
        .navigationDestination(for: Mission.self) { MissionDetailView(mission: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("More", systemImage: "ellipsis") {
                    NavigationLink { BoardView(embedded: true) } label: { Label("Task board", systemImage: "rectangle.split.3x1") }
                    NavigationLink { ClientsView() } label: { Label("Clients", systemImage: "person.2") }
                    NavigationLink { WorkspacesView() } label: { Label("Workspaces", systemImage: "building.2") }
                    NavigationLink { JobCalendarView() } label: { Label("Calendar", systemImage: "calendar") }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New mission", systemImage: "plus") { editing = newMission() }
            }
        }
        .sheet(item: $editing) { MissionEditorView(mission: $0) }
    }

    private func rows(_ list: [Mission]) -> some View {
        ForEach(list) { mission in
            NavigationLink(value: mission) { MissionRow(mission: mission) }
        }
        .onDelete { offsets in offsets.map { list[$0] }.forEach(context.delete) }
    }

    private func newMission() -> Mission {
        let mission = Mission(title: "", status: scope == .pipeline ? .lead : .active, rateCents: 0, startDate: .now,
                              endDate: .now.addingTimeInterval(86_400 * 30))
        context.insert(mission)
        return mission
    }
}

struct MissionRow: View {
    var mission: Mission

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mission.symbol)
                .font(.headline)
                .foregroundStyle(Color.named(mission.colorName))
                .frame(width: 40, height: 40)
                .background(Color.named(mission.colorName).opacity(0.14), in: .rect(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(mission.title.isEmpty ? String(localized: "New mission") : mission.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !mission.clientName.isEmpty { Text(mission.clientName) }
                    Image(systemName: mission.location.symbol).accessibilityLabel(mission.location.title)
                    if !mission.source.isEmpty && mission.status.isPipeline { Text("· \(mission.source)") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if mission.status == .active, mission.estimatedDays > 0 {
                    ProgressView(value: min(mission.daysLogged / mission.estimatedDays, 1))
                        .tint(Color.named(mission.colorName))
                        .accessibilityLabel("Progress")
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(mission.rate.formatted)/\(mission.billingMode.unit)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if mission.status == .active {
                    Text(mission.daysRemaining == 0 ? "Ends today" : "^[\(mission.daysRemaining) day](inflect: true) left")
                        .font(.caption)
                        .foregroundStyle(mission.daysRemaining < 30 ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(.secondary))
                } else {
                    Label(mission.status.title, systemImage: mission.status.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
