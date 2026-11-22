import Foundation
import Observation
import WidgetKit

/// App-wide marketplace state. Views read from it; every write goes through moderation first.
@Observable
final class MarketplaceStore {
    enum Mode: String, CaseIterable, Identifiable {
        case freelancer, hiring
        var id: String { rawValue }
        var title: String { self == .freelancer ? String(localized: "Freelancing") : String(localized: "Hiring") }
    }

    let backend: MarketplaceBackend
    let moderation: ModerationService

    var account: UserAccount?
    var profile: PublicProfile?
    var openJobs: [JobPost] = []
    var myJobs: [JobPost] = []
    var conversations: [Conversation] = []
    var blocked: Set<String> = []
    var isAdmin = false
    var isLoading = false
    var mode: Mode = .freelancer
    var lastError: String?

    init(backend: MarketplaceBackend, moderation: ModerationService) {
        self.backend = backend
        self.moderation = moderation
    }

    var me: String { backend.userID ?? "" }
    var isFreelancer: Bool { account?.isFreelancer == true }
    var unreadCount: Int { conversations.reduce(0) { $0 + ($1.unread[me] ?? 0) } }

    /// Jobs matching the freelancer's skills, best first.
    var matchedJobs: [JobPost] {
        guard let profile else { return openJobs }
        let skills = Set(profile.skills.map { $0.lowercased() })
        return openJobs.sorted { a, b in
            let sa = Set(a.skills.map { $0.lowercased() }).intersection(skills).count + (a.discipline == profile.discipline ? 2 : 0)
            let sb = Set(b.skills.map { $0.lowercased() }).intersection(skills).count + (b.discipline == profile.discipline ? 2 : 0)
            return sa == sb ? a.createdAt > b.createdAt : sa > sb
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            account = try await backend.account()
            if let id = backend.userID { profile = try await backend.publicProfile(id) }
            if account?.isFreelancer != true { mode = .hiring }
            async let open = isFreelancer ? backend.openJobs() : []
            async let mine = backend.jobs(postedBy: me)
            (openJobs, myJobs) = try await (open, mine)
            isAdmin = await backend.isAdmin()
            blocked = (try? await backend.blockedUsers()) ?? []
            publishToWidgets()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func observeConversations() async {
        for await list in backend.conversations() {
            conversations = list.filter { $0.participantIds.allSatisfy { !blocked.contains($0) } }
        }
    }

    private func publishToWidgets() {
        guard !LaunchOptions.isDemo || LaunchOptions.isScreenshotRun else { return }
        SharedStore.matchedJobs = matchedJobs.prefix(4).map(\.snapshot)
        SharedStore.openJobCount = openJobs.count
        if let score = profile?.score {
            SharedStore.score = score.overall
            SharedStore.tier = score.tier.title
            WatchSync.shared.send(score: score.overall, tier: score.tier.title, openJobs: openJobs.count)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Writes (moderated)

    enum PublishOutcome { case published, inReview(String), rejected(String) }

    func publish(_ draft: JobPost) async throws -> PublishOutcome {
        try draft.validate()
        var job = draft
        let verdict = await moderation.review(.job(job))
        job.moderation = verdict
        switch verdict.decision {
        case .block: return .rejected(verdict.rationale)
        case .review: job.status = .pendingReview
        case .allow: job.status = .open
        }
        try await backend.publish(job)
        myJobs.insert(job, at: 0)
        return job.status == .open ? .published : .inReview(verdict.rationale)
    }

    func submitProposal(to job: JobPost, note: String, price: Money) async throws {
        guard isFreelancer else { throw BackendError.notFreelancer }
        let verdict = await moderation.review(.proposal(note))
        if verdict.decision == .block { throw BackendError.rejected(verdict.rationale) }
        let proposal = Proposal(id: UUID().uuidString, jobId: job.id, freelancerId: me, note: note,
                                price: price, status: .sent, createdAt: .now)
        try await backend.submit(proposal)
        if let i = openJobs.firstIndex(where: { $0.id == job.id }) { openJobs[i].proposalCount += 1 }
    }

    /// Sends a chat message. Personal details are redacted until contact is mutually accepted.
    @discardableResult
    func send(_ text: String, in conversation: Conversation, contactUnlocked: Bool) async throws -> Bool {
        let verdict = await moderation.review(.message(text, contactUnlocked: contactUnlocked))
        let harmful: Set<ModerationCategory> = [.harassment, .hate, .sexual, .scam, .phishingLink, .offPlatformPayment]
        if verdict.decision == .block && !Set(verdict.categories).isDisjoint(with: harmful) {
            throw BackendError.rejected(verdict.rationale)
        }
        let (body, redacted) = contactUnlocked ? (text, false) : ContentGuard.redactPersonalData(text)
        let message = ChatMessage(id: UUID().uuidString, senderId: me, text: body, sentAt: .now, wasRedacted: redacted)
        try await backend.send(message, in: conversation.id)
        return redacted
    }

    func submit(review: EmployerReview) async throws {
        let verdict = await moderation.review(.review(review))
        if verdict.decision == .block { throw BackendError.rejected(verdict.rationale) }
        try await backend.submit(review)
    }

    func report(_ kind: ReportTargetKind, id: String, owner: String, excerpt: String, reason: ReportReason, details: String) async throws {
        let report = Report(id: UUID().uuidString, reporterId: me, targetKind: kind, targetId: id, targetOwnerId: owner,
                            excerpt: String(excerpt.prefix(280)), reason: reason, details: details, createdAt: .now,
                            status: .open, aiVerdict: nil)
        try await backend.submit(report)
    }

    func block(_ uid: String) async throws {
        try await backend.block(uid)
        blocked.insert(uid)
        conversations.removeAll { $0.participantIds.contains(uid) }
    }

    func deleteAccount() async throws {
        try await backend.deleteAccount()
        account = nil
        profile = nil
    }

    func save(account: UserAccount, profile: PublicProfile) async throws {
        let verdict = await moderation.review(.profile(headline: profile.headline, skills: profile.skills))
        if verdict.decision == .block { throw BackendError.rejected(verdict.rationale) }
        try await backend.save(account: account, profile: profile)
        self.account = account
        self.profile = profile
    }
}
