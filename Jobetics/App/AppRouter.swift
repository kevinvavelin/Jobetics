import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    // iPhone tab bar
    case home, missions, money, jobs, messages
    // iPad sidebar destinations (on iPhone they're reached from Missions, Money or Profile)
    case board, profile, calendar, invoices, quotes, expenses, clients, journal, card, web
    case accounting, payouts, portfolio, admin
    case search

}

enum AppSheet: String, Identifiable {
    case focus, postJob, profile
    var id: String { rawValue }
}

@Observable
final class AppRouter {
    var tab: AppTab = .home
    var jobsPath: [JobPost] = []
    var messagesPath: [Conversation] = []
    var sheet: AppSheet?
    /// Conversation requested by a deep link before conversations finished loading.
    var pendingConversationID: String?

    /// `jobetics://jobs/{id}`, `jobetics://chat/{id}`, `jobetics://focus`, `jobetics://post-job`
    func handle(_ url: URL, store: MarketplaceStore) {
        guard url.scheme == "jobetics" else { return }
        let id = url.pathComponents.dropFirst().first
        switch url.host() {
        case "jobs":
            tab = .jobs
            if let id, let job = (store.openJobs + store.myJobs).first(where: { $0.id == id }) { jobsPath = [job] }
        case "chat":
            tab = .messages
            if let id, let conversation = store.conversations.first(where: { $0.id == id }) {
                messagesPath = [conversation]
            } else {
                pendingConversationID = id
            }
        case "missions": tab = .missions
        case "money": tab = .money
        case "profile": sheet = .profile
        case "focus": sheet = .focus
        case "post-job": sheet = .postJob
        default: tab = .home
        }
    }

    /// On iPhone, destinations that aren't in the user's tab bar map to the tab that hosts them.
    func normalize(compact: Bool, available: [AppTab]) {
        guard compact, !available.contains(tab) else { return }
        let host: AppTab? = switch tab {
        case .board, .clients, .calendar, .web: .missions
        case .invoices, .quotes, .expenses, .accounting, .payouts: .money
        default: nil
        }
        if let host, available.contains(host) {
            tab = host
        } else {
            if [.profile, .card, .journal, .portfolio, .admin].contains(tab) { sheet = .profile }
            tab = available.first ?? .home
        }
    }

    func consumePendingRoute(focus: FocusTimer) {
        focus.refresh()
        guard let route = SharedStore.pendingRoute else { return }
        SharedStore.pendingRoute = nil
        if route == "focus-start" {
            if !focus.session.isRunning { focus.start() }
            sheet = .focus
        }
    }
}
