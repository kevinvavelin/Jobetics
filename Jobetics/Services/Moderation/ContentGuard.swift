import Foundation

/// Fast, offline checks that run before (and independently of) Gemini.
nonisolated enum ContentGuard {
    struct Finding: Hashable, Sendable {
        var category: ModerationCategory
        var match: String
    }

    private static let email = /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/
    private static let phone = /(?:\+|00)?\d[\d\s().\-]{7,}\d/
    private static let handle = /(?:^|\s)@[A-Za-z0-9_]{3,}/
    private static let url = /https?:\/\/[^\s]+|www\.[^\s]+/

    private static let offPlatformPayment = [
        "western union", "moneygram", "gift card", "itunes card", "pay outside", "wire me",
        "crypto only", "pay in bitcoin", "usdt", "cash app", "send a deposit", "registration fee",
    ]

    private static let unpaidWork = [
        "for exposure", "unpaid", "no budget", "free trial project", "test project for free",
        "equity only", "pay you later", "volunteer basis",
    ]

    private static let spam = [
        "make money fast", "work from home and earn", "click here", "limited offer",
        "dm me on telegram", "whatsapp me", "100% guaranteed", "mlm", "passive income",
    ]

    static func scan(_ text: String) -> [Finding] {
        let lower = text.lowercased()
        var findings: [Finding] = []
        for m in text.matches(of: email) { findings.append(.init(category: .personalData, match: String(m.output))) }
        for m in text.matches(of: phone) where m.output.filter(\.isNumber).count >= 9 {
            findings.append(.init(category: .personalData, match: String(m.output)))
        }
        for m in text.matches(of: handle) { findings.append(.init(category: .personalData, match: String(m.output))) }
        for m in text.matches(of: url) {
            let raw = String(m.output)
            if let link = URL(string: raw.hasPrefix("www.") ? "https://" + raw : raw),
               LinkGuard.assess(link).level == .blocked {
                findings.append(.init(category: .phishingLink, match: raw))
            }
        }
        for p in offPlatformPayment where lower.contains(p) { findings.append(.init(category: .offPlatformPayment, match: p)) }
        for p in unpaidWork where lower.contains(p) { findings.append(.init(category: .unpaidWork, match: p)) }
        for p in spam where lower.contains(p) { findings.append(.init(category: .spam, match: p)) }
        return findings
    }

    /// Replaces e-mails, phone numbers and social handles until both sides accepted contact.
    static func redactPersonalData(_ text: String) -> (text: String, redacted: Bool) {
        var output = text
        for finding in scan(text) where finding.category == .personalData {
            output = output.replacingOccurrences(of: finding.match.trimmingCharacters(in: .whitespaces), with: "•••")
        }
        return (output, output != text)
    }
}
