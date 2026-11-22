import Foundation
import SwiftUI

// MARK: - Disciplines & links

nonisolated enum Discipline: String, Codable, CaseIterable, Identifiable, Sendable {
    case design, development, consulting, advisory, marketing, writing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .design: String(localized: "Design")
        case .development: String(localized: "Development")
        case .consulting: String(localized: "Consulting")
        case .advisory: String(localized: "Advisory")
        case .marketing: String(localized: "Marketing")
        case .writing: String(localized: "Writing")
        }
    }

    var professional: String {
        switch self {
        case .design: String(localized: "Designer")
        case .development: String(localized: "Developer")
        case .consulting: String(localized: "Consultant")
        case .advisory: String(localized: "Advisor")
        case .marketing: String(localized: "Marketer")
        case .writing: String(localized: "Writer")
        }
    }

    var symbol: String {
        switch self {
        case .design: "paintpalette.fill"
        case .development: "chevron.left.forwardslash.chevron.right"
        case .consulting: "briefcase.fill"
        case .advisory: "lightbulb.max.fill"
        case .marketing: "megaphone.fill"
        case .writing: "pencil.and.scribble"
        }
    }

    var tint: Color {
        switch self {
        case .design: .pink
        case .development: Brand.blue
        case .consulting: .teal
        case .advisory: .orange
        case .marketing: Brand.violet
        case .writing: .mint
        }
    }

    /// The portfolio link each discipline must provide, on top of the mandatory LinkedIn.
    var requiredLink: ProfileLinkKind? {
        switch self {
        case .design: .behance
        case .development: .github
        case .consulting: .website
        case .advisory: .twitter
        case .marketing, .writing: nil
        }
    }
}

nonisolated enum ProfileLinkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case linkedin, behance, github, website, twitter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linkedin: String(localized: "LinkedIn")
        case .behance: String(localized: "Behance")
        case .github: String(localized: "GitHub")
        case .website: String(localized: "Website")
        case .twitter: String(localized: "X (Twitter)")
        }
    }

    var symbol: String {
        switch self {
        case .linkedin: "person.crop.square.filled.and.at.rectangle"
        case .behance: "square.on.circle"
        case .github: "terminal"
        case .website: "globe"
        case .twitter: "at"
        }
    }

    var placeholder: String {
        switch self {
        case .linkedin: "https://www.linkedin.com/in/you"
        case .behance: "https://www.behance.net/you"
        case .github: "https://github.com/you"
        case .website: "https://your-studio.com"
        case .twitter: "https://x.com/you"
        }
    }

    /// Hosts accepted for this link. `nil` means any HTTPS host that passes `LinkGuard`.
    var allowedHosts: [String]? {
        switch self {
        case .linkedin: ["linkedin.com"]
        case .behance: ["behance.net"]
        case .github: ["github.com"]
        case .twitter: ["x.com", "twitter.com"]
        case .website: nil
        }
    }
}

nonisolated struct ProfileLink: Codable, Hashable, Sendable {
    var kind: ProfileLinkKind
    var url: URL
}

// MARK: - Accounts & profiles

/// Private account document (`users/{uid}`). Readable only by its owner, and by a
/// counterpart once **both** sides accepted a contact exchange (see `Connection`).
nonisolated struct UserAccount: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var email: String
    var phone: String?
    var isFreelancer: Bool
    var discipline: Discipline?
    var links: [ProfileLink]
    var jobAlertSkills: [String]
    var createdAt: Date

    func link(_ kind: ProfileLinkKind) -> URL? { links.first { $0.kind == kind }?.url }

    /// Validates the registration rules: LinkedIn is mandatory for freelancers,
    /// plus the discipline-specific link (Behance, GitHub, website, X).
    var missingLinks: [ProfileLinkKind] {
        guard isFreelancer else { return [] }
        var required: [ProfileLinkKind] = [.linkedin]
        if let extra = discipline?.requiredLink { required.append(extra) }
        return required.filter { link($0) == nil }
    }
}

/// Public, anonymized profile (`publicProfiles/{uid}`): skills and reputation only.
/// No name, email, phone, photo or link URLs, until contact is mutually accepted.
nonisolated struct PublicProfile: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var discipline: Discipline
    var headline: String
    var skills: [String]
    var yearsOfExperience: Int
    var hourlyRate: Money?
    /// Coarse location only, e.g. "Europe · CET".
    var region: String
    var signals: ScoreSignals
    var completedJobs: Int
    /// Which links were verified, never the URLs themselves.
    var verifiedLinks: [ProfileLinkKind]
    var isAvailable: Bool

    var handle: String { "\(discipline.professional) #\(id.suffix(4).uppercased())" }
    var score: FreelancerScore { ScoreEngine.score(signals) }

    func matchScore(for skills: [String]) -> Double {
        let mine = Set(self.skills.map { $0.lowercased() })
        let wanted = Set(skills.map { $0.lowercased() })
        guard !wanted.isEmpty else { return 0 }
        return Double(mine.intersection(wanted).count) / Double(wanted.count)
    }
}

/// Contact details, revealed only after both sides accepted.
nonisolated struct PrivateContact: Codable, Hashable, Sendable {
    var displayName: String
    var email: String
    var phone: String?
    var links: [ProfileLink]
}

// MARK: - Jobs

nonisolated enum Pricing: String, Codable, CaseIterable, Sendable {
    case fixed, hourly
    var title: String { self == .fixed ? String(localized: "Fixed price") : String(localized: "Hourly") }
}

nonisolated enum JobStatus: String, Codable, Sendable {
    case pendingReview, open, inProgress, closed, removed

    var title: String {
        switch self {
        case .pendingReview: String(localized: "In review")
        case .open: String(localized: "Open")
        case .inProgress: String(localized: "In progress")
        case .closed: String(localized: "Closed")
        case .removed: String(localized: "Removed")
        }
    }
}

/// Aggregated freelancer reviews of an employer (denormalized onto each job).
nonisolated struct EmployerReputation: Codable, Hashable, Sendable {
    var clarity: Double
    var communication: Double
    var payment: Double
    var reviewCount: Int
    var spamReports: Int

    var overall: Double { reviewCount == 0 ? 0 : (clarity + communication + payment) / 3 }
    static let new = EmployerReputation(clarity: 0, communication: 0, payment: 0, reviewCount: 0, spamReports: 0)
}

nonisolated struct JobPost: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var ownerId: String
    var title: String
    var summary: String
    var discipline: Discipline
    var skills: [String]
    var budget: Money
    var pricing: Pricing
    var startDate: Date
    var dueDate: Date
    var isRemote: Bool
    var status: JobStatus
    var createdAt: Date
    var proposalCount: Int
    var employer: EmployerReputation
    var moderation: ModerationVerdict?

    enum ValidationError: LocalizedError, Equatable {
        case missingTitle, summaryTooShort, unpaid, dueBeforeStart, noSkills

        var errorDescription: String? {
            switch self {
            case .missingTitle: String(localized: "Give your job a clear title.")
            case .summaryTooShort: String(localized: "Describe the job in at least 80 characters so freelancers know what you need.")
            case .unpaid: String(localized: "Every job on Jobetics is paid. Set a budget above zero.")
            case .dueBeforeStart: String(localized: "The due date must be after the start date.")
            case .noSkills: String(localized: "Add at least one skill so we can match the right freelancers.")
            }
        }
    }

    func validate() throws(ValidationError) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 6 { throw .missingTitle }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).count < 80 { throw .summaryTooShort }
        if !budget.isPositive { throw .unpaid }
        if dueDate <= startDate { throw .dueBeforeStart }
        if skills.isEmpty { throw .noSkills }
    }

    var snapshot: JobSnapshot {
        JobSnapshot(id: id, title: title, disciplineSymbol: discipline.symbol,
                    budget: budget.formatted + (pricing == .hourly ? "/h" : ""), postedAt: createdAt)
    }
}

nonisolated enum ProposalStatus: String, Codable, Sendable { case sent, shortlisted, accepted, declined }

nonisolated struct Proposal: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var jobId: String
    var freelancerId: String
    var note: String
    var price: Money
    var status: ProposalStatus
    var createdAt: Date
}

// MARK: - Contact & chat

/// A mutual contact-exchange agreement. Personal data is unlocked only when
/// `acceptedBy` contains both participants. Enforced by Firestore rules.
nonisolated struct Connection: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var participantIds: [String]
    var requesterId: String
    var acceptedBy: [String]
    var createdAt: Date

    var isMutual: Bool { Set(acceptedBy) == Set(participantIds) }
    static func id(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: "_") }
}

nonisolated struct Conversation: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var participantIds: [String]
    /// Anonymized handle of each participant, e.g. "Designer #4F2A".
    var handles: [String: String]
    var jobId: String?
    var jobTitle: String?
    var lastMessage: String
    var lastMessageAt: Date
    var unread: [String: Int]

    func otherParticipant(than me: String) -> String { participantIds.first { $0 != me } ?? me }
}

nonisolated struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var senderId: String
    var text: String
    var sentAt: Date
    /// Personal details were removed because contact was not unlocked yet.
    var wasRedacted: Bool
}

// MARK: - Reviews & reports

/// A freelancer's review of an employer after a job (or after a spammy proposal round).
nonisolated struct EmployerReview: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var jobId: String
    var employerId: String
    var reviewerId: String
    /// Was the brief clear enough? 1...5
    var clarity: Int
    var communication: Int
    var payment: Int
    var overall: Int
    var markedAsSpam: Bool
    var comment: String
    var createdAt: Date
}

nonisolated enum ReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case spam, scam, unpaidWork, harassment, inappropriate, personalData, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: String(localized: "Spam")
        case .scam: String(localized: "Scam or fraud")
        case .unpaidWork: String(localized: "Unpaid or \"exposure\" work")
        case .harassment: String(localized: "Harassment")
        case .inappropriate: String(localized: "Inappropriate content")
        case .personalData: String(localized: "Sharing personal data")
        case .other: String(localized: "Something else")
        }
    }
}

nonisolated enum ReportTargetKind: String, Codable, Sendable { case job, message, profile, review }

nonisolated enum ReportStatus: String, Codable, Sendable { case open, actioned, dismissed }

nonisolated struct Report: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var reporterId: String
    var targetKind: ReportTargetKind
    var targetId: String
    var targetOwnerId: String
    var excerpt: String
    var reason: ReportReason
    var details: String
    var createdAt: Date
    var status: ReportStatus
    var aiVerdict: ModerationVerdict?
}

nonisolated enum ModerationAction: String, Codable, Sendable {
    case dismiss, removeContent, warnUser, suspendUser
}

// MARK: - Moderation

nonisolated enum ModerationDecision: String, Codable, Sendable { case allow, review, block }

nonisolated enum ModerationCategory: String, Codable, CaseIterable, Sendable {
    case spam, scam, unpaidWork, offPlatformPayment, harassment, hate, sexual, personalData, phishingLink, discrimination

    var title: String {
        switch self {
        case .spam: String(localized: "Spam")
        case .scam: String(localized: "Scam")
        case .unpaidWork: String(localized: "Unpaid work")
        case .offPlatformPayment: String(localized: "Off-platform payment")
        case .harassment: String(localized: "Harassment")
        case .hate: String(localized: "Hate")
        case .sexual: String(localized: "Sexual content")
        case .personalData: String(localized: "Personal data")
        case .phishingLink: String(localized: "Phishing link")
        case .discrimination: String(localized: "Discrimination")
        }
    }
}

nonisolated struct ModerationVerdict: Codable, Hashable, Sendable {
    var decision: ModerationDecision
    var categories: [ModerationCategory]
    var confidence: Double
    var rationale: String

    static let allowed = ModerationVerdict(decision: .allow, categories: [], confidence: 1, rationale: "")
}
