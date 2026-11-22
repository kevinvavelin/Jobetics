import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import SwiftUI // WebAuthenticationSession

/// Firebase Auth with the two providers enabled on the project: e-mail/password and Google.
///
/// Google uses the OAuth 2.0 authorization-code flow with PKCE in an `ASWebAuthenticationSession`
/// (the same flow the GoogleSignIn SDK runs). The iOS client ID is read at runtime from the
/// git-ignored GoogleService-Info.plist, so nothing project-specific lives in the repository,
/// and no URL scheme needs to be declared in Info.plist.
@Observable
final class AuthService {
    private(set) var isSignedIn: Bool
    private(set) var displayName: String?
    private(set) var email: String?
    private var handle: AuthStateDidChangeListenerHandle?

    init(demo: Bool) {
        let user = demo ? nil : Auth.auth().currentUser
        isSignedIn = demo || user != nil
        displayName = user?.displayName
        email = user?.email
        guard !demo else { return }
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isSignedIn = user != nil
            self?.displayName = user?.displayName
            self?.email = user?.email
        }
    }

    // MARK: E-mail & password

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email.trimmed, password: password)
    }

    func createAccount(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email.trimmed, password: password)
        try? await result.user.sendEmailVerification()
    }

    func sendPasswordReset(to email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email.trimmed)
    }

    // MARK: Google

    /// Returns `false` when the user cancelled the Google sheet.
    @discardableResult
    func signInWithGoogle(using session: WebAuthenticationSession) async throws -> Bool {
        guard let clientID = FirebaseApp.app()?.options.clientID else { throw AuthServiceError.googleNotConfigured }
        // "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.randomString(length: 64)
        let state = Self.randomString(length: 32)
        let nonce = Self.randomString(length: 32)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]

        let callback: URL
        do {
            callback = try await session.authenticate(using: components.url!, callback: .customScheme(scheme),
                                                      preferredBrowserSession: .shared, additionalHeaderFields: [:])
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthServiceError.googleFailed }
        if items.contains(where: { $0.name == "error" }) { return false } // e.g. access_denied
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw AuthServiceError.googleFailed }

        let tokens = try await Self.exchange(code: code, clientID: clientID, redirectURI: redirectURI, verifier: verifier)
        let credential = GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken)
        try await Auth.auth().signIn(with: credential)
        return true
    }

    private struct GoogleTokens: Decodable {
        let idToken: String
        let accessToken: String
        enum CodingKeys: String, CodingKey { case idToken = "id_token", accessToken = "access_token" }
    }

    private static func exchange(code: String, clientID: String, redirectURI: String, verifier: String) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        // URLComponents leaves "+" unescaped, which form decoding reads as a space.
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuthServiceError.googleFailed }
        return try JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    // MARK: Session

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: Helpers

    /// User-facing message for a Firebase Auth error.
    static func message(for error: Error) -> String {
        if let error = error as? AuthServiceError { return error.localizedDescription }
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .invalidEmail: return String(localized: "This e-mail address isn't valid.")
        case .wrongPassword, .invalidCredential, .userNotFound: return String(localized: "Wrong e-mail or password.")
        case .emailAlreadyInUse: return String(localized: "An account already exists with this e-mail. Sign in instead.")
        case .weakPassword: return String(localized: "Choose a password of at least 6 characters.")
        case .accountExistsWithDifferentCredential: return String(localized: "This e-mail is already linked to another sign-in method.")
        case .userDisabled: return String(localized: "This account has been disabled.")
        case .tooManyRequests: return String(localized: "Too many attempts. Try again in a few minutes.")
        case .networkError: return String(localized: "No connection. Check your network and try again.")
        default: return error.localizedDescription
        }
    }

    private static func randomString(length: Int) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AuthServiceError: LocalizedError {
    case googleNotConfigured, googleFailed

    var errorDescription: String? {
        switch self {
        case .googleNotConfigured: String(localized: "Google sign-in isn't configured for this build.")
        case .googleFailed: String(localized: "Google sign-in failed. Please try again.")
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
