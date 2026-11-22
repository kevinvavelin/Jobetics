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

/// iPhone: simple tab bar (Home, Jobs, Board, Messages, Profile). Business tools live under Profile.
/// iPad: the same tabs become a sidebar with a full Business section, Search and Admin.
struct MainTabView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView() }
            Tab("Jobs", systemImage: "briefcase.fill", value: AppTab.jobs) { JobsView() }
            Tab("Board", systemImage: "rectangle.split.3x1.fill", value: AppTab.board) { BoardView() }
            Tab("Messages", systemImage: "bubble.left.and.text.bubble.right.fill", value: AppTab.messages) { MessagesView() }
                .badge(store.unreadCount)
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) { ProfileView() }

            if sizeClass == .regular {
            TabSection("Business") {
                Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) { NavigationStack { JobCalendarView() } }
                Tab("Invoices", systemImage: "doc.text.fill", value: AppTab.invoices) { NavigationStack { BillingListView(kind: .invoice) } }
                Tab("Quotes", systemImage: "doc.text.magnifyingglass", value: AppTab.quotes) { NavigationStack { BillingListView(kind: .quote) } }
                Tab("Accounting", systemImage: "chart.bar.xaxis", value: AppTab.accounting) { NavigationStack { AccountingView() } }
                Tab("Payouts", systemImage: "banknote.fill", value: AppTab.payouts) { NavigationStack { PayoutsView() } }
                Tab("Portfolio", systemImage: "square.grid.2x2.fill", value: AppTab.portfolio) { NavigationStack { PortfolioView() } }
            }
            .defaultVisibility(.hidden, for: .tabBar)
            }

            if store.isAdmin && sizeClass == .regular {
                TabSection("Administration") {
                    Tab("Moderation", systemImage: "checkmark.shield.fill", value: AppTab.admin) { NavigationStack { ModerationQueueView() } }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }

            if sizeClass == .regular {
                Tab(value: AppTab.search, role: .search) { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .defaultAdaptableTabBarPlacement(.sidebar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { NextUpAccessory() }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .focus: FocusView()
            case .postJob: PostJobView()
            }
        }
    }
}
