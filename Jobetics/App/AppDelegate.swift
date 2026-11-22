import FirebaseAppCheck
import FirebaseCore
import FirebaseMessaging
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseBootstrap.configureIfNeeded()
        PushService.shared.configure(messagingEnabled: LaunchOptions.firebaseAvailable)
        WatchSync.shared.activate()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard LaunchOptions.firebaseAvailable else { return }
        Messaging.messaging().apnsToken = deviceToken
    }
}

enum FirebaseBootstrap {
    /// Idempotent. App Check must be set up BEFORE FirebaseApp.configure(): it protects Gemini,
    /// Firestore and Auth from requests that don't come from this genuine app.
    static func configureIfNeeded() {
        guard LaunchOptions.firebaseAvailable, FirebaseApp.app() == nil else { return }
        AppCheck.setAppCheckProviderFactory(JobeticsAppCheckProviderFactory())
        FirebaseApp.configure()
    }
}

/// Debug builds use the App Check debug provider (register the token printed in the Xcode
/// console in the Firebase console, and never commit it). Release builds use App Attest.
final class JobeticsAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}
