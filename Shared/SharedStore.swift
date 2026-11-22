import Foundation

/// Tiny snapshot of a job, cheap enough to hand to widgets and the watch.
nonisolated struct JobSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var disciplineSymbol: String
    var budget: String
    var postedAt: Date
}

/// Values shared between the app, widgets and watch through the App Group.
/// Contains no personal data: only counts, scores and job titles.
nonisolated enum SharedStore {
    static let appGroup = "group.fr.vavelinkevin.Jobetics"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private enum Key {
        static let focusSession = "focusSession"
        static let focusSettings = "focusSettings"
        static let focusCompleted = "focusCompleted"
        static let focusMinutes = "focusMinutes"
        static let focusDate = "focusDate"
        static let score = "score"
        static let tier = "tier"
        static let jobs = "matchedJobs"
        static let jobCount = "openJobCount"
        static let pendingRoute = "pendingRoute"
    }

    static var focusSession: FocusSession {
        get { decode(FocusSession.self, Key.focusSession) ?? FocusSession() }
        set { encode(newValue, Key.focusSession) }
    }

    static var focusSettings: FocusSettings {
        get { decode(FocusSettings.self, Key.focusSettings) ?? FocusSettings() }
        set { encode(newValue, Key.focusSettings) }
    }

    /// Focus sessions completed today (resets at midnight).
    static var focusCompletedToday: Int {
        get { isToday ? defaults.integer(forKey: Key.focusCompleted) : 0 }
        set { touchToday(); defaults.set(newValue, forKey: Key.focusCompleted) }
    }

    static var focusMinutesToday: Int {
        get { isToday ? defaults.integer(forKey: Key.focusMinutes) : 0 }
        set { touchToday(); defaults.set(newValue, forKey: Key.focusMinutes) }
    }

    private static var isToday: Bool {
        (defaults.object(forKey: Key.focusDate) as? Date).map(Calendar.current.isDateInToday) ?? false
    }

    private static func touchToday() {
        if !isToday {
            defaults.set(0, forKey: Key.focusCompleted)
            defaults.set(0, forKey: Key.focusMinutes)
        }
        defaults.set(Date.now, forKey: Key.focusDate)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    static var score: Int {
        get { defaults.integer(forKey: Key.score) }
        set { defaults.set(newValue, forKey: Key.score) }
    }

    static var tier: String {
        get { defaults.string(forKey: Key.tier) ?? FreelancerScore.Tier.rising.title }
        set { defaults.set(newValue, forKey: Key.tier) }
    }

    static var openJobCount: Int {
        get { defaults.integer(forKey: Key.jobCount) }
        set { defaults.set(newValue, forKey: Key.jobCount) }
    }

    static var matchedJobs: [JobSnapshot] {
        get {
            guard let data = defaults.data(forKey: Key.jobs) else { return [] }
            return (try? JSONDecoder().decode([JobSnapshot].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.jobs) }
    }

    /// Route requested by a widget / control (e.g. "focus-start"), consumed by the app on activation.
    static var pendingRoute: String? {
        get { defaults.string(forKey: Key.pendingRoute) }
        set { defaults.set(newValue, forKey: Key.pendingRoute) }
    }
}
