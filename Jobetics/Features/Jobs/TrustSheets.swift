import SwiftUI

/// Report a job, message, profile or review to the Jobetics moderation team.
struct ReportSheet: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var kind: ReportTargetKind
    var targetId: String
    var ownerId: String
    var excerpt: String
    @State private var reason: ReportReason = .spam
    @State private var details = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                }
                Section("What's wrong?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("Anything else we should know? (optional)", text: $details, axis: .vertical).lineLimit(3...6)
                } footer: {
                    Text("Reports are confidential. The person you report won't know it was you.")
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", role: .confirm) {
                        Task {
                            try? await store.report(kind, id: targetId, owner: ownerId, excerpt: excerpt, reason: reason, details: details)
                            sent = true
                            try? await Task.sleep(for: .seconds(1))
                            dismiss()
                        }
                    }
                }
            }
            .overlay {
                if sent {
                    Label("Thanks, our team will review it.", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .padding()
                        .glassEffect(.regular, in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring, value: sent)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Freelancers review employers: was the brief clear, was it spam, did they pay on time?
struct ReviewEmployerView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var job: JobPost
    @State private var clarity = 4
    @State private var communication = 4
    @State private var payment = 4
    @State private var overall = 4
    @State private var spam = false
    @State private var comment = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(job.title).font(.headline)
                }
                Section("Your ratings") {
                    rating("Was the brief clear?", $clarity)
                    rating("Communication", $communication)
                    rating("Fair & on-time payment", $payment)
                    rating("Overall", $overall)
                }
                Section {
                    Toggle("This job looked like spam or a scam", isOn: $spam)
                } footer: {
                    Text("Spam flags are reviewed by our moderation team and help protect other freelancers.")
                }
                Section("Comment") {
                    TextField("Share what went well and what could be better", text: $comment, axis: .vertical).lineLimit(3...8)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger) }
                }
            }
            .navigationTitle("Review employer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit", role: .confirm) {
                        let review = EmployerReview(id: UUID().uuidString, jobId: job.id, employerId: job.ownerId, reviewerId: store.me,
                                                    clarity: clarity, communication: communication, payment: payment, overall: overall,
                                                    markedAsSpam: spam, comment: comment, createdAt: .now)
                        Task {
                            do { try await store.submit(review: review); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }

    private func rating(_ title: LocalizedStringKey, _ value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        value.wrappedValue = star
                    } label: {
                        Image(systemName: star <= value.wrappedValue ? "star.fill" : "star")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: value.wrappedValue)
            .accessibilityElement()
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text("\(value.wrappedValue) of 5"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value.wrappedValue = min(5, value.wrappedValue + 1)
                case .decrement: value.wrappedValue = max(1, value.wrappedValue - 1)
                @unknown default: break
                }
            }
        }
    }
}
