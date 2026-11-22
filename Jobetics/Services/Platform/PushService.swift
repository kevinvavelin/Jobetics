import FirebaseMessaging
import UIKit
import UserNotifications

/// Push notifications through Firebase Cloud Messaging.
/// Sent by Cloud Functions when a message arrives or a job matching your alerts is published.
final class PushService: NSObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = PushService()

    var onToken: ((String) -> Void)?
    var onOpen: ((URL) -> Void)?

    func configure(messagingEnabled: Bool) {
        UNUserNotificationCenter.current().delegate = self
        if messagingEnabled { Messaging.messaging().delegate = self }
    }

    func requestAuthorization() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in self.onToken?(fcmToken) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Payload contains `link`, e.g. `jobetics://chat/{conversationId}` or `jobetics://jobs/{jobId}`.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["link"] as? String,
              let url = URL(string: raw), url.scheme == "jobetics" else { return }
        await MainActor.run { self.onOpen?(url) }
    }
}
