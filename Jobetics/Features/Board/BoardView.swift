import SwiftData
import SwiftUI

/// Kanban board of tasks, one board per project. Drag cards between columns.
struct BoardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.dueDate) private var projects: [Project]
    @State private var selectedID: PersistentIdentifier?
    @State private var newTaskStatus: TaskStatus?
    @State private var showsNewProject = false
    /// Pushed inside another navigation stack (Missions on iPhone).
    var embedded = false

    private var project: Project? { projects.first { $0.persistentModelID == selectedID } ?? projects.first }

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
            VStack(spacing: 0) {
                projectPicker
                if let project {
                    board(for: project)
                } else {
                    ContentUnavailableView {
                        Label("No projects yet", systemImage: "rectangle.split.3x1")
                    } actions: {
                        Button("New project") { showsNewProject = true }.buttonStyle(.gradientCapsule)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(project?.name ?? String(localized: "Board"))
            .navigationSubtitle(project.map { "\($0.clientName) · \($0.progress.formatted(.percent.precision(.fractionLength(0))))" } ?? "")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New project", systemImage: "folder.badge.plus") { showsNewProject = true }
                }
            }
            .sheet(item: $newTaskStatus) { status in
                if let project { NewTaskSheet(project: project, status: status) }
            }
            .sheet(isPresented: $showsNewProject) { NewProjectSheet() }
    }

    private var projectPicker: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(projects) { p in
                        let selected = p.persistentModelID == project?.persistentModelID
                        Button {
                            withAnimation(.snappy) { selectedID = p.persistentModelID }
                        } label: {
                            Label(p.name, systemImage: p.symbol)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .selectableCapsule(selected, gradient: Brand.gradient(for: Color.named(p.colorName)))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func board(for project: Project) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(TaskStatus.allCases) { status in
                    BoardColumn(project: project, status: status) { newTaskStatus = status }
                        .containerRelativeFrame(.horizontal, count: sizeClass == .regular ? 4 : 10, span: sizeClass == .regular ? 1 : 8, spacing: 14)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
            .padding(.bottom)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }
}

extension TaskStatus: Transferable {
    static var transferRepresentation: some TransferRepresentation { ProxyRepresentation(exporting: \.rawValue) }
}

struct BoardColumn: View {
    @Environment(\.modelContext) private var context
    var project: Project
    var status: TaskStatus
    var onAdd: () -> Void
    @State private var isTargeted = false

    private var tasks: [BoardTask] { project.sortedTasks.filter { $0.status == status } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(status.title, systemImage: status.symbol).font(.headline)
                Text(tasks.count, format: .number)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                Spacer()
                Button("Add task", systemImage: "plus", action: onAdd)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        TaskCard(task: task)
                            .draggable(task.persistentModelID.hashValue.description) {
                                TaskCard(task: task).frame(width: 260).opacity(0.9)
                            }
                            .contextMenu {
                                ForEach(TaskStatus.allCases.filter { $0 != status }) { target in
                                    Button("Move to \(target.title)", systemImage: target.symbol) { move(task, to: target) }
                                }
                                Divider()
                                Button("Delete", systemImage: "trash", role: .destructive) { context.delete(task) }
                            }
                    }
                }
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(isTargeted ? Brand.indigo.opacity(0.12) : Color(.tertiarySystemFill).opacity(0.5), in: .rect(cornerRadius: 22, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let key = items.first,
                  let task = project.tasks?.first(where: { $0.persistentModelID.hashValue.description == key }) else { return false }
            move(task, to: status)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func move(_ task: BoardTask, to status: TaskStatus) {
        withAnimation(.snappy) {
            task.status = status
            task.order = (project.sortedTasks.last?.order ?? 0) + 1
        }
    }
}

struct TaskCard: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(AppRouter.self) private var router
    var task: BoardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.subheadline.weight(.semibold))
                .strikethrough(task.status == .done, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let due = task.dueDate {
                    Label(due.formatted(.dateTime.day().month(.abbreviated)), systemImage: "calendar")
                        .foregroundStyle(due < .now && task.status != .done ? Brand.danger : .secondary)
                }
                if task.estimateHours > 0 {
                    Label("\(task.estimateHours.formatted())h", systemImage: "clock")
                }
                if task.focusSessions > 0 {
                    Label("\(task.focusSessions)", systemImage: "timer")
                }
                Spacer()
                if task.status != .done {
                    Button("Focus", systemImage: "play.fill") {
                        focus.reset()
                        focus.start(.focus, task: task.title)
                        task.focusSessions += 1
                        router.sheet = .focus
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption2)
                    .buttonStyle(.glass)
                    .controlSize(.mini)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color.named(task.project?.colorName ?? "")).frame(width: 3).padding(.vertical, 12)
        }
    }
}

struct NewTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var project: Project
    var status: TaskStatus
    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Date.now.addingTimeInterval(86_400 * 3)
    @State private var estimate: Double = 2

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $title)
                Toggle("Due date", isOn: $hasDue)
                if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                Stepper("Estimate: \(estimate.formatted())h", value: $estimate, in: 0.5...40, step: 0.5)
            }
            .navigationTitle(status.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) {
                        let task = BoardTask(title: title, status: status, order: (project.sortedTasks.last?.order ?? 0) + 1,
                                             dueDate: hasDue ? due : nil, estimateHours: estimate)
                        task.project = project
                        context.insert(task)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct NewProjectSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var client = ""
    @State private var color = "blue"
    @State private var due = Date.now.addingTimeInterval(86_400 * 30)
    private let colors = ["blue", "indigo", "purple", "pink", "orange", "teal", "green", "mint"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $name)
                TextField("Client", text: $client)
                DatePicker("Deadline", selection: $due, displayedComponents: .date)
                Picker("Color", selection: $color) {
                    ForEach(colors, id: \.self) { c in
                        Label { Text(c.capitalized) } icon: { Image(systemName: "circle.fill").foregroundStyle(Color.named(c)) }.tag(c)
                    }
                }
            }
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", role: .confirm) {
                        context.insert(Project(name: name, clientName: client, colorName: color, symbol: "folder.fill",
                                               startDate: .now, dueDate: due, budgetCents: 0))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
