import Foundation
import SwiftData

/// Launch configuration. The app runs in **demo mode** when Firebase isn't configured
/// (no GoogleService-Info.plist, which is git-ignored) or when launched with `-demo`.
enum LaunchOptions {
    static let arguments = ProcessInfo.processInfo.arguments
    static let hasFirebaseConfig = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    static let isDemo = arguments.contains("-demo") || !hasFirebaseConfig
    static let firebaseAvailable = hasFirebaseConfig && !arguments.contains("-demo")
    static let isScreenshotRun = arguments.contains("-screenshots")

    /// `-tab jobs` opens a given tab; `-route invoice` pushes a screen (screenshots/UI tests).
    static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
        return arguments[i + 1]
    }
}

@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let container: ModelContainer
    let store: MarketplaceStore
    let auth: AuthService
    let router = AppRouter()
    let browser = SafeBrowser()
    let focus = FocusTimer()
    let settings: SettingsStore

    private init() {
        let demo = LaunchOptions.isDemo
        container = Self.makeContainer(demo: demo)
        settings = demo ? SettingsStore(defaults: UserDefaults(suiteName: "demo") ?? .standard, syncsWithICloud: false) : SettingsStore()
        let backend: MarketplaceBackend = demo ? DemoBackend() : FirestoreBackend()
        store = MarketplaceStore(backend: backend, moderation: ModerationService(isEnabled: !demo))
        auth = AuthService(demo: demo)
        if demo {
            DemoSeed.seedIfNeeded(container.mainContext)
            FreelanceSeed.seedIfNeeded(container.mainContext, settings: settings)
            focus.loadDemo()
        }
        if let tab = LaunchOptions.value(after: "-tab").flatMap(AppTab.init(rawValue:)) { router.tab = tab }
        if let route = LaunchOptions.value(after: "-mode"), route == "hiring" { store.mode = .hiring }

        PushService.shared.onToken = { [store] token in Task { await store.backend.registerPushToken(token) } }
        PushService.shared.onOpen = { [router, store] url in router.handle(url, store: store) }
    }

    /// Private business data syncs through the user's iCloud (CloudKit private database).
    private static func makeContainer(demo: Bool) -> ModelContainer {
        let schema = Schema(BusinessSchema.models)
        if demo {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: config)
        }
        // CloudKit traps (rather than throws) without the iCloud entitlement, e.g. unsigned test builds,
        // so only sync when an iCloud account is available. Same store file: sync starts once signed in.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let hasICloudAccount = FileManager.default.ubiquityIdentityToken != nil
        do {
            let database: ModelConfiguration.CloudKitDatabase = (!isTesting && hasICloudAccount)
                ? .private("iCloud.fr.vavelinkevin.Jobetics") : .none
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: database)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // e.g. unsigned build without the iCloud entitlement: keep data local.
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do { return try ModelContainer(for: schema, configurations: config) }
            catch { fatalError("Could not create ModelContainer: \(error)") }
        }
    }
}
