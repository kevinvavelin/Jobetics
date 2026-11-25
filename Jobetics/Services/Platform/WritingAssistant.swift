import Foundation
import FoundationModels

/// On-device writing help with Apple Intelligence (Foundation Models). Private by design:
/// nothing is sent to a server. Falls back to plain text rules when the model isn't available.
enum WritingAssistant {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Turns a private journal entry into a LinkedIn post of at most 500 characters.
    static func linkedInPost(from entry: String, impact: String, hashtags: [String]) async -> String {
        let source = [entry, impact].filter { !$0.isEmpty }.joined(separator: "\n")
        guard isAvailable, !source.isEmpty else { return SocialShare.linkedInPost(source, hashtags: hashtags) }
        let session = LanguageModelSession(instructions: """
            You help a freelancer share their work on LinkedIn. Rewrite their private journal note as a short, \
            warm, first-person post about what they learned or the value they delivered. Never invent facts, \
            never name clients, no emojis spam (one at most), no hashtags. Keep it under 380 characters. \
            Write in the same language as the note.
            """)
        do {
            let response = try await session.respond(to: source)
            return SocialShare.linkedInPost(response.content, hashtags: hashtags)
        } catch {
            return SocialShare.linkedInPost(source, hashtags: hashtags)
        }
    }

    /// Polite payment reminder, firmer with each reminder already sent.
    static func paymentReminder(client: String, number: String, amount: String, daysLate: Int, reminderIndex: Int,
                                penalty: String, sender: String) async -> String {
        let fallback = defaultReminder(client: client, number: number, amount: amount, daysLate: daysLate,
                                       reminderIndex: reminderIndex, penalty: penalty, sender: sender)
        guard isAvailable else { return fallback }
        let tone = reminderIndex == 0 ? "friendly" : reminderIndex == 1 ? "polite but firm" : "formal, mentioning penalties"
        let session = LanguageModelSession(instructions: """
            Write a short payment reminder e-mail body (no subject) from a freelancer to a client. Tone: \(tone). \
            Keep every number exactly as given. Sign with the sender name. Same language as the user's locale: \
            \(Locale.current.language.languageCode?.identifier ?? "en").
            """)
        let prompt = "Client: \(client). Invoice \(number), amount \(amount), \(daysLate) days late. Penalties so far: \(penalty). Sender: \(sender)."
        return (try? await session.respond(to: prompt).content) ?? fallback
    }

    static func defaultReminder(client: String, number: String, amount: String, daysLate: Int, reminderIndex: Int,
                                penalty: String, sender: String) -> String {
        switch reminderIndex {
        case 0:
            String(localized: "Hello \(client),\n\nA quick reminder that invoice \(number) (\(amount)) was due \(daysLate) days ago. Could you let me know when the payment is planned?\n\nThank you,\n\(sender)")
        case 1:
            String(localized: "Hello \(client),\n\nInvoice \(number) (\(amount)) is now \(daysLate) days overdue. Please arrange the payment this week.\n\nBest regards,\n\(sender)")
        default:
            String(localized: "Hello \(client),\n\nDespite my previous reminders, invoice \(number) (\(amount)) remains unpaid after \(daysLate) days. As stated on the invoice, late-payment penalties and the €40 recovery indemnity now apply (\(penalty)). Please settle it within 8 days.\n\nRegards,\n\(sender)")
        }
    }
}
