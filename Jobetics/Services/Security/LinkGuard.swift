import Foundation

/// Offline, deterministic link-safety checks. Every URL opened from Jobetics content
/// (chat, job posts, profiles, portfolio) goes through `LinkGuard` before Safari sees it.
///
/// Server-side, the same links are also checked by a Cloud Function against the
/// Google Safe Browsing API (keys stay on the server, never in this public repo).
nonisolated enum LinkGuard {
    enum Level: Int, Comparable, Sendable {
        case trusted, caution, blocked
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    enum Reason: Hashable, Sendable {
        case insecureScheme
        case unsupportedScheme(String)
        case ipAddressHost
        case embeddedCredentials
        case punycodeHost
        case urlShortener
        case unusualPort
        case suspiciousTLD(String)
        case lookalike(brand: String)
        case unknownHost

        var level: Level {
            switch self {
            case .unsupportedScheme, .ipAddressHost, .embeddedCredentials, .lookalike: .blocked
            case .insecureScheme, .punycodeHost, .urlShortener, .unusualPort, .suspiciousTLD: .caution
            case .unknownHost: .caution
            }
        }

        var explanation: String {
            switch self {
            case .insecureScheme: String(localized: "This link isn't encrypted (HTTP). Anything you type could be read by others.")
            case .unsupportedScheme(let s): String(localized: "\"\(s):\" links can run code or open other apps. Jobetics only opens web pages.")
            case .ipAddressHost: String(localized: "The link points to a raw IP address instead of a website name, a common phishing trick.")
            case .embeddedCredentials: String(localized: "The link hides its real destination behind an \"@\" sign.")
            case .punycodeHost: String(localized: "The address uses look-alike international characters that can imitate a real site.")
            case .urlShortener: String(localized: "Shortened links hide where they really go.")
            case .unusualPort: String(localized: "The link uses an unusual network port.")
            case .suspiciousTLD(let tld): String(localized: "Sites ending in \".\(tld)\" are frequently used for scams.")
            case .lookalike(let brand): String(localized: "This address imitates \(brand) but isn't the real \(brand) website.")
            case .unknownHost: String(localized: "Jobetics doesn't know this website yet. Only continue if you trust the sender.")
            }
        }
    }

    struct Assessment: Sendable {
        var url: URL
        var host: String
        var reasons: [Reason]
        var level: Level { reasons.map(\.level).max() ?? .trusted }
        var canOpen: Bool { level != .blocked }
    }

    /// Well-known, reputable domains (and their subdomains).
    static let trustedDomains: Set<String> = [
        "linkedin.com", "behance.net", "github.com", "x.com", "twitter.com", "dribbble.com",
        "figma.com", "notion.so", "apple.com", "google.com", "youtube.com", "vimeo.com",
        "medium.com", "gitlab.com", "stackoverflow.com", "wikipedia.org", "firebase.google.com",
    ]

    /// Brands phishers like to imitate → their legitimate domains.
    static let protectedBrands: [String: [String]] = [
        "linkedin": ["linkedin.com", "lnkd.in"],
        "paypal": ["paypal.com", "paypal.me"],
        "apple": ["apple.com", "icloud.com"],
        "google": ["google.com", "google.fr", "googleusercontent.com", "goo.gl"],
        "github": ["github.com", "github.io", "githubusercontent.com"],
        "behance": ["behance.net"],
        "stripe": ["stripe.com"],
        "microsoft": ["microsoft.com", "live.com", "office.com"],
        "jobetics": ["jobetics.app"],
    ]

    static let shorteners: Set<String> = [
        "bit.ly", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "is.gd", "buff.ly",
        "rebrand.ly", "cutt.ly", "shorturl.at", "rb.gy", "tiny.cc", "lnkd.in",
    ]

    static let suspiciousTLDs: Set<String> = [
        "zip", "mov", "top", "xyz", "click", "gq", "tk", "ml", "cf", "ga", "work", "country", "loan", "rest",
    ]

    static func assess(_ url: URL) -> Assessment {
        var reasons: [Reason] = []
        let scheme = url.scheme?.lowercased() ?? ""
        let host = (url.host(percentEncoded: false) ?? "").lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        switch scheme {
        case "https": break
        case "http": reasons.append(.insecureScheme)
        default:
            reasons.append(.unsupportedScheme(scheme.isEmpty ? "unknown" : scheme))
            return Assessment(url: url, host: host, reasons: reasons)
        }

        if url.user != nil || url.password != nil { reasons.append(.embeddedCredentials) }
        if isIPAddress(host) { reasons.append(.ipAddressHost) }
        if host.split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) || !host.allSatisfy(\.isASCII) {
            reasons.append(.punycodeHost)
        }
        if let port = url.port, ![80, 443].contains(port) { reasons.append(.unusualPort) }
        if shorteners.contains(host) { reasons.append(.urlShortener) }
        if let tld = host.split(separator: ".").last.map(String.init), suspiciousTLDs.contains(tld) {
            reasons.append(.suspiciousTLD(tld))
        }
        if let brand = impersonatedBrand(host) { reasons.append(.lookalike(brand: brand.capitalized)) }

        if reasons.isEmpty && !isTrusted(host) { reasons.append(.unknownHost) }
        return Assessment(url: url, host: host, reasons: reasons)
    }

    static func isTrusted(_ host: String) -> Bool {
        trustedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Checks that a profile link points to the expected site (e.g. LinkedIn → linkedin.com) over HTTPS.
    static func validateProfileLink(_ text: String, kind: ProfileLinkKind) -> Result<URL, ProfileLinkError> {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.contains("://") { candidate = "https://" + candidate }
        guard let url = URL(string: candidate), let host = url.host()?.lowercased(), !host.isEmpty else {
            return .failure(.malformed)
        }
        guard url.scheme?.lowercased() == "https" else { return .failure(.notHTTPS) }
        if let allowed = kind.allowedHosts, !allowed.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .failure(.wrongSite(expected: allowed[0]))
        }
        guard assess(url).canOpen else { return .failure(.unsafe) }
        return .success(url)
    }

    enum ProfileLinkError: LocalizedError, Equatable {
        case malformed, notHTTPS, unsafe
        case wrongSite(expected: String)

        var errorDescription: String? {
            switch self {
            case .malformed: String(localized: "This doesn't look like a web address.")
            case .notHTTPS: String(localized: "Use a secure https:// link.")
            case .unsafe: String(localized: "This link looks unsafe.")
            case .wrongSite(let expected): String(localized: "This link must point to \(expected).")
            }
        }
    }

    // MARK: Helpers

    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true } // IPv6 literal
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    /// "linkedin-security-check.com", "paypa1.com", "github.verify-login.io" → impersonation.
    private static func impersonatedBrand(_ host: String) -> String? {
        let normalized = host
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "l")
            .replacingOccurrences(of: "rn", with: "m")
        for (brand, domains) in protectedBrands where normalized.contains(brand) {
            let legit = domains.contains { host == $0 || host.hasSuffix("." + $0) }
            if !legit { return brand }
        }
        return nil
    }
}
