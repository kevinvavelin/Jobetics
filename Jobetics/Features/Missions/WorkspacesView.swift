import SwiftData
import SwiftUI

/// Where the freelancer works. Checking in sets today's context: the day's expense (coworking pass)
/// and the place recorded on today's logged work.
struct WorkspacesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workspace.name) private var workspaces: [Workspace]
    @State private var editing: Workspace?

    var body: some View {
        List {
            Section {
                ForEach(workspaces) { workspace in
                    Button { editing = workspace } label: { WorkspaceRow(workspace: workspace) }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .leading) {
                            Button("Check in", systemImage: "mappin.and.ellipse") {
                                WorkspaceCheckIn.checkIn(workspace, context: context)
                            }
                            .tint(.accentColor)
                        }
                }
                .onDelete { offsets in offsets.map { workspaces[$0] }.forEach(context.delete) }
            } footer: {
                Text("Swipe right to check in. A daily cost, like a coworking pass, is added to your expenses once a day.")
            }
        }
        .navigationTitle("Workspaces")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New workspace", systemImage: "plus") {
                    let workspace = Workspace(name: "", kind: .coworking)
                    context.insert(workspace)
                    editing = workspace
                }
            }
        }
        .sheet(item: $editing) { WorkspaceEditor(workspace: $0) }
    }
}

struct WorkspaceRow: View {
    var workspace: Workspace

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workspace.kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.quaternary, in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name.isEmpty ? workspace.kind.title : workspace.name).font(.headline)
                Text(workspace.dayCostCents > 0 ? "\(workspace.kind.title) · \(Money(cents: workspace.dayCostCents).formatted)/day" : workspace.kind.title)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if workspace.isCheckedInToday {
                Label("Here today", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Brand.positive)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum WorkspaceCheckIn {
    static func checkIn(_ workspace: Workspace, context: ModelContext, now: Date = .now) {
        let alreadyToday = workspace.isCheckedInToday
        let all = (try? context.fetch(FetchDescriptor<Workspace>())) ?? []
        for other in all where other !== workspace && other.isCheckedInToday { other.lastCheckIn = nil }
        workspace.lastCheckIn = now
        if !alreadyToday && workspace.dayCostCents > 0 {
            let expense = Expense(date: now, title: workspace.name, amountCents: workspace.dayCostCents,
                                  category: workspace.kind == .coworking ? .coworking : .other,
                                  vatCents: Int((Double(workspace.dayCostCents) / 6).rounded()))
            context.insert(expense)
        }
        let start = Calendar.current.startOfDay(for: now)
        let end = start.addingTimeInterval(86_400)
        let logs = (try? context.fetch(FetchDescriptor<WorkLog>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        for log in logs where !log.isLocked {
            log.workspaceName = workspace.name
            log.onSite = workspace.kind == .clientSite
        }
    }
}

struct WorkspaceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var workspace: Workspace

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $workspace.name)
                Picker("Type", selection: $workspace.kind) {
                    ForEach(WorkspaceKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                TextField("Address", text: $workspace.address, axis: .vertical).textContentType(.fullStreetAddress)
                LabeledContent("Cost per day") {
                    TextField("Amount", value: Binding(get: { Double(workspace.dayCostCents) / 100 },
                                                       set: { workspace.dayCostCents = Int(($0 * 100).rounded()) }),
                              format: .currency(code: "EUR"))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle(workspace.name.isEmpty ? String(localized: "New workspace") : workspace.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        if workspace.name.isEmpty { workspace.name = workspace.kind.title }
                        dismiss()
                    }
                }
            }
        }
    }
}
