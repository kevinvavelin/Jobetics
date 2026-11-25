import FirebaseAuth
import FirebaseCore
import Foundation
import PassKit

/// Apple Wallet business card. A Wallet pass must be signed with the Pass Type ID certificate,
/// which can't live in the app, so the `walletPass` Cloud Function signs it. The pass carries a
/// QR code containing the vCard: anyone scanning it with their Camera can add the contact.
enum WalletPassService {
    enum PassError: LocalizedError {
        case unavailable, notSignedIn, server(Int)

        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "Apple Wallet passes need the Jobetics server. Share your QR code or vCard instead.")
            case .notSignedIn: String(localized: "Sign in to create your Wallet card.")
            case .server(let code): String(localized: "The Wallet card couldn't be created (error \(code)).")
            }
        }
    }

    /// Wallet is available on this device and the signing backend is configured.
    static var isAvailable: Bool { PKAddPassesViewController.canAddPasses() && endpoint != nil }

    static var endpoint: URL? {
        guard LaunchOptions.firebaseAvailable, let project = FirebaseApp.app()?.options.projectID else { return nil }
        return URL(string: "https://europe-west1-\(project).cloudfunctions.net/walletPass")
    }

    static func makePass(for card: ContactCard) async throws -> PKPass {
        guard let endpoint else { throw PassError.unavailable }
        guard let user = Auth.auth().currentUser else { throw PassError.notSignedIn }
        let token = try await user.getIDToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(card))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw PassError.server(status) }
        return try PKPass(data: data)
    }

    private struct Payload: Encodable {
        var fullName, organization, title, email, phone, website, vCard: String
        init(_ card: ContactCard) {
            fullName = card.fullName; organization = card.organization; title = card.title
            email = card.email; phone = card.phone; website = card.website; vCard = card.vCard
        }
    }
}
