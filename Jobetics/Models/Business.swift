import Foundation
import SwiftData

// Private business data. Stored with SwiftData and synced across the user's devices
// through their own iCloud (CloudKit private database). Never sent to Firebase.
//
// CloudKit rules: every attribute has a default, relationships are optional,
// and there are no unique constraints.

@Model
final class Project {
    var name: String = ""
    var clientName: String = ""
    var colorName: String = "blue"
    var symbol: String = "folder.fill"
    var startDate: Date = Date.now
    var dueDate: Date = Date.now
    var budgetCents: Int = 0
    var isArchived: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \BoardTask.project) var tasks: [BoardTask]? = []
    @Relationship(deleteRule: .cascade, inverse: \Meeting.project) var meetings: [Meeting]? = []

    init(name: String, clientName: String, colorName: String, symbol: String, startDate: Date, dueDate: Date, budgetCents: Int) {
        self.name = name
        self.clientName = clientName
        self.colorName = colorName
        self.symbol = symbol
        self.startDate = startDate
        self.dueDate = dueDate
        self.budgetCents = budgetCents
    }

    var sortedTasks: [BoardTask] { (tasks ?? []).sorted { $0.order < $1.order } }
    var progress: Double {
        let all = tasks ?? []
        guard !all.isEmpty else { return 0 }
        return Double(all.filter { $0.status == .done }.count) / Double(all.count)
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, doing, review, done
    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: String(localized: "To do")
        case .doing: String(localized: "In progress")
        case .review: String(localized: "Review")
        case .done: String(localized: "Done")
        }
    }

    var symbol: String {
        switch self {
        case .todo: "circle.dashed"
        case .doing: "circle.lefthalf.filled"
        case .review: "eye.circle"
        case .done: "checkmark.circle.fill"
        }
    }
}

@Model
final class BoardTask {
    var title: String = ""
    var notes: String = ""
    var statusRaw: String = TaskStatus.todo.rawValue
    var order: Double = 0
    var dueDate: Date?
    var estimateHours: Double = 0
    /// Pomodoro sessions completed on this task.
    var focusSessions: Int = 0
    var project: Project?

    init(title: String, status: TaskStatus = .todo, order: Double = 0, dueDate: Date? = nil, estimateHours: Double = 0) {
        self.title = title
        self.statusRaw = status.rawValue
        self.order = order
        self.dueDate = dueDate
        self.estimateHours = estimateHours
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class Meeting {
    var title: String = ""
    var date: Date = Date.now
    var durationMinutes: Int = 30
    /// nil = upcoming, true = joined on time, false = late or missed. Feeds punctuality.
    var onTime: Bool?
    var project: Project?

    init(title: String, date: Date, durationMinutes: Int = 30, onTime: Bool? = nil) {
        self.title = title
        self.date = date
        self.durationMinutes = durationMinutes
        self.onTime = onTime
    }
}

enum BillingKind: String, Codable, CaseIterable, Identifiable {
    case quote, invoice
    var id: String { rawValue }
    var title: String { self == .quote ? String(localized: "Quote") : String(localized: "Invoice") }
    var plural: String { self == .quote ? String(localized: "Quotes") : String(localized: "Invoices") }
    var prefix: String { self == .quote ? "Q" : "INV" }
    var symbol: String { self == .quote ? "doc.text.magnifyingglass" : "doc.text.fill" }
}

enum BillingStatus: String, Codable, CaseIterable, Identifiable {
    case draft, sent, accepted, declined, paid, overdue
    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: String(localized: "Draft")
        case .sent: String(localized: "Sent")
        case .accepted: String(localized: "Accepted")
        case .declined: String(localized: "Declined")
        case .paid: String(localized: "Paid")
        case .overdue: String(localized: "Overdue")
        }
    }

    var symbol: String {
        switch self {
        case .draft: "pencil.circle"
        case .sent: "paperplane.circle.fill"
        case .accepted: "hand.thumbsup.circle.fill"
        case .declined: "xmark.circle.fill"
        case .paid: "checkmark.circle.fill"
        case .overdue: "exclamationmark.circle.fill"
        }
    }
}

@Model
final class BillingDocument {
    var kindRaw: String = BillingKind.invoice.rawValue
    var number: String = ""
    var clientName: String = ""
    var clientEmail: String = ""
    var clientAddress: String = ""
    var issueDate: Date = Date.now
    var dueDate: Date = Date.now
    var statusRaw: String = BillingStatus.draft.rawValue
    var currency: String = "EUR"
    /// Percent, e.g. 20 for 20% VAT.
    var taxRate: Double = 20
    var notes: String = ""
    @Relationship(deleteRule: .cascade, inverse: \LineItem.document) var lineItems: [LineItem]? = []

    init(kind: BillingKind, number: String, clientName: String, clientEmail: String = "",
         issueDate: Date = .now, dueDate: Date, status: BillingStatus = .draft, taxRate: Double = 20) {
        self.kindRaw = kind.rawValue
        self.number = number
        self.clientName = clientName
        self.clientEmail = clientEmail
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.statusRaw = status.rawValue
        self.taxRate = taxRate
    }

    var kind: BillingKind {
        get { BillingKind(rawValue: kindRaw) ?? .invoice }
        set { kindRaw = newValue.rawValue }
    }

    var status: BillingStatus {
        get { BillingStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var items: [LineItem] { (lineItems ?? []).sorted { $0.order < $1.order } }
    var subtotal: Money { Money(cents: items.reduce(0) { $0 + $1.totalCents }, currency: currency) }
    var tax: Money { Money(cents: Int((Double(subtotal.cents) * taxRate / 100).rounded()), currency: currency) }
    var total: Money { subtotal + tax }

    var isOverdue: Bool { kind == .invoice && status == .sent && dueDate < .now }
}

@Model
final class LineItem {
    var title: String = ""
    var quantity: Double = 1
    var unitPriceCents: Int = 0
    var order: Double = 0
    var document: BillingDocument?

    init(title: String, quantity: Double, unitPriceCents: Int, order: Double = 0) {
        self.title = title
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.order = order
    }

    var totalCents: Int { Int((Double(unitPriceCents) * quantity).rounded()) }
}

enum LedgerKind: String, Codable, CaseIterable, Identifiable {
    case income, expense
    var id: String { rawValue }
    var title: String { self == .income ? String(localized: "Income") : String(localized: "Expense") }
}

/// Accounting ledger entry. Income entries double as paychecks / payouts.
@Model
final class LedgerEntry {
    var date: Date = Date.now
    var amountCents: Int = 0
    var currency: String = "EUR"
    var kindRaw: String = LedgerKind.income.rawValue
    var category: String = ""
    var counterparty: String = ""
    var note: String = ""
    var invoiceNumber: String?

    init(date: Date, amountCents: Int, kind: LedgerKind, category: String, counterparty: String, note: String = "", invoiceNumber: String? = nil) {
        self.date = date
        self.amountCents = amountCents
        self.kindRaw = kind.rawValue
        self.category = category
        self.counterparty = counterparty
        self.note = note
        self.invoiceNumber = invoiceNumber
    }

    var kind: LedgerKind {
        get { LedgerKind(rawValue: kindRaw) ?? .income }
        set { kindRaw = newValue.rawValue }
    }

    var money: Money { Money(cents: amountCents, currency: currency) }
}

@Model
final class PortfolioItem {
    var title: String = ""
    var summary: String = ""
    var disciplineRaw: String = Discipline.design.rawValue
    var link: URL?
    var createdAt: Date = Date.now
    var tags: [String] = []
    /// Large binary data lives outside the SQLite store and syncs as CloudKit assets.
    @Attribute(.externalStorage) var coverImage: Data?
    @Attribute(.externalStorage) var attachment: Data?
    var attachmentName: String?

    init(title: String, summary: String, discipline: Discipline, link: URL? = nil, tags: [String] = [], createdAt: Date = .now) {
        self.title = title
        self.summary = summary
        self.disciplineRaw = discipline.rawValue
        self.link = link
        self.tags = tags
        self.createdAt = createdAt
    }

    var discipline: Discipline { Discipline(rawValue: disciplineRaw) ?? .design }
}

enum BusinessSchema {
    static let models: [any PersistentModel.Type] = [
        Project.self, BoardTask.self, Meeting.self, BillingDocument.self,
        LineItem.self, LedgerEntry.self, PortfolioItem.self,
    ]
}
