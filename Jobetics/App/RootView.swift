import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(FocusTimer.self) private var focus
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if !auth.isSignedIn {
                OnboardingView()
            } else if hasLoaded && store.account == nil {
                ProfileSetupView()
            } else {
                MainTabView()
            }
        }
        .task(id: auth.isSignedIn) {
            guard auth.isSignedIn else { return }
            await store.load()
            hasLoaded = true
            if let link = LaunchOptions.value(after: "-deeplink").flatMap(URL.init(string:)) {
                router.handle(link, store: store)
            }
            if !LaunchOptions.isDemo { await PushService.shared.requestAuthorization() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { router.consumePendingRoute(focus: focus) }
        }
    }
}

/// iPhone: the user's own tab bar (Today, Missions, Money, Jobs, Messages by default; editable in Profile ▸ Tab bar).
/// iPad: a sidebar with the full suite, customizable with the system sidebar editing.
struct MainTabView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(TabPreferences.storageKey) private var compactTabsRaw = TabPreferences.encode(TabPreferences.defaultTabs)
    @AppStorage("tabs.sidebar.customization") private var customization: TabViewCustomization

    private var compactTabs: [AppTab] { TabPreferences.decode(compactTabsRaw) }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            if sizeClass == .regular {
                ForEach(TabPreferences.defaultTabs, id: \.self) { tab in
                    Tab(tab.title, systemImage: tab.symbol, value: tab) { tab.root }
                        .badge(tab == .messages ? store.unreadCount : 0)
                        .customizationID(tab.rawValue)
                }
                section("Work", [.calendar, .board, .clients, .journal, .web])
                section("Money", [.invoices, .quotes, .expenses, .accounting, .payouts])
                section("You", [.profile, .card, .portfolio])
                if store.isAdmin { section("Administration", [.admin]) }
                Tab(value: AppTab.search, role: .search) { SearchView() }
                    .customizationID("search")
            } else {
                ForEach(compactTabs, id: \.self) { tab in
                    Tab(tab.title, systemImage: tab.symbol, value: tab) { tab.root }
                        .badge(tab == .messages ? store.unreadCount : 0)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .defaultAdaptableTabBarPlacement(.sidebar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { NextUpAccessory() }
        .onAppear(perform: normalize)
        .onChange(of: sizeClass) { normalize() }
        .onChange(of: router.tab) { normalize() }
        .onChange(of: compactTabsRaw) { normalize() }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .focus: FocusView()
            case .postJob: PostJobView()
            case .profile: ProfileView(isPresented: true)
            }
        }
    }

    private func section(_ title: LocalizedStringKey, _ tabs: [AppTab]) -> some TabContent<AppTab> {
        TabSection(title) {
            ForEach(tabs, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) { tab.root }
                    .customizationID(tab.rawValue)
            }
        }
        .defaultVisibility(.hidden, for: .tabBar)
        .customizationID("section-\(tabs.first?.rawValue ?? "")")
    }

    private func normalize() {
        router.normalize(compact: sizeClass == .compact, available: compactTabs)
    }
}
