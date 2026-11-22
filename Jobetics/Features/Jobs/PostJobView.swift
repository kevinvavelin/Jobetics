import SwiftUI

/// Any registered user can post a job. Every job must be paid, and every post is
/// reviewed by Gemini before it goes live.
struct PostJobView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var summary = ""
    @State private var discipline: Discipline = .design
    @State private var skills: [String] = []
    @State private var newSkill = ""
    @State private var pricing: Pricing = .fixed
    @State private var budget: Double = 0
    @State private var startDate = Date.now.addingTimeInterval(86_400 * 7)
    @State private var dueDate = Date.now.addingTimeInterval(86_400 * 30)
    @State private var isRemote = true
    @State private var phase: Phase = .editing

    enum Phase: Equatable { case editing, checking, published, inReview(String), rejected(String), invalid(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section("The job") {
                    TextField("Title", text: $title)
                    TextField("Describe the work, deliverables and context", text: $summary, axis: .vertical)
                        .lineLimit(5...10)
                    Picker("Discipline", selection: $discipline) {
                        ForEach(Discipline.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section {
                    FlowLayout {
                        ForEach(skills, id: \.self) { skill in
                            Button { skills.removeAll { $0 == skill } } label: {
                                Label(skill, systemImage: "xmark").labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    TextField("Add a skill", text: $newSkill)
                        .onSubmit(addSkill)
                        .submitLabel(.done)
                } header: {
                    Text("Skills")
                } footer: {
                    Text("We use skills to recommend matching freelancers and notify them.")
                }
                Section {
                    Picker("Pricing", selection: $pricing) {
                        ForEach(Pricing.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(pricing == .hourly ? "Hourly rate" : "Budget", value: $budget, format: .currency(code: "EUR"))
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Budget")
                } footer: {
                    Label("Every job on Jobetics is paid. Unpaid, \"exposure\" or free test work is not allowed.", systemImage: "eurosign.circle")
                }
                Section("Timing") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("Due", selection: $dueDate, in: startDate..., displayedComponents: .date)
                    Toggle("Remote", isOn: $isRemote)
                }
                statusSection
            }
            .navigationTitle("Post a job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish", role: .confirm, action: publish).disabled(phase == .checking)
                }
            }
            .interactiveDismissDisabled(phase == .checking)
        }
    }

    @ViewBuilder private var statusSection: some View {
        switch phase {
        case .editing: EmptyView()
        case .checking:
            Section { Label { Text("Checking your post…") } icon: { ProgressView() } }
        case .published:
            Section { Label("Your job is live. We'll notify matching freelancers.", systemImage: "checkmark.seal.fill").foregroundStyle(Brand.positive) }
        case .inReview(let reason):
            Section { Label(reason, systemImage: "hourglass").foregroundStyle(Brand.warning) }
        case .rejected(let reason), .invalid(let reason):
            Section { Label(reason, systemImage: "exclamationmark.octagon.fill").foregroundStyle(Brand.danger) }
        }
    }

    private func addSkill() {
        let skill = newSkill.trimmingCharacters(in: .whitespaces)
        if !skill.isEmpty && !skills.contains(skill) { skills.append(skill) }
        newSkill = ""
    }

    private func publish() {
        addSkill()
        let job = JobPost(id: UUID().uuidString, ownerId: store.me, title: title, summary: summary, discipline: discipline,
                          skills: skills, budget: Money(budget), pricing: pricing, startDate: startDate, dueDate: dueDate,
                          isRemote: isRemote, status: .pendingReview, createdAt: .now, proposalCount: 0,
                          employer: .new, moderation: nil)
        phase = .checking
        Task {
            do {
                switch try await store.publish(job) {
                case .published:
                    phase = .published
                    try? await Task.sleep(for: .seconds(1.2))
                    dismiss()
                case .inReview(let reason): phase = .inReview(reason)
                case .rejected(let reason): phase = .rejected(reason)
                }
            } catch {
                phase = .invalid(error.localizedDescription)
            }
        }
    }
}
