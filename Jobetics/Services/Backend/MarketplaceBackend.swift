import Foundation

/// Everything the app needs from the marketplace backend. Two implementations:
/// `FirestoreBackend` (production) and `DemoBackend` (offline demo, previews, screenshots).
protocol MarketplaceBackend: AnyObject {
    var userID: String? { get }

    func account() async throws -> UserAccount?
    func publicProfile(_ id: String) async throws -> PublicProfile?
    func save(account: UserAccount, profile: PublicProfile) async throws

    func openJobs() async throws -> [JobPost]
    func jobs(postedBy uid: String) async throws -> [JobPost]
    func publish(_ job: JobPost) async throws
    func submit(_ proposal: Proposal) async throws
    func proposals(forJob id: String) async throws -> [Proposal]
    func candidates(for job: JobPost, limit: Int) async throws -> [PublicProfile]

    func conversations() -> AsyncStream<[Conversation]>
    func messages(in conversationID: String) -> AsyncStream<[ChatMessage]>
    func send(_ message: ChatMessage, in conversationID: String) async throws
    func startConversation(with uid: String, handles: [String: String], job: JobPost?) async throws -> Conversation

    func connection(with uid: String) async throws -> Connection?
    func requestContact(with uid: String) async throws -> Connection
    func accept(_ connection: Connection) async throws -> Connection
    func contact(of uid: String) async throws -> PrivateContact?

    func submit(_ review: EmployerReview) async throws
    func submit(_ report: Report) async throws

    func isAdmin() async -> Bool
    func openReports() async throws -> [Report]
    func jobsAwaitingReview() async throws -> [JobPost]
    func resolve(_ report: Report, action: ModerationAction) async throws
    func moderate(_ job: JobPost, approve: Bool) async throws

    func registerPushToken(_ token: String) async

    /// App Store guideline 1.2: users can block abusive users.
    func blockedUsers() async throws -> Set<String>
    func block(_ uid: String) async throws
    /// App Store guideline 5.1.1(v): in-app account deletion.
    func deleteAccount() async throws
}

enum BackendError: LocalizedError {
    case notSignedIn, notFreelancer, contactLocked, rejected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: String(localized: "Please sign in again.")
        case .notFreelancer: String(localized: "Only registered freelancers can do this.")
        case .contactLocked: String(localized: "Contact details are shared once you both accept.")
        case .rejected(let reason): reason
        }
    }
}
