import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Production backend. Access control lives in the Firestore security rules; this class
/// never relies on the client for security decisions.
///
/// Collections:
/// - `users/{uid}` private account · `users/{uid}/devices/{token}` push tokens
/// - `publicProfiles/{uid}` anonymized profile (score signals written by Cloud Functions only)
/// - `jobs/{id}` · `jobs/{id}/proposals/{freelancerUid}`
/// - `conversations/{id}` · `conversations/{id}/messages/{id}`
/// - `connections/{uidA_uidB}` mutual contact agreements
/// - `reviews/{id}` · `reports/{id}` · `moderationActions/{id}` (admin, applied by Functions)
final class FirestoreBackend: MarketplaceBackend {
    private lazy var db = Firestore.firestore()

    var userID: String? { Auth.auth().currentUser?.uid }

    private func uid() throws -> String {
        guard let id = userID else { throw BackendError.notSignedIn }
        return id
    }

    // MARK: Accounts

    func account() async throws -> UserAccount? {
        let snapshot = try await db.collection("users").document(try uid()).getDocument()
        return snapshot.exists ? try snapshot.data(as: UserAccount.self) : nil
    }

    func publicProfile(_ id: String) async throws -> PublicProfile? {
        let snapshot = try await db.collection("publicProfiles").document(id).getDocument()
        return snapshot.exists ? try snapshot.data(as: PublicProfile.self) : nil
    }

    func save(account: UserAccount, profile: PublicProfile) async throws {
        let batch = db.batch()
        try batch.setData(from: account, forDocument: db.collection("users").document(account.id))
        // Score signals, completed jobs and verified links are server-owned: merge only editable fields.
        batch.setData([
            "id": profile.id,
            "discipline": profile.discipline.rawValue,
            "headline": profile.headline,
            "skills": profile.skills,
            "yearsOfExperience": profile.yearsOfExperience,
            "region": profile.region,
            "isAvailable": profile.isAvailable,
        ], forDocument: db.collection("publicProfiles").document(profile.id), merge: true)
        try await batch.commit()
    }

    // MARK: Jobs

    func openJobs() async throws -> [JobPost] {
        try await db.collection("jobs")
            .whereField("status", isEqualTo: JobStatus.open.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
            .documents.compactMap { try? $0.data(as: JobPost.self) }
    }

    func jobs(postedBy uid: String) async throws -> [JobPost] {
        try await db.collection("jobs")
            .whereField("ownerId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments()
            .documents.compactMap { try? $0.data(as: JobPost.self) }
    }

    func publish(_ job: JobPost) async throws {
        // Clients can only create jobs in `pendingReview` (enforced by rules). The `moderateJob`
        // Cloud Function re-runs Gemini server-side and is the only one allowed to set `open`.
        var pending = job
        pending.status = .pendingReview
        try db.collection("jobs").document(job.id).setData(from: pending)
    }

    func submit(_ proposal: Proposal) async throws {
        try db.collection("jobs").document(proposal.jobId)
            .collection("proposals").document(proposal.freelancerId).setData(from: proposal)
    }

    func proposals(forJob id: String) async throws -> [Proposal] {
        try await db.collection("jobs").document(id).collection("proposals")
            .order(by: "createdAt", descending: true).getDocuments()
            .documents.compactMap { try? $0.data(as: Proposal.self) }
    }

    func candidates(for job: JobPost, limit: Int) async throws -> [PublicProfile] {
        let profiles = try await db.collection("publicProfiles")
            .whereField("discipline", isEqualTo: job.discipline.rawValue)
            .whereField("isAvailable", isEqualTo: true)
            .limit(to: 50)
            .getDocuments()
            .documents.compactMap { try? $0.data(as: PublicProfile.self) }
        return Self.rank(profiles, for: job, limit: limit)
    }

    /// Skill match (60%) + reputation (40%).
    static func rank(_ profiles: [PublicProfile], for job: JobPost, limit: Int) -> [PublicProfile] {
        func relevance(_ profile: PublicProfile) -> Double {
            let match: Double = profile.matchScore(for: job.skills)
            let reputation: Double = Double(profile.score.overall) / 100
            return match * 0.6 + reputation * 0.4
        }
        let sorted: [PublicProfile] = profiles.sorted { relevance($0) > relevance($1) }
        return Array(sorted.prefix(limit))
    }

    // MARK: Chat

    func conversations() -> AsyncStream<[Conversation]> {
        guard let me = userID else { return AsyncStream { $0.finish() } }
        let query = db.collection("conversations")
            .whereField("participantIds", arrayContains: me)
            .order(by: "lastMessageAt", descending: true)
        return stream(query) { try? $0.data(as: Conversation.self) }
    }

    func messages(in conversationID: String) -> AsyncStream<[ChatMessage]> {
        let query = db.collection("conversations").document(conversationID)
            .collection("messages").order(by: "sentAt").limit(toLast: 200)
        return stream(query) { try? $0.data(as: ChatMessage.self) }
    }

    private func stream<T>(_ query: Query, map: @escaping (QueryDocumentSnapshot) -> T?) -> AsyncStream<[T]> {
        AsyncStream { continuation in
            let registration = query.addSnapshotListener { snapshot, _ in
                continuation.yield(snapshot?.documents.compactMap(map) ?? [])
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func send(_ message: ChatMessage, in conversationID: String) async throws {
        let conversation = db.collection("conversations").document(conversationID)
        let batch = db.batch()
        try batch.setData(from: message, forDocument: conversation.collection("messages").document(message.id))
        batch.updateData(["lastMessage": message.text, "lastMessageAt": Timestamp(date: message.sentAt)], forDocument: conversation)
        try await batch.commit()
    }

    func startConversation(with other: String, handles: [String: String], job: JobPost?) async throws -> Conversation {
        let me = try uid()
        let id = [me, other].sorted().joined(separator: "_") + (job.map { "_" + $0.id } ?? "")
        let conversation = Conversation(id: id, participantIds: [me, other], handles: handles, jobId: job?.id,
                                        jobTitle: job?.title, lastMessage: "", lastMessageAt: .now, unread: [:])
        try db.collection("conversations").document(id).setData(from: conversation, merge: true)
        return conversation
    }

    // MARK: Contact exchange

    func connection(with other: String) async throws -> Connection? {
        let snapshot = try await db.collection("connections").document(Connection.id(try uid(), other)).getDocument()
        return snapshot.exists ? try snapshot.data(as: Connection.self) : nil
    }

    func requestContact(with other: String) async throws -> Connection {
        let me = try uid()
        let connection = Connection(id: Connection.id(me, other), participantIds: [me, other].sorted(),
                                    requesterId: me, acceptedBy: [me], createdAt: .now)
        try db.collection("connections").document(connection.id).setData(from: connection)
        return connection
    }

    func accept(_ connection: Connection) async throws -> Connection {
        let me = try uid()
        try await db.collection("connections").document(connection.id)
            .updateData(["acceptedBy": FieldValue.arrayUnion([me])])
        var updated = connection
        if !updated.acceptedBy.contains(me) { updated.acceptedBy.append(me) }
        return updated
    }

    func contact(of other: String) async throws -> PrivateContact? {
        // Rules reject this read unless the connection is mutual.
        guard let connection = try await connection(with: other), connection.isMutual else { throw BackendError.contactLocked }
        let account = try await db.collection("users").document(other).getDocument(as: UserAccount.self)
        return PrivateContact(displayName: account.displayName, email: account.email, phone: account.phone, links: account.links)
    }

    // MARK: Trust & safety

    func submit(_ review: EmployerReview) async throws {
        try db.collection("reviews").document(review.id).setData(from: review)
    }

    func submit(_ report: Report) async throws {
        try db.collection("reports").document(report.id).setData(from: report)
    }

    func isAdmin() async -> Bool {
        guard let result = try? await Auth.auth().currentUser?.getIDTokenResult() else { return false }
        return result.claims["admin"] as? Bool == true
    }

    func openReports() async throws -> [Report] {
        try await db.collection("reports").whereField("status", isEqualTo: ReportStatus.open.rawValue)
            .order(by: "createdAt", descending: true).limit(to: 100).getDocuments()
            .documents.compactMap { try? $0.data(as: Report.self) }
    }

    func jobsAwaitingReview() async throws -> [JobPost] {
        try await db.collection("jobs").whereField("status", isEqualTo: JobStatus.pendingReview.rawValue)
            .order(by: "createdAt").limit(to: 100).getDocuments()
            .documents.compactMap { try? $0.data(as: JobPost.self) }
    }

    func resolve(_ report: Report, action: ModerationAction) async throws {
        // A Cloud Function applies the action with the Admin SDK (remove content, disable account…).
        let batch = db.batch()
        batch.setData([
            "reportId": report.id, "action": action.rawValue, "targetKind": report.targetKind.rawValue,
            "targetId": report.targetId, "targetOwnerId": report.targetOwnerId,
            "adminId": try uid(), "createdAt": FieldValue.serverTimestamp(),
        ], forDocument: db.collection("moderationActions").document())
        batch.updateData(["status": action == .dismiss ? ReportStatus.dismissed.rawValue : ReportStatus.actioned.rawValue],
                         forDocument: db.collection("reports").document(report.id))
        try await batch.commit()
    }

    func moderate(_ job: JobPost, approve: Bool) async throws {
        try await db.collection("jobs").document(job.id)
            .updateData(["status": approve ? JobStatus.open.rawValue : JobStatus.removed.rawValue])
    }

    func blockedUsers() async throws -> Set<String> {
        let snapshot = try await db.collection("users").document(try uid()).collection("blocked").getDocuments()
        return Set(snapshot.documents.map(\.documentID))
    }

    func block(_ other: String) async throws {
        try await db.collection("users").document(try uid()).collection("blocked").document(other)
            .setData(["createdAt": FieldValue.serverTimestamp()])
    }

    /// Deletes the private account and public profile, then the Auth user. Jobs, messages and
    /// reviews are anonymized by the `onAccountDeleted` Cloud Function.
    func deleteAccount() async throws {
        let me = try uid()
        let batch = db.batch()
        batch.deleteDocument(db.collection("users").document(me))
        batch.deleteDocument(db.collection("publicProfiles").document(me))
        try await batch.commit()
        try await Auth.auth().currentUser?.delete()
    }

    func registerPushToken(_ token: String) async {
        guard let me = userID else { return }
        try? await db.collection("users").document(me).collection("devices").document(token)
            .setData(["token": token, "platform": "ios", "updatedAt": FieldValue.serverTimestamp()])
    }
}
