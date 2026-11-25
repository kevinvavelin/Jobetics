import AppIntents
import SwiftData

// Siri, Shortcuts, Spotlight and the Action button: the freelancer's daily gestures without opening the app.

struct MissionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mission"
    static let defaultQuery = MissionQuery()

    var id: String
    var title: String
    var client: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(client)", image: .init(systemName: "briefcase.fill"))
    }
}

struct MissionQuery: EntityStringQuery {
    @MainActor
    private func activeMissions() -> [Mission] {
        let context = AppEnvironment.shared.container.mainContext
        return (try? context.fetch(FetchDescriptor<Mission>(predicate: #Predicate { $0.statusRaw == "active" }, sortBy: [SortDescriptor(\.endDate)]))) ?? []
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [MissionEntity] {
        activeMissions().filter { identifiers.contains($0.intentID) }.map(\.entity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [MissionEntity] {
        activeMissions().filter { $0.title.localizedStandardContains(string) || $0.clientName.localizedStandardContains(string) }.map(\.entity)
    }

    @MainActor
    func suggestedEntities() async throws -> [MissionEntity] { activeMissions().map(\.entity) }
}

extension Mission {
    /// Stable identifier for App Intents: the persistent model ID, encoded.
    var intentID: String {
        (try? JSONEncoder().encode(persistentModelID)).map { $0.base64EncodedString() } ?? title
    }
    var entity: MissionEntity { MissionEntity(id: intentID, title: title, client: clientName) }

    @MainActor
    static func find(_ entity: MissionEntity) -> Mission? {
        let context = AppEnvironment.shared.container.mainContext
        let all = (try? context.fetch(FetchDescriptor<Mission>())) ?? []
        return all.first { $0.intentID == entity.id }
    }
}

enum DayAmount: String, AppEnum {
    case full, half
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Amount"
    static let caseDisplayRepresentations: [DayAmount: DisplayRepresentation] = [.full: "Full day", .half: "Half day"]
    var days: Double { self == .full ? 1 : 0.5 }
}

struct LogWorkDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Work Day"
    static let description = IntentDescription("Log a full or half day on a mission in Jobetics.")

    @Parameter(title: "Mission") var mission: MissionEntity
    @Parameter(title: "Amount", default: .full) var amount: DayAmount
    @Parameter(title: "On site", default: false) var onSite: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) on \(\.$mission)") { \.$onSite }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = Mission.find(mission) else { throw $mission.needsValueError() }
        let context = AppEnvironment.shared.container.mainContext
        let today = Calendar.current.startOfDay(for: .now)
        if let existing = (model.logs ?? []).first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            guard !existing.isLocked else { return .result(dialog: "Today is already in a signed activity report.") }
            existing.days = amount.days
            existing.hours = amount.days * 7
            existing.onSite = onSite
        } else {
            let log = WorkLog(date: today, days: amount.days, onSite: onSite)
            log.mission = model
            context.insert(log)
        }
        try? context.save()
        return .result(dialog: "Logged \(amount.days.formatted()) day on \(model.title). \(model.daysLogged.formatted()) days so far.")
    }
}

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add an Expense"
    static let description = IntentDescription("Record a business expense in Jobetics.")

    @Parameter(title: "Amount (€)") var amount: Double
    @Parameter(title: "Description") var title: String
    @Parameter(title: "Rebill to the client", default: false) var rebillable: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) € for \(\.$title)") { \.$rebillable }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppEnvironment.shared.container.mainContext
        let category = ReceiptScanner.category(for: title.lowercased()) ?? .other
        context.insert(Expense(date: .now, title: title, amountCents: Int((amount * 100).rounded()), category: category, isRebillable: rebillable))
        try? context.save()
        return .result(dialog: "Added \(Money(amount).formatted) for \(title).")
    }
}

struct OutstandingAmountIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Am I Owed?"
    static let description = IntentDescription("Tells you the total of unpaid invoices and what's overdue.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let context = AppEnvironment.shared.container.mainContext
        let invoices = (try? context.fetch(FetchDescriptor<BillingDocument>(predicate: #Predicate { $0.kindRaw == "invoice" }))) ?? []
        let unpaid = invoices.filter { ($0.status == .sent || $0.status == .overdue) && !$0.isCancelled }
        let total = Money(cents: unpaid.reduce(0) { $0 + $1.total.cents })
        let overdue = unpaid.filter(\.isOverdue)
        guard !unpaid.isEmpty else { return .result(value: 0, dialog: "Every invoice is paid. Nice.") }
        let overdueText = overdue.isEmpty ? "" : String(localized: " \(overdue.count) overdue.")
        return .result(value: total.amount, dialog: "You're owed \(total.formatted) across \(unpaid.count) invoices.\(overdueText)")
    }
}

nonisolated struct JobeticsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWorkDayIntent(),
                    phrases: ["Log a day in \(.applicationName)", "Log my day on \(\.$mission) in \(.applicationName)"],
                    shortTitle: "Log a Day", systemImageName: "calendar.badge.plus")
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Add an expense in \(.applicationName)"],
                    shortTitle: "Add Expense", systemImageName: "creditcard")
        AppShortcut(intent: OutstandingAmountIntent(),
                    phrases: ["How much am I owed in \(.applicationName)", "Unpaid invoices in \(.applicationName)"],
                    shortTitle: "Amount Owed", systemImageName: "hourglass")
        AppShortcut(intent: StartFocusIntent(),
                    phrases: ["Start focus in \(.applicationName)", "Start a Pomodoro in \(.applicationName)"],
                    shortTitle: "Start Focus", systemImageName: "timer")
    }
}
