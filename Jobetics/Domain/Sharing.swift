import Foundation

/// Builders for sharing outside the app: social networks, messaging apps and contact cards.
nonisolated enum SocialShare {
    static let linkedInLimit = 500

    /// Fits a journal entry into a LinkedIn post of at most `limit` characters, cutting on a
    /// word boundary and keeping hashtags at the end when they fit.
    static func linkedInPost(_ text: String, hashtags: [String] = [], limit: Int = linkedInLimit) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = hashtags.map { $0.hasPrefix("#") ? $0 : "#" + $0.replacingOccurrences(of: " ", with: "") }.joined(separator: " ")
        let suffix = tags.isEmpty ? "" : "\n\n" + tags
        if body.count + suffix.count <= limit { return body + suffix }
        // Keep hashtags only if they leave most of the room to the text.
        guard !suffix.isEmpty, suffix.count <= limit / 4 else { return truncate(body, to: limit) }
        return truncate(body, to: limit - suffix.count) + suffix
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        guard limit > 1 else { return String(text.prefix(max(limit, 0))) }
        let hard = String(text.prefix(limit - 1))
        let cut = hard.lastIndex(where: { $0 == " " || $0 == "\n" }).map { String(hard[..<$0]) } ?? hard
        return cut.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }

    /// Opens LinkedIn's composer pre-filled (app if installed, web otherwise).
    static func linkedInComposeURL(text: String) -> URL? {
        var components = URLComponents(string: "https://www.linkedin.com/feed/")
        components?.queryItems = [URLQueryItem(name: "shareActive", value: "true"), URLQueryItem(name: "text", value: text)]
        return components?.url
    }

    /// WhatsApp universal link. With a phone number (international format), opens that chat.
    static func whatsAppURL(text: String, phone: String? = nil) -> URL? {
        let digits = phone?.filter(\.isNumber) ?? ""
        var components = URLComponents(string: "https://wa.me/\(digits)")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }

    static func smsURL(phone: String, text: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sms"
        components.path = phone.filter { $0.isNumber || $0 == "+" }
        components.queryItems = [URLQueryItem(name: "body", value: text)]
        return components.url
    }

    static func mailURL(to: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return components.url
    }
}

/// vCard 3.0, readable by Contacts, the Camera QR scanner, Android and every CRM.
nonisolated struct ContactCard: Hashable, Sendable {
    var fullName: String
    var organization = ""
    var title = ""
    var email = ""
    var phone = ""
    var website = ""
    var linkedIn = ""
    var address = ""
    var note = ""

    var vCard: String {
        let parts = fullName.split(separator: " ", maxSplits: 1).map(String.init)
        let first = parts.first ?? ""
        let last = parts.count > 1 ? parts[1] : ""
        var lines = ["BEGIN:VCARD", "VERSION:3.0", "N:\(escape(last));\(escape(first));;;", "FN:\(escape(fullName))"]
        if !organization.isEmpty { lines.append("ORG:\(escape(organization))") }
        if !title.isEmpty { lines.append("TITLE:\(escape(title))") }
        if !email.isEmpty { lines.append("EMAIL;TYPE=INTERNET,WORK:\(email)") }
        if !phone.isEmpty { lines.append("TEL;TYPE=CELL:\(phone)") }
        if !website.isEmpty { lines.append("URL:\(website)") }
        if !linkedIn.isEmpty { lines.append("X-SOCIALPROFILE;TYPE=linkedin:\(linkedIn)") }
        if !address.isEmpty { lines.append("ADR;TYPE=WORK:;;\(escape(address));;;;") }
        if !note.isEmpty { lines.append("NOTE:\(escape(note))") }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n")
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
