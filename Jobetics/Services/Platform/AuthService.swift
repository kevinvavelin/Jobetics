import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation

/// Sign in with Apple → Firebase Auth. No passwords stored anywhere.
@Observable
final class AuthService {
    private(set) var isSignedIn: Bool
    private var currentNonce: String?
    private var handle: AuthStateDidChangeListenerHandle?

    init(demo: Bool) {
        isSignedIn = demo || Auth.auth().currentUser != nil
        guard !demo else { return }
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isSignedIn = user != nil
        }
    }

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async throws {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw URLError(.userAuthenticationRequired)
        }
        let firebaseCredential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: credential.fullName)
        try await Auth.auth().signIn(with: firebaseCredential)
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
