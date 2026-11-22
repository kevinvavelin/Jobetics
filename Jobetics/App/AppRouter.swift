import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case home, jobs, board, messages, profile
    // iPad sidebar destinations (on iPhone they live under Profile)
    case calendar, invoices, quotes, accounting, payouts, portfolio, admin
    case search
}

enum AppSheet: String, Identifiable {
    case focus, postJob
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
        case "focus": sheet = .focus
        case "post-job": sheet = .postJob
        default: tab = .home
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
