import Foundation

/// Offline backend with realistic sample data. Used when Firebase isn't configured
/// (fresh clone of the public repo), in previews, UI tests and App Store screenshots.
final class DemoBackend: MarketplaceBackend {
    static let me = "demo-camille-7q2c"

    private(set) var account: UserAccount? = DemoData.account
    private var profiles: [String: PublicProfile] = Dictionary(uniqueKeysWithValues: DemoData.profiles.map { ($0.id, $0) })
    private var jobs: [JobPost] = DemoData.jobs
    private var proposals: [Proposal] = DemoData.proposals
    private var conversationList: [Conversation] = DemoData.conversations
    private var messageStore: [String: [ChatMessage]] = DemoData.messages
    private var connections: [String: Connection] = DemoData.connections
    private var reports: [Report] = DemoData.reports
    private var conversationObservers: [UUID: AsyncStream<[Conversation]>.Continuation] = [:]
    private var messageObservers: [String: [UUID: AsyncStream<[ChatMessage]>.Continuation]] = [:]

    var userID: String? { Self.me }

    func account() async throws -> UserAccount? { account }
    func publicProfile(_ id: String) async throws -> PublicProfile? { profiles[id] }
    func save(account: UserAccount, profile: PublicProfile) async throws {
        self.account = account
        profiles[profile.id] = profile
    }

    func openJobs() async throws -> [JobPost] { jobs.filter { $0.status == .open && $0.ownerId != Self.me } }
    func jobs(postedBy uid: String) async throws -> [JobPost] { jobs.filter { $0.ownerId == uid } }
    func publish(_ job: JobPost) async throws { jobs.insert(job, at: 0) }
    func submit(_ proposal: Proposal) async throws {
        proposals.append(proposal)
        if let i = jobs.firstIndex(where: { $0.id == proposal.jobId }) { jobs[i].proposalCount += 1 }
    }
    func proposals(forJob id: String) async throws -> [Proposal] { proposals.filter { $0.jobId == id } }
    func candidates(for job: JobPost, limit: Int) async throws -> [PublicProfile] {
        FirestoreBackend.rank(profiles.values.filter { $0.id != Self.me }, for: job, limit: limit)
    }

    func conversations() -> AsyncStream<[Conversation]> {
        AsyncStream { continuation in
            let id = UUID()
            conversationObservers[id] = continuation
            continuation.yield(conversationList)
        }
    }

    func messages(in conversationID: String) -> AsyncStream<[ChatMessage]> {
        AsyncStream { continuation in
            let id = UUID()
            messageObservers[conversationID, default: [:]][id] = continuation
            continuation.yield(messageStore[conversationID] ?? [])
        }
    }

    func send(_ message: ChatMessage, in conversationID: String) async throws {
        messageStore[conversationID, default: []].append(message)
        if let i = conversationList.firstIndex(where: { $0.id == conversationID }) {
            conversationList[i].lastMessage = message.text
            conversationList[i].lastMessageAt = message.sentAt
            conversationList.sort { $0.lastMessageAt > $1.lastMessageAt }
        }
        messageObservers[conversationID]?.values.forEach { $0.yield(messageStore[conversationID] ?? []) }
        conversationObservers.values.forEach { $0.yield(conversationList) }
    }

    func startConversation(with uid: String, handles: [String: String], job: JobPost?) async throws -> Conversation {
        if let existing = conversationList.first(where: { $0.participantIds.contains(uid) && $0.jobId == job?.id }) { return existing }
        let conversation = Conversation(id: UUID().uuidString, participantIds: [Self.me, uid], handles: handles,
                                        jobId: job?.id, jobTitle: job?.title, lastMessage: "", lastMessageAt: .now, unread: [:])
        conversationList.insert(conversation, at: 0)
        conversationObservers.values.forEach { $0.yield(conversationList) }
        return conversation
    }

    func connection(with uid: String) async throws -> Connection? { connections[Connection.id(Self.me, uid)] }
    func requestContact(with uid: String) async throws -> Connection {
        let c = Connection(id: Connection.id(Self.me, uid), participantIds: [Self.me, uid].sorted(),
                           requesterId: Self.me, acceptedBy: [Self.me], createdAt: .now)
        connections[c.id] = c
        return c
    }
    func accept(_ connection: Connection) async throws -> Connection {
        var c = connection
        c.acceptedBy = c.participantIds
        connections[c.id] = c
        return c
    }
    func contact(of uid: String) async throws -> PrivateContact? {
        guard connections[Connection.id(Self.me, uid)]?.isMutual == true else { throw BackendError.contactLocked }
        return DemoData.contacts[uid]
    }

    func submit(_ review: EmployerReview) async throws {}
    func submit(_ report: Report) async throws { reports.insert(report, at: 0) }

    func isAdmin() async -> Bool { true }
    func openReports() async throws -> [Report] { reports.filter { $0.status == .open } }
    func jobsAwaitingReview() async throws -> [JobPost] { jobs.filter { $0.status == .pendingReview } }
    func resolve(_ report: Report, action: ModerationAction) async throws {
        if let i = reports.firstIndex(where: { $0.id == report.id }) { reports[i].status = action == .dismiss ? .dismissed : .actioned }
    }
    func moderate(_ job: JobPost, approve: Bool) async throws {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i].status = approve ? .open : .removed }
    }
    func registerPushToken(_ token: String) async {}

    private var blocked: Set<String> = []
    func blockedUsers() async throws -> Set<String> { blocked }
    func block(_ uid: String) async throws { blocked.insert(uid) }
    func deleteAccount() async throws { account = nil }
}

enum DemoData {
    static let now = Date.now
    static func days(_ d: Double) -> Date { now.addingTimeInterval(d * 86_400) }
    static func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3_600) }

    static let account = UserAccount(
        id: DemoBackend.me, displayName: "Camille Laurent", email: "camille@example.com", phone: "+33 6 00 00 00 00",
        isFreelancer: true, discipline: .design,
        links: [
            ProfileLink(kind: .linkedin, url: URL(string: "https://www.linkedin.com/in/example")!),
            ProfileLink(kind: .behance, url: URL(string: "https://www.behance.net/example")!),
        ],
        jobAlertSkills: ["Product design", "Design systems", "SwiftUI", "Prototyping"],
        createdAt: days(-420)
    )

    static let myProfile = PublicProfile(
        id: DemoBackend.me, discipline: .design, headline: "Product designer for iOS & design systems",
        skills: ["Product design", "Design systems", "Figma", "Prototyping", "SwiftUI", "User research"],
        yearsOfExperience: 8, hourlyRate: Money(85), region: "Europe · CET",
        signals: ScoreSignals(medianResponseMinutes: 18, meetingsAttended: 47, meetingsTotal: 48,
                              deliveredOnTime: 22, deliveredTotal: 23, averageRating: 4.9, ratingCount: 21,
                              profileCompleteness: 0.95),
        completedJobs: 23, verifiedLinks: [.linkedin, .behance], isAvailable: true
    )

    static let profiles: [PublicProfile] = [
        myProfile,
        PublicProfile(id: "p-41f2", discipline: .development, headline: "Senior iOS engineer · SwiftUI, SwiftData, CloudKit",
                      skills: ["SwiftUI", "SwiftData", "CloudKit", "Firebase", "WidgetKit"], yearsOfExperience: 10,
                      hourlyRate: Money(110), region: "Europe · CET",
                      signals: .init(medianResponseMinutes: 25, meetingsAttended: 60, meetingsTotal: 61, deliveredOnTime: 30, deliveredTotal: 31, averageRating: 4.95, ratingCount: 28, profileCompleteness: 1),
                      completedJobs: 31, verifiedLinks: [.linkedin, .github], isAvailable: true),
        PublicProfile(id: "p-a9c0", discipline: .development, headline: "Full-stack developer, TypeScript & Cloud Functions",
                      skills: ["TypeScript", "Firebase", "Node.js", "SwiftUI"], yearsOfExperience: 6,
                      hourlyRate: Money(80), region: "North America · EST",
                      signals: .init(medianResponseMinutes: 55, meetingsAttended: 30, meetingsTotal: 33, deliveredOnTime: 14, deliveredTotal: 16, averageRating: 4.6, ratingCount: 12, profileCompleteness: 0.85),
                      completedJobs: 16, verifiedLinks: [.linkedin, .github], isAvailable: true),
        PublicProfile(id: "p-77be", discipline: .design, headline: "Brand & motion designer for startups",
                      skills: ["Branding", "Motion design", "Figma", "Illustration"], yearsOfExperience: 7,
                      hourlyRate: Money(75), region: "Europe · GMT",
                      signals: .init(medianResponseMinutes: 40, meetingsAttended: 25, meetingsTotal: 26, deliveredOnTime: 18, deliveredTotal: 19, averageRating: 4.8, ratingCount: 15, profileCompleteness: 0.9),
                      completedJobs: 19, verifiedLinks: [.linkedin, .behance], isAvailable: true),
        PublicProfile(id: "p-3d18", discipline: .design, headline: "UX researcher & product designer, fintech",
                      skills: ["User research", "Product design", "Prototyping", "Design systems"], yearsOfExperience: 5,
                      hourlyRate: Money(70), region: "Europe · CET",
                      signals: .init(medianResponseMinutes: 90, meetingsAttended: 18, meetingsTotal: 20, deliveredOnTime: 9, deliveredTotal: 10, averageRating: 4.7, ratingCount: 8, profileCompleteness: 0.8),
                      completedJobs: 10, verifiedLinks: [.linkedin, .behance], isAvailable: true),
        PublicProfile(id: "p-c5e3", discipline: .consulting, headline: "Go-to-market consultant for B2B SaaS",
                      skills: ["Go-to-market", "Pricing", "Sales strategy", "Positioning"], yearsOfExperience: 12,
                      hourlyRate: Money(150), region: "Europe · CET",
                      signals: .init(medianResponseMinutes: 35, meetingsAttended: 80, meetingsTotal: 81, deliveredOnTime: 25, deliveredTotal: 25, averageRating: 4.9, ratingCount: 22, profileCompleteness: 1),
                      completedJobs: 25, verifiedLinks: [.linkedin, .website], isAvailable: true),
        PublicProfile(id: "p-0b6d", discipline: .advisory, headline: "Fractional CTO & technical advisor",
                      skills: ["Architecture", "Hiring", "Fundraising", "Security"], yearsOfExperience: 15,
                      hourlyRate: Money(180), region: "Europe · CET",
                      signals: .init(medianResponseMinutes: 120, meetingsAttended: 40, meetingsTotal: 41, deliveredOnTime: 12, deliveredTotal: 12, averageRating: 5, ratingCount: 10, profileCompleteness: 1),
                      completedJobs: 12, verifiedLinks: [.linkedin, .twitter], isAvailable: false),
    ]

    static let goodEmployer = EmployerReputation(clarity: 4.8, communication: 4.7, payment: 4.9, reviewCount: 34, spamReports: 0)
    static let okEmployer = EmployerReputation(clarity: 4.1, communication: 4.4, payment: 4.6, reviewCount: 9, spamReports: 0)

    static let jobs: [JobPost] = [
        JobPost(id: "job-ios-redesign", ownerId: "emp-northwind", title: "Redesign our iOS banking app for Liquid Glass",
                summary: "We're a 40-person fintech preparing our app for iOS 26. You'll audit our current flows, define a Liquid Glass-ready component library in Figma and hand off specs to our SwiftUI team. Accessibility is a priority.",
                discipline: .design, skills: ["Product design", "Design systems", "Figma", "SwiftUI"],
                budget: Money(9_500), pricing: .fixed, startDate: days(5), dueDate: days(40), isRemote: true,
                status: .open, createdAt: hours(-2), proposalCount: 7, employer: goodEmployer, moderation: .allowed),
        JobPost(id: "job-design-system", ownerId: "emp-lumen", title: "Design system lead for a health startup (3 months)",
                summary: "Lumen Health is scaling from 2 to 6 product squads. We need a senior designer to own our design system: tokens, components, documentation, and contribution model with engineering.",
                discipline: .design, skills: ["Design systems", "Figma", "Documentation", "Product design"],
                budget: Money(90), pricing: .hourly, startDate: days(12), dueDate: days(100), isRemote: true,
                status: .open, createdAt: hours(-6), proposalCount: 12, employer: okEmployer, moderation: .allowed),
        JobPost(id: "job-widgets", ownerId: "emp-orbit", title: "Build interactive widgets & a watchOS companion",
                summary: "Our habit-tracking app needs Home Screen widgets, Control Center controls and an Apple Watch companion. SwiftUI, App Intents and WidgetKit experience required. Clean, tested code.",
                discipline: .development, skills: ["SwiftUI", "WidgetKit", "App Intents", "watchOS"],
                budget: Money(12_000), pricing: .fixed, startDate: days(3), dueDate: days(35), isRemote: true,
                status: .open, createdAt: hours(-9), proposalCount: 4, employer: goodEmployer, moderation: .allowed),
        JobPost(id: "job-prototype", ownerId: "emp-atlas", title: "Prototype an onboarding flow for a travel app",
                summary: "Five-day sprint to prototype and test a new onboarding for our travel planner. You'll run five user interviews with us and iterate on a high-fidelity Figma prototype.",
                discipline: .design, skills: ["Prototyping", "User research", "Figma"],
                budget: Money(3_200), pricing: .fixed, startDate: days(8), dueDate: days(15), isRemote: false,
                status: .open, createdAt: days(-1), proposalCount: 9, employer: goodEmployer, moderation: .allowed),
        JobPost(id: "job-gtm", ownerId: "emp-ferris", title: "Pricing & packaging review for our B2B SaaS",
                summary: "We sell workflow software to accounting firms. We'd like an experienced consultant to review our pricing tiers, interview 10 customers and recommend a new packaging before Q1.",
                discipline: .consulting, skills: ["Pricing", "Go-to-market", "Positioning"],
                budget: Money(7_000), pricing: .fixed, startDate: days(10), dueDate: days(45), isRemote: true,
                status: .open, createdAt: days(-2), proposalCount: 3, employer: okEmployer, moderation: .allowed),
        JobPost(id: "job-firebase", ownerId: "emp-orbit", title: "Firebase security rules & Cloud Functions audit",
                summary: "Audit our Firestore security rules, App Check setup and Cloud Functions before launch. Deliver a written report and fixes as pull requests. Experience with the Emulator Suite is a must.",
                discipline: .development, skills: ["Firebase", "TypeScript", "Security"],
                budget: Money(120), pricing: .hourly, startDate: days(2), dueDate: days(20), isRemote: true,
                status: .open, createdAt: days(-3), proposalCount: 6, employer: goodEmployer, moderation: .allowed),
        JobPost(id: "job-advisor", ownerId: "emp-kite", title: "Technical advisor for seed-stage marketplace",
                summary: "Two calls a month with our founding team to review architecture choices, hiring plan and security posture while we prepare our seed round. Six-month engagement.",
                discipline: .advisory, skills: ["Architecture", "Hiring", "Fundraising"],
                budget: Money(2_000), pricing: .fixed, startDate: days(14), dueDate: days(190), isRemote: true,
                status: .open, createdAt: days(-4), proposalCount: 2, employer: .new, moderation: .allowed),
        // Posted by the demo user (hiring mode)
        JobPost(id: "job-mine-illustration", ownerId: DemoBackend.me, title: "Illustrations for our onboarding screens",
                summary: "Looking for a brand illustrator to create 6 onboarding illustrations matching our Liquid Glass visual language. Source files in Figma and SVG exports for iOS and the web.",
                discipline: .design, skills: ["Illustration", "Branding", "Figma"],
                budget: Money(2_400), pricing: .fixed, startDate: days(7), dueDate: days(28), isRemote: true,
                status: .open, createdAt: days(-1), proposalCount: 5, employer: goodEmployer, moderation: .allowed),
        JobPost(id: "job-mine-dev", ownerId: DemoBackend.me, title: "SwiftUI developer to build a widget suite",
                summary: "We need an experienced SwiftUI developer to implement Home Screen and Lock Screen widgets plus an Apple Watch complication from our existing Figma designs.",
                discipline: .development, skills: ["SwiftUI", "WidgetKit", "watchOS"],
                budget: Money(6_500), pricing: .fixed, startDate: days(10), dueDate: days(40), isRemote: true,
                status: .open, createdAt: days(-3), proposalCount: 8, employer: goodEmployer, moderation: .allowed),
        // Waiting for moderation (admin queue)
        JobPost(id: "job-suspicious", ownerId: "emp-unknown", title: "Easy design task, quick payment via gift cards",
                summary: "Need 20 logos today. Payment by gift card after delivery, contact me on telegram for details. Free test logo first to check your skills, then we talk about money maybe.",
                discipline: .design, skills: ["Logo"], budget: Money(50), pricing: .fixed, startDate: days(0), dueDate: days(1),
                isRemote: true, status: .pendingReview, createdAt: hours(-1), proposalCount: 0, employer: .new,
                moderation: ModerationVerdict(decision: .block, categories: [.offPlatformPayment, .unpaidWork, .scam], confidence: 0.97, rationale: "Gift-card payment and free test work.")),
    ]

    static let proposals: [Proposal] = []

    static let connections: [String: Connection] = {
        let c = Connection(id: Connection.id(DemoBackend.me, "emp-northwind"), participantIds: [DemoBackend.me, "emp-northwind"].sorted(),
                           requesterId: "emp-northwind", acceptedBy: [DemoBackend.me, "emp-northwind"], createdAt: days(-1))
        let pending = Connection(id: Connection.id(DemoBackend.me, "emp-orbit"), participantIds: [DemoBackend.me, "emp-orbit"].sorted(),
                                 requesterId: "emp-orbit", acceptedBy: ["emp-orbit"], createdAt: hours(-3))
        return [c.id: c, pending.id: pending]
    }()

    static let contacts: [String: PrivateContact] = [
        "emp-northwind": PrivateContact(displayName: "Northwind Bank, Product team", email: "design@example.com", phone: nil,
                                        links: [ProfileLink(kind: .linkedin, url: URL(string: "https://www.linkedin.com/company/example")!)]),
    ]

    static let conversations: [Conversation] = [
        Conversation(id: "c-northwind", participantIds: [DemoBackend.me, "emp-northwind"],
                     handles: [DemoBackend.me: "Designer #7Q2C", "emp-northwind": "Fintech employer · ★4.8"],
                     jobId: "job-ios-redesign", jobTitle: "Redesign our iOS banking app for Liquid Glass",
                     lastMessage: "Perfect, see you Thursday at 10:00 for the kickoff", lastMessageAt: hours(-0.3),
                     unread: [DemoBackend.me: 2]),
        Conversation(id: "c-orbit", participantIds: [DemoBackend.me, "emp-orbit"],
                     handles: [DemoBackend.me: "Designer #7Q2C", "emp-orbit": "Consumer app employer · ★4.8"],
                     jobId: "job-widgets", jobTitle: "Build interactive widgets & a watchOS companion",
                     lastMessage: "Could you share a rough timeline for the widget designs?", lastMessageAt: hours(-3),
                     unread: [DemoBackend.me: 1]),
        Conversation(id: "c-41f2", participantIds: [DemoBackend.me, "p-41f2"],
                     handles: [DemoBackend.me: "Designer #7Q2C", "p-41f2": "Developer #41F2"],
                     jobId: "job-mine-dev", jobTitle: "SwiftUI developer to build a widget suite",
                     lastMessage: "I've shipped 12 widget suites, happy to walk you through a few.", lastMessageAt: days(-1),
                     unread: [:]),
        Conversation(id: "c-lumen", participantIds: [DemoBackend.me, "emp-lumen"],
                     handles: [DemoBackend.me: "Designer #7Q2C", "emp-lumen": "Health startup employer · ★4.4"],
                     jobId: "job-design-system", jobTitle: "Design system lead for a health startup (3 months)",
                     lastMessage: "You: Thanks! I've attached two case studies from my portfolio.", lastMessageAt: days(-2),
                     unread: [:]),
    ]

    static let messages: [String: [ChatMessage]] = [
        "c-northwind": [
            ChatMessage(id: "m1", senderId: "emp-northwind", text: "Hi! We loved your design systems case study. Would you be available to start next week?", sentAt: hours(-26), wasRedacted: false),
            ChatMessage(id: "m2", senderId: DemoBackend.me, text: "Thanks a lot! Yes, I can start Monday. I'd suggest a 1-week audit, then 4 weeks on the component library.", sentAt: hours(-25.5), wasRedacted: false),
            ChatMessage(id: "m3", senderId: "emp-northwind", text: "Sounds great. Can we exchange contact details to set up the kickoff?", sentAt: hours(-24), wasRedacted: false),
            ChatMessage(id: "m4", senderId: DemoBackend.me, text: "Of course, I've accepted the contact request.", sentAt: hours(-23.8), wasRedacted: false),
            ChatMessage(id: "m5", senderId: "emp-northwind", text: "I just sent the signed quote back. Kickoff Thursday at 10:00?", sentAt: hours(-1), wasRedacted: false),
            ChatMessage(id: "m6", senderId: DemoBackend.me, text: "Thursday 10:00 works for me.", sentAt: hours(-0.5), wasRedacted: false),
            ChatMessage(id: "m7", senderId: "emp-northwind", text: "Perfect, see you Thursday at 10:00 for the kickoff", sentAt: hours(-0.3), wasRedacted: false),
        ],
        "c-orbit": [
            ChatMessage(id: "o1", senderId: "emp-orbit", text: "Hello! Your profile matches our widget project really well.", sentAt: hours(-4), wasRedacted: false),
            ChatMessage(id: "o2", senderId: "emp-orbit", text: "Reach me at ••• so we can talk faster.", sentAt: hours(-3.5), wasRedacted: true),
            ChatMessage(id: "o3", senderId: "emp-orbit", text: "Could you share a rough timeline for the widget designs?", sentAt: hours(-3), wasRedacted: false),
        ],
        "c-41f2": [
            ChatMessage(id: "d1", senderId: "p-41f2", text: "Hi! I saw your widget suite job. I've shipped 12 widget suites, happy to walk you through a few.", sentAt: days(-1), wasRedacted: false),
        ],
        "c-lumen": [
            ChatMessage(id: "l1", senderId: "emp-lumen", text: "Could you share examples of design systems you've led?", sentAt: days(-2.1), wasRedacted: false),
            ChatMessage(id: "l2", senderId: DemoBackend.me, text: "Thanks! I've attached two case studies from my portfolio.", sentAt: days(-2), wasRedacted: false),
        ],
    ]

    static let reports: [Report] = [
        Report(id: "r1", reporterId: "p-77be", targetKind: .job, targetId: "job-suspicious", targetOwnerId: "emp-unknown",
               excerpt: "Payment by gift card after delivery, contact me on telegram…", reason: .scam,
               details: "Asked me to pay a fee to unlock the brief.", createdAt: hours(-0.8), status: .open,
               aiVerdict: ModerationVerdict(decision: .block, categories: [.scam, .offPlatformPayment], confidence: 0.96, rationale: "Gift-card payment request.")),
        Report(id: "r2", reporterId: "p-3d18", targetKind: .message, targetId: "msg-881", targetOwnerId: "emp-spam42",
               excerpt: "Earn $5,000/week from home!!! Click here: bit.ly/…", reason: .spam,
               details: "", createdAt: hours(-5), status: .open,
               aiVerdict: ModerationVerdict(decision: .block, categories: [.spam, .phishingLink], confidence: 0.93, rationale: "Mass promotion with shortened link.")),
        Report(id: "r3", reporterId: "p-a9c0", targetKind: .review, targetId: "rev-204", targetOwnerId: "p-unknown",
               excerpt: "Terrible client, never pay, don't trust them", reason: .other,
               details: "I think this review is from a competitor.", createdAt: days(-1), status: .open,
               aiVerdict: ModerationVerdict(decision: .review, categories: [], confidence: 0.55, rationale: "Needs a human look.")),
    ]
}
