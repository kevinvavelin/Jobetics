#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// Sends the freelancer score from iPhone to Apple Watch (application context: latest value wins).
nonisolated final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if os(iOS)
    func send(score: Int, tier: String, openJobs: Int) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired else { return }
        try? WCSession.default.updateApplicationContext(["score": score, "tier": tier, "openJobs": openJobs])
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        if let score = context["score"] as? Int { SharedStore.score = score }
        if let tier = context["tier"] as? String { SharedStore.tier = tier }
        if let jobs = context["openJobs"] as? Int { SharedStore.openJobCount = jobs }
    }
}
#endif
