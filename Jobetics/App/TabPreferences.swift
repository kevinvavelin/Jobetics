import SwiftUI

/// The iPhone tab bar is the user's: they pick up to five destinations and their order.
/// (On iPad the sidebar is customizable with the system's own editing, via `TabViewCustomization`.)
enum TabPreferences {
    static let storageKey = "tabs.compact.v1"
    static let maxTabs = 5
    static let defaultTabs: [AppTab] = [.home, .missions, .money, .jobs, .messages]
    /// Destinations that can be placed in the iPhone tab bar.
    static let choices: [AppTab] = [.home, .missions, .money, .calendar, .jobs, .messages, .board, .journal,
                                    .clients, .invoices, .expenses, .web, .card, .profile]

    static func decode(_ raw: String) -> [AppTab] {
        let tabs = raw.split(separator: ",").compactMap { AppTab(rawValue: String($0)) }.filter(choices.contains)
        var unique: [AppTab] = []
        for tab in tabs where !unique.contains(tab) { unique.append(tab) }
        return unique.isEmpty ? defaultTabs : Array(unique.prefix(maxTabs))
    }

    static func encode(_ tabs: [AppTab]) -> String { tabs.map(\.rawValue).joined(separator: ",") }
}

extension AppTab {
    var title: LocalizedStringKey {
        switch self {
        case .home: "Today"
        case .missions: "Missions"
        case .money: "Money"
        case .jobs: "Jobs"
        case .messages: "Messages"
        case .board: "Board"
        case .profile: "Profile"
        case .calendar: "Calendar"
        case .invoices: "Invoices"
        case .quotes: "Quotes"
        case .expenses: "Expenses"
        case .clients: "Clients"
        case .journal: "Journal"
        case .card: "My card"
        case .web: "Find missions"
        case .accounting: "Accounting"
        case .payouts: "Payouts"
        case .portfolio: "Portfolio"
        case .admin: "Moderation"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .home: "sun.max"
        case .missions: "briefcase"
        case .money: "eurosign.circle"
        case .jobs: "sparkle.magnifyingglass"
        case .messages: "bubble.left.and.bubble.right"
        case .board: "rectangle.split.3x1"
        case .profile: "person.crop.circle"
        case .calendar: "calendar"
        case .invoices: "doc.text"
        case .quotes: "doc.text.magnifyingglass"
        case .expenses: "creditcard"
        case .clients: "person.2"
        case .journal: "book.closed"
        case .card: "qrcode"
        case .web: "globe"
        case .accounting: "chart.bar.xaxis"
        case .payouts: "banknote"
        case .portfolio: "square.grid.2x2"
        case .admin: "checkmark.shield"
        case .search: "magnifyingglass"
        }
    }

    /// Root screen of a destination when shown as a tab.
    @ViewBuilder var root: some View {
        switch self {
        case .home: HomeView()
        case .missions: MissionsView()
        case .money: MoneyView()
        case .jobs: JobsView()
        case .messages: MessagesView()
        case .board: BoardView()
        case .profile: ProfileView()
        case .calendar: NavigationStack { JobCalendarView() }
        case .invoices: NavigationStack { BillingListView(kind: .invoice) }
        case .quotes: NavigationStack { BillingListView(kind: .quote) }
        case .expenses: NavigationStack { ExpensesView() }
        case .clients: NavigationStack { ClientsView() }
        case .journal: NavigationStack { JournalView() }
        case .card: NavigationStack { MyCardView() }
        case .web: NavigationStack { WebMissionSearchView() }
        case .accounting: NavigationStack { AccountingView() }
        case .payouts: NavigationStack { PayoutsView() }
        case .portfolio: NavigationStack { PortfolioView() }
        case .admin: NavigationStack { ModerationQueueView() }
        case .search: SearchView()
        }
    }
}

/// Settings screen: choose and order the iPhone tabs.
struct TabBarSettingsView: View {
    @AppStorage(TabPreferences.storageKey) private var raw = TabPreferences.encode(TabPreferences.defaultTabs)

    private var tabs: [AppTab] { TabPreferences.decode(raw) }
    private var available: [AppTab] { TabPreferences.choices.filter { !tabs.contains($0) } }

    var body: some View {
        List {
            Section {
                ForEach(tabs, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                }
                .onMove { from, to in
                    var list = tabs
                    list.move(fromOffsets: from, toOffset: to)
                    raw = TabPreferences.encode(list)
                }
                .onDelete { offsets in
                    var list = tabs
                    list.remove(atOffsets: offsets)
                    raw = TabPreferences.encode(list.isEmpty ? [.home] : list)
                }
                .deleteDisabled(tabs.count <= 2)
            } header: {
                Text("In your tab bar")
            } footer: {
                Text("Up to \(TabPreferences.maxTabs) tabs. Drag to reorder, swipe to remove.")
            }

            Section("More destinations") {
                ForEach(available, id: \.self) { tab in
                    Button {
                        withAnimation { raw = TabPreferences.encode(tabs + [tab]) }
                    } label: {
                        HStack {
                            Label(tab.title, systemImage: tab.symbol).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(tabs.count < TabPreferences.maxTabs ? Brand.positive : .secondary)
                        }
                    }
                    .disabled(tabs.count >= TabPreferences.maxTabs)
                }
            }

            Section {
                Button("Restore default tabs") { withAnimation { raw = TabPreferences.encode(TabPreferences.defaultTabs) } }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab bar")
    }
}
