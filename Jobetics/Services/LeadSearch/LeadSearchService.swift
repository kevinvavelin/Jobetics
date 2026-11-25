import Foundation
import Security

/// Searches every enabled provider in parallel and returns ranked, de-duplicated leads.
/// Only the search words leave the device: never the user's name, e-mail or profile.
nonisolated struct LeadSearchOutcome: Sendable {
    var results: [LeadResult]
    /// Providers that failed, with a short reason, shown discreetly under the results.
    var failures: [LeadSource: String]
}

nonisolated struct LeadSearchConfiguration: Sendable {
    var enabled: Set<LeadSource>
    var braveKey: String?
    var googleKey: String?
    var googleEngineID: String?
}

nonisolated enum LeadSearchService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "Jobetics-iOS/1.0", "Accept": "application/json"]
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 30_000_000)
        return URLSession(configuration: config)
    }()

    @concurrent
    static func search(_ query: String, skills: [String], freelanceOnly: Bool, configuration: LeadSearchConfiguration) async -> LeadSearchOutcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return LeadSearchOutcome(results: [], failures: [:]) }
        let sources = configuration.enabled.filter { source in
            switch source {
            case .brave: !(configuration.braveKey ?? "").isEmpty
            case .google: !(configuration.googleKey ?? "").isEmpty && !(configuration.googleEngineID ?? "").isEmpty
            default: true
            }
        }
        var all: [LeadResult] = []
        var failures: [LeadSource: String] = [:]
        await withTaskGroup(of: (LeadSource, Result<[LeadResult], Error>).self) { group in
            for source in sources {
                group.addTask {
                    do { return (source, .success(try await fetch(source, query: trimmed, freelanceOnly: freelanceOnly, configuration: configuration))) }
                    catch { return (source, .failure(error)) }
                }
            }
            for await (source, result) in group {
                switch result {
                case .success(let items): all += items
                case .failure(let error): failures[source] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        return LeadSearchOutcome(results: LeadRanking.rank(all, skills: skills, freelanceOnly: freelanceOnly), failures: failures)
    }

    static func request(for source: LeadSource, query: String, freelanceOnly: Bool, configuration: LeadSearchConfiguration) -> URLRequest? {
        var components: URLComponents?
        switch source {
        case .remotive:
            components = URLComponents(string: "https://remotive.com/api/remote-jobs")
            components?.queryItems = [URLQueryItem(name: "search", value: query), URLQueryItem(name: "limit", value: "30")]
        case .jobicy:
            components = URLComponents(string: "https://jobicy.com/api/v2/remote-jobs")
            components?.queryItems = [URLQueryItem(name: "count", value: "30"), URLQueryItem(name: "tag", value: query)]
        case .himalayas:
            components = URLComponents(string: "https://himalayas.app/jobs/api/search")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
                + (freelanceOnly ? [URLQueryItem(name: "employment_type", value: "Contractor")] : [])
        case .brave:
            components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
            components?.queryItems = [URLQueryItem(name: "q", value: LeadRanking.webQuery(for: query)), URLQueryItem(name: "count", value: "20"),
                                      URLQueryItem(name: "freshness", value: "pm")]
        case .google:
            components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")
            components?.queryItems = [URLQueryItem(name: "key", value: configuration.googleKey), URLQueryItem(name: "cx", value: configuration.googleEngineID),
                                      URLQueryItem(name: "q", value: LeadRanking.webQuery(for: query)), URLQueryItem(name: "num", value: "10"),
                                      URLQueryItem(name: "dateRestrict", value: "m1")]
        }
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        if source == .brave, let key = configuration.braveKey { request.setValue(key, forHTTPHeaderField: "X-Subscription-Token") }
        return request
    }

    private static func fetch(_ source: LeadSource, query: String, freelanceOnly: Bool, configuration: LeadSearchConfiguration) async throws -> [LeadResult] {
        guard let request = request(for: source, query: query, freelanceOnly: freelanceOnly, configuration: configuration) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw LeadSearchError.http(status) }
        return switch source {
        case .remotive: try LeadParsers.remotive(data)
        case .jobicy: try LeadParsers.jobicy(data)
        case .himalayas: try LeadParsers.himalayas(data)
        case .brave: try LeadParsers.brave(data)
        case .google: try LeadParsers.google(data)
        }
    }
}

nonisolated enum LeadSearchError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(401), .http(403): String(localized: "API key refused")
        case .http(429): String(localized: "Too many searches, try again later")
        case .http(let code): String(localized: "Unavailable (\(code))")
        }
    }
}

/// API keys belong in the Keychain, never in UserDefaults or the repository.
nonisolated enum KeychainStore {
    private static let service = "fr.vavelinkevin.Jobetics.search"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
