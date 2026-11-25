import SwiftUI

/// Admin-only (Firebase custom claim `admin`). Reports from users, plus jobs held by AI moderation.
struct ModerationQueueView: View {
    @Environment(MarketplaceStore.self) private var store
    @State private var reports: [Report] = []
    @State private var heldJobs: [JobPost] = []
    @State private var segment = 0

    var body: some View {
        List {
            Section {
                Picker("Queue", selection: $segment) {
                    Text("Reports (\(reports.count))").tag(0)
                    Text("Held by AI (\(heldJobs.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if segment == 0 {
                ForEach(reports) { report in
                    ReportRow(report: report) { action in
                        Task {
                            try? await store.backend.resolve(report, action: action)
                            withAnimation { reports.removeAll { $0.id == report.id } }
                        }
                    }
                }
            } else {
                ForEach(heldJobs) { job in
                    HeldJobRow(job: job) { approve in
                        Task {
                            try? await store.backend.moderate(job, approve: approve)
                            withAnimation { heldJobs.removeAll { $0.id == job.id } }
                        }
                    }
                }
            }
        }
        .overlay {
            if (segment == 0 ? reports.isEmpty : heldJobs.isEmpty) {
                ContentUnavailableView("All clear", systemImage: "checkmark.shield.fill", description: Text("Nothing waiting for review."))
            }
        }
        .navigationTitle("Moderation")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        reports = (try? await store.backend.openReports()) ?? []
        heldJobs = (try? await store.backend.jobsAwaitingReview()) ?? []
    }
}

struct VerdictChips: View {
    var verdict: ModerationVerdict

    var body: some View {
        FlowLayout {
            OutlineCapsule(text: "AI: \(verdict.decision.rawValue) · \(verdict.confidence.formatted(.percent.precision(.fractionLength(0))))",
                           symbol: "sparkles", gradient: Brand.gradient(for: verdict.decision == .block ? Brand.danger : Brand.warning))
            ForEach(verdict.categories, id: \.self) { SkillChip(text: $0.title) }
        }
    }
}

struct ReportRow: View {
    var report: Report
    var onAction: (ModerationAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(report.reason.title, systemImage: "flag.fill").font(.headline).foregroundStyle(Brand.danger)
                Spacer()
                Text(report.createdAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(report.targetKind.rawValue.capitalized) · “\(report.excerpt)”").font(.subheadline).lineLimit(3)
            if !report.details.isEmpty { Text(report.details).font(.caption).foregroundStyle(.secondary) }
            if let verdict = report.aiVerdict { VerdictChips(verdict: verdict) }
            HStack {
                Button("Dismiss") { onAction(.dismiss) }.buttonStyle(.glass)
                Spacer()
                Menu {
                    Button("Remove content", systemImage: "trash") { onAction(.removeContent) }
                    Button("Warn user", systemImage: "exclamationmark.bubble") { onAction(.warnUser) }
                    Button("Suspend user", systemImage: "person.fill.xmark", role: .destructive) { onAction(.suspendUser) }
                } label: {
                    Label("Take action", systemImage: "hammer.fill")
                }
                .buttonStyle(.gradientCapsule)
                .tint(Brand.danger)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

struct HeldJobRow: View {
    var job: JobPost
    var onDecision: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.title).font(.headline)
            Text(job.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
            Text("\(job.budget.formatted) · \(job.pricing.title)").font(.caption.weight(.semibold))
            if let verdict = job.moderation {
                VerdictChips(verdict: verdict)
                Text(verdict.rationale).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Remove", role: .destructive) { onDecision(false) }.buttonStyle(.glass)
                Spacer()
                Button("Approve") { onDecision(true) }.buttonStyle(.gradientCapsule)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}
