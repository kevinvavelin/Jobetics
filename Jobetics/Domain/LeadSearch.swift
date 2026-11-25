import Foundation

// Lead search: results from job APIs and web search providers, normalized into one model.
// Pure parsing only (no networking), so every provider is unit tested with real payload shapes.

nonisolated enum ContractKind: String, Codable, CaseIterable, Sendable {
    case freelance, partTime, fullTime, unknown

    var title: String {
        switch self {
        case .freelance: String(localized: "Freelance / contract")
        case .partTime: String(localized: "Part-time")
        case .fullTime: String(localized: "Full-time")
        case .unknown: String(localized: "Not specified")
        }
    }

    /// Maps the many spellings used by job boards.
    static func from(_ raw: [String]) -> ContractKind {
        let text = raw.joined(separator: " ").lowercased()
        if ["contract", "freelance", "contractor", "freelancer", "indépendant", "independant", "mission", "temporary"].contains(where: text.contains) {
            return .freelance
        }
        if text.contains("part") { return .partTime }
        if text.contains("full") || text.contains("permanent") || text.contains("cdi") || text.contains("unbefristet") { return .fullTime }
        return .unknown
    }
}

nonisolated struct ParsedRate: Hashable, Codable, Sendable {
    enum Unit: String, Codable, Sendable { case hour, day, month, year }
    var minCents: Int
    var maxCents: Int?
    var currency: String
    var unit: Unit

    /// Daily equivalent, for comparing with the freelancer's target rate (7 h days, 218 days a year).
    var dailyCents: Int {
        let base = maxCents.map { ($0 + minCents) / 2 } ?? minCents
        return switch unit {
        case .hour: base * 7
        case .day: base
        case .month: base / 20
        case .year: base / 218
        }
    }

    var formatted: String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency).precision(.fractionLength(0))
        let min = (Double(minCents) / 100).formatted(style)
        let range = maxCents.map { "\(min)–\((Double($0) / 100).formatted(style))" } ?? min
        let suffix = switch unit {
        case .hour: String(localized: "/h")
        case .day: String(localized: "/day")
        case .month: String(localized: "/month")
        case .year: String(localized: "/year")
        }
        return range + suffix
    }
}

nonisolated struct LeadResult: Identifiable, Hashable, Sendable {
    var id: String { url.absoluteString }
    var title: String
    var company: String
    var location: String
    var isRemote: Bool
    var contract: ContractKind
    var rate: ParsedRate?
    var tags: [String]
    var postedAt: Date?
    /// Short plain-text summary for the list.
    var summary: String
    /// Full description as plain text with paragraphs and bullets kept.
    var details: String
    /// Original listing: "Apply" always opens it (required by the providers' terms).
    var url: URL
    var logoURL: URL?
    var source: LeadSource

    /// 0…1: share of the freelancer's skills found in the listing.
    func match(skills: [String]) -> Double {
        let wanted = skills.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return 0 }
        let haystack = ([title, summary, details] + tags).joined(separator: " ").lowercased()
        return Double(wanted.filter { haystack.contains($0) }.count) / Double(wanted.count)
    }
}

nonisolated enum LeadSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case remotive, jobicy, himalayas, brave, google

    var id: String { rawValue }

    var name: String {
        switch self {
        case .remotive: "Remotive"
        case .jobicy: "Jobicy"
        case .himalayas: "Himalayas"
        case .brave: "Brave Search"
        case .google: "Google"
        }
    }

    var homepage: URL {
        switch self {
        case .remotive: URL(string: "https://remotive.com")!
        case .jobicy: URL(string: "https://jobicy.com")!
        case .himalayas: URL(string: "https://himalayas.app")!
        case .brave: URL(string: "https://search.brave.com")!
        case .google: URL(string: "https://www.google.com")!
        }
    }

    /// Job boards answer without an API key; web search providers need the user's own key.
    var needsAPIKey: Bool { self == .brave || self == .google }
    var isWebSearch: Bool { needsAPIKey }
}

// MARK: - Text helpers

nonisolated enum HTMLText {
    /// Converts listing HTML into readable plain text: paragraphs, line breaks and bullets are kept,
    /// tags, scripts and styles are dropped, common entities decoded. Never loads remote content.
    static func plain(_ html: String) -> String {
        var text = html
        text = text.replacing(/(?is)<(script|style)[^>]*>.*?<\/\1>/, with: "")
        text = text.replacing(/(?i)<li[^>]*>/, with: "\n• ")
        text = text.replacing(/(?i)<br\s*\/?>/, with: "\n")
        text = text.replacing(/(?i)<\/(p|div|h[1-6]|ul|ol|tr|section)>/, with: "\n")
        text = text.replacing(/(?i)<\/li>/, with: "")
        text = text.replacing(/(?i)<(p|div|h[1-6]|ul|ol|tr|section)[^>]*>/, with: "\n")
        text = text.replacing(/<[^>]+>/, with: "")
        text = decodeEntities(text)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line.replacing(/[ \t\u{00A0}]{2,}/, with: " "))
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        var out = text
        let named = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&ndash;": "–", "&mdash;": "—",
                     "&hellip;": "…", "&euro;": "€", "&eacute;": "é", "&egrave;": "è", "&agrave;": "à", "&ccedil;": "ç"]
        for (entity, value) in named { out = out.replacingOccurrences(of: entity, with: value) }
        out = out.replacing(/&#(x?)([0-9a-fA-F]+);/) { match in
            let radix = match.output.1.isEmpty ? 10 : 16
            guard let code = UInt32(match.output.2, radix: radix), let scalar = Unicode.Scalar(code) else { return "" }
            return String(Character(scalar))
        }
        return out
    }

    static func excerpt(_ text: String, length: Int = 220) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacing(/\s{2,}/, with: " ")
        return SocialShare.truncate(flat, to: length)
    }
}

/// Finds a rate in free text: "€500/day", "TJM 600 €", "550 € par jour", "$80-100/hour", "60k€/an".
nonisolated enum RateExtractor {
    static func parse(_ text: String, defaultCurrency: String = "EUR") -> ParsedRate? {
        let lower = text.lowercased()
        let pattern = /(?:(€|\$|£|eur|usd|gbp)\s?)?(\d{1,3}(?:[ ,.\u{202F}]\d{3})*|\d+)(k)?\s?(?:(?:-|–|to|à)\s?(?:€|\$|£)?\s?(\d{1,3}(?:[ ,.\u{202F}]\d{3})*|\d+)(k)?)?\s?(€|\$|£|eur|usd|gbp)?\s?(?:ht\s?)?(?:\/|per|par|a|an|by)?\s?(jour|day|daily|j\b|hour|heure|hr|h\b|month|mois|year|an\b|annum|yr)/
        for match in lower.matches(of: pattern) {
            let symbol = String(match.output.1 ?? match.output.6 ?? "")
            let tjm = lower[..<match.range.lowerBound].suffix(12).contains("tjm")
            guard !symbol.isEmpty || tjm else { continue }
            guard let min = amount(String(match.output.2), thousands: match.output.3 != nil) else { continue }
            let max = match.output.4.flatMap { amount(String($0), thousands: match.output.5 != nil) }
            let unit: ParsedRate.Unit = switch String(match.output.7) {
            case "jour", "day", "daily", "j": .day
            case "hour", "heure", "hr", "h": .hour
            case "month", "mois": .month
            default: .year
            }
            return ParsedRate(minCents: min, maxCents: max.flatMap { $0 > min ? $0 : nil }, currency: currency(symbol, fallback: defaultCurrency), unit: unit)
        }
        if let match = lower.firstMatch(of: /tjm\s?:?\s?(\d{3,4})/), let value = Int(match.output.1) {
            return ParsedRate(minCents: value * 100, currency: defaultCurrency, unit: .day)
        }
        return nil
    }

    private static func amount(_ raw: String, thousands: Bool) -> Int? {
        let digits = raw.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return (thousands ? value * 1000 : value) * 100
    }

    private static func currency(_ symbol: String, fallback: String) -> String {
        switch symbol {
        case "$", "usd": "USD"
        case "£", "gbp": "GBP"
        case "€", "eur": "EUR"
        default: fallback
        }
    }
}

// MARK: - Provider parsers

nonisolated enum LeadParsers {
    private static let iso = ISO8601DateFormatter()

    private static func isoDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let date = iso.date(from: string) { return date }
        return iso.date(from: string + "Z") // Remotive omits the time zone (UTC)
    }

    // Remotive: GET https://remotive.com/api/remote-jobs?search=…&limit=…
    private struct RemotiveResponse: Decodable { var jobs: [Job]
        struct Job: Decodable {
            var url: String; var title: String; var company_name: String; var company_logo: String?
            var tags: [String]?; var job_type: String?; var publication_date: String?
            var candidate_required_location: String?; var salary: String?; var description: String?
        }
    }

    static func remotive(_ data: Data) throws -> [LeadResult] {
        try JSONDecoder().decode(RemotiveResponse.self, from: data).jobs.compactMap { job in
            guard let url = URL(string: job.url) else { return nil }
            let details = HTMLText.plain(job.description ?? "")
            return LeadResult(title: job.title, company: job.company_name, location: job.candidate_required_location ?? "",
                              isRemote: true, contract: .from([job.job_type ?? ""]),
                              rate: RateExtractor.parse(job.salary ?? "") ?? RateExtractor.parse(details),
                              tags: job.tags ?? [], postedAt: isoDate(job.publication_date), summary: HTMLText.excerpt(details),
                              details: details, url: url, logoURL: job.company_logo.flatMap(URL.init(string:)), source: .remotive)
        }
    }

    // Jobicy: GET https://jobicy.com/api/v2/remote-jobs?count=…&tag=…
    private struct JobicyResponse: Decodable { var jobs: [Job]?
        struct Job: Decodable {
            var url: String; var jobTitle: String; var companyName: String; var companyLogo: String?
            var jobIndustry: [String]?; var jobType: [String]?; var jobGeo: String?
            var jobExcerpt: String?; var jobDescription: String?; var pubDate: String?
            var salaryMin: Double?; var salaryMax: Double?; var salaryCurrency: String?; var salaryPeriod: String?
        }
    }

    static func jobicy(_ data: Data) throws -> [LeadResult] {
        (try JSONDecoder().decode(JobicyResponse.self, from: data).jobs ?? []).compactMap { job in
            guard let url = URL(string: job.url) else { return nil }
            let details = HTMLText.plain(job.jobDescription ?? "")
            var rate: ParsedRate?
            if let min = job.salaryMin, min > 0 {
                rate = ParsedRate(minCents: Int(min * 100), maxCents: job.salaryMax.map { Int($0 * 100) }, currency: job.salaryCurrency ?? "USD",
                                  unit: unit(job.salaryPeriod))
            }
            return LeadResult(title: HTMLText.decodeEntities(job.jobTitle), company: HTMLText.decodeEntities(job.companyName),
                              location: job.jobGeo ?? "", isRemote: true, contract: .from(job.jobType ?? []),
                              rate: rate ?? RateExtractor.parse(details), tags: job.jobIndustry ?? [], postedAt: isoDate(job.pubDate),
                              summary: HTMLText.excerpt(HTMLText.plain(job.jobExcerpt ?? details)), details: details, url: url,
                              logoURL: job.companyLogo.flatMap(URL.init(string:)), source: .jobicy)
        }
    }

    // Himalayas: GET https://himalayas.app/jobs/api/search?q=…&employment_type=Contractor
    private struct HimalayasResponse: Decodable { var jobs: [Job]?
        struct Job: Decodable {
            var title: String; var excerpt: String?; var companyName: String; var companyLogo: String?
            var employmentType: String?; var minSalary: Double?; var maxSalary: Double?; var salaryPeriod: String?
            var currency: String?; var locationRestrictions: [String]?; var categories: [String]?
            var description: String?; var pubDate: Double?; var applicationLink: String?; var guid: String?
        }
    }

    static func himalayas(_ data: Data) throws -> [LeadResult] {
        (try JSONDecoder().decode(HimalayasResponse.self, from: data).jobs ?? []).compactMap { job in
            guard let url = (job.guid ?? job.applicationLink).flatMap(URL.init(string:)) else { return nil }
            let details = HTMLText.plain(job.description ?? "")
            var rate: ParsedRate?
            if let min = job.minSalary, min > 0 {
                rate = ParsedRate(minCents: Int(min * 100), maxCents: job.maxSalary.map { Int($0 * 100) }, currency: job.currency ?? "USD",
                                  unit: unit(job.salaryPeriod))
            }
            let locations = job.locationRestrictions ?? []
            return LeadResult(title: job.title, company: job.companyName,
                              location: locations.isEmpty ? String(localized: "Worldwide") : locations.joined(separator: ", "),
                              isRemote: true, contract: .from([job.employmentType ?? ""]), rate: rate ?? RateExtractor.parse(details),
                              tags: (job.categories ?? []).prefix(6).map { $0.replacingOccurrences(of: "-", with: " ") },
                              postedAt: job.pubDate.map { Date(timeIntervalSince1970: $0) },
                              summary: HTMLText.excerpt(job.excerpt ?? details), details: details, url: url,
                              logoURL: job.companyLogo.flatMap(URL.init(string:)), source: .himalayas)
        }
    }

    // Brave Search API: GET https://api.search.brave.com/res/v1/web/search?q=… (header X-Subscription-Token)
    private struct BraveResponse: Decodable { var web: Web?
        struct Web: Decodable { var results: [Result] }
        struct Result: Decodable { var title: String; var url: String; var description: String?; var page_age: String? }
    }

    static func brave(_ data: Data) throws -> [LeadResult] {
        (try JSONDecoder().decode(BraveResponse.self, from: data).web?.results ?? []).compactMap { item in
            webResult(title: item.title, link: item.url, snippet: item.description ?? "", date: isoDate(item.page_age), source: .brave)
        }
    }

    // Google Programmable Search (Custom Search JSON API): GET https://www.googleapis.com/customsearch/v1?key=…&cx=…&q=…
    private struct GoogleResponse: Decodable { var items: [Item]?
        struct Item: Decodable { var title: String; var link: String; var snippet: String? }
    }

    static func google(_ data: Data) throws -> [LeadResult] {
        (try JSONDecoder().decode(GoogleResponse.self, from: data).items ?? []).compactMap { item in
            webResult(title: item.title, link: item.link, snippet: item.snippet ?? "", date: nil, source: .google)
        }
    }

    /// Web results carry no structure: company and rate are inferred from the title, host and snippet.
    static func webResult(title rawTitle: String, link: String, snippet rawSnippet: String, date: Date?, source: LeadSource) -> LeadResult? {
        guard let url = URL(string: link), let host = url.host() else { return nil }
        let title = HTMLText.plain(rawTitle)
        let snippet = HTMLText.plain(rawSnippet)
        let board = host.replacingOccurrences(of: "www.", with: "")
        // "Senior iOS developer - Acme | Malt" → company "Acme"
        let parts = title.split(whereSeparator: { "|–-—·".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }
        let company = parts.count >= 3 ? parts[1] : ""
        let text = title + " " + snippet
        return LeadResult(title: parts.first ?? title, company: company, location: board,
                          isRemote: text.lowercased().contains("remote") || text.lowercased().contains("télétravail"),
                          contract: .from([text]), rate: RateExtractor.parse(text), tags: [], postedAt: date,
                          summary: snippet, details: snippet, url: url, logoURL: nil, source: source)
    }

    private static func unit(_ period: String?) -> ParsedRate.Unit {
        switch period?.lowercased() ?? "" {
        case "hourly", "hour": .hour
        case "daily", "day": .day
        case "monthly", "month": .month
        default: .year
        }
    }
}

nonisolated enum LeadRanking {
    /// Freelance listings first, then best skill match, then most recent. Duplicates (same title + company) removed.
    static func rank(_ results: [LeadResult], skills: [String], freelanceOnly: Bool) -> [LeadResult] {
        var seen = Set<String>()
        let unique = results.filter { result in
            let key = (result.title + "|" + result.company).lowercased()
            return seen.insert(key).inserted
        }
        let filtered = freelanceOnly ? unique.filter { $0.contract == .freelance || $0.source.isWebSearch } : unique
        return filtered.sorted { a, b in
            let ma = a.match(skills: skills), mb = b.match(skills: skills)
            if (a.contract == .freelance) != (b.contract == .freelance) { return a.contract == .freelance }
            if abs(ma - mb) > 0.01 { return ma > mb }
            return (a.postedAt ?? .distantPast) > (b.postedAt ?? .distantPast)
        }
    }

    /// Query sent to web search providers: freelance missions on the boards freelancers use.
    static func webQuery(for query: String) -> String {
        "\(query) freelance mission (site:malt.fr OR site:free-work.com OR site:linkedin.com/jobs OR site:welcometothejungle.com OR site:codeur.com)"
    }
}
