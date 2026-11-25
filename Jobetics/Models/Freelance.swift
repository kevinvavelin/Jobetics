import Foundation
import SwiftData

// Freelance ERP data: clients, missions, time, expenses, workspaces and journal.
// Same CloudKit rules as Business.swift: defaults everywhere, optional relationships, no unique constraints.

// MARK: - Client

@Model
final class Client {
    var name: String = ""
    var contactName: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var siret: String = ""
    var vatNumber: String = ""
    /// Payment terms in days (30 = 30 days net).
    var paymentTermsDays: Int = 30
    /// `CNContact.identifier` when the client was picked from Contacts.
    var contactIdentifier: String?
    var notes: String = ""
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Mission.client) var missions: [Mission]? = []

    init(name: String, contactName: String = "", email: String = "", phone: String = "", address: String = "",
         siret: String = "", paymentTermsDays: Int = 30) {
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.address = address
        self.siret = siret
        self.paymentTermsDays = paymentTermsDays
    }
}

// MARK: - Mission

nonisolated enum MissionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case lead, negotiating, quoted, active, paused, done, lost
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lead: String(localized: "Lead")
        case .negotiating: String(localized: "In talks")
        case .quoted: String(localized: "Quote sent")
        case .active: String(localized: "Active")
        case .paused: String(localized: "Paused")
        case .done: String(localized: "Completed")
        case .lost: String(localized: "Lost")
        }
    }

    var symbol: String {
        switch self {
        case .lead: "sparkle.magnifyingglass"
        case .negotiating: "bubble.left.and.bubble.right"
        case .quoted: "doc.text"
        case .active: "bolt.fill"
        case .paused: "pause.circle"
        case .done: "checkmark.seal.fill"
        case .lost: "xmark.circle"
        }
    }

    var isPipeline: Bool { self == .lead || self == .negotiating || self == .quoted }
}

nonisolated enum BillingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily, hourly, fixed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: String(localized: "Daily rate")
        case .hourly: String(localized: "Hourly")
        case .fixed: String(localized: "Fixed price")
        }
    }

    var unit: String {
        switch self {
        case .daily: String(localized: "day")
        case .hourly: String(localized: "hour")
        case .fixed: String(localized: "project")
        }
    }
}

nonisolated enum WorkLocation: String, Codable, CaseIterable, Identifiable, Sendable {
    case remote, onSite, hybrid
    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote: String(localized: "Remote")
        case .onSite: String(localized: "On site")
        case .hybrid: String(localized: "Hybrid")
        }
    }

    var symbol: String {
        switch self {
        case .remote: "house.fill"
        case .onSite: "building.2.fill"
        case .hybrid: "arrow.triangle.swap"
        }
    }
}

@Model
final class Mission {
    var title: String = ""
    var summary: String = ""
    var statusRaw: String = MissionStatus.active.rawValue
    var billingModeRaw: String = BillingMode.daily.rawValue
    /// Daily rate, hourly rate or total price depending on `billingMode`. Excluding VAT.
    var rateCents: Int = 0
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    /// Days planned (fixed price) or budgeted (daily rate).
    var estimatedDays: Double = 0
    var colorName: String = "blue"
    var symbol: String = "briefcase.fill"

    // Where the work happens
    var locationRaw: String = WorkLocation.remote.rawValue
    var siteAddress: String = ""
    var siteLatitude: Double?
    var siteLongitude: Double?
    /// Planned on-site days per week for hybrid missions.
    var onSiteDaysPerWeek: Int = 0

    // Travel
    var transportRaw: String = TransportMode.car.rawValue
    var travelPolicyRaw: String = TravelPolicy.included.rawValue
    var oneWayKm: Double = 0
    var commuteMinutes: Double = 0
    var flatTravelPerDayCents: Int = 0
    var ticketRoundTripCents: Int = 0

    /// Where the lead was found (Malt, LinkedIn, referral…), and its URL.
    var source: String = ""
    var sourceURL: URL?
    var purchaseOrder: String = ""
    var createdAt: Date = Date.now

    var client: Client?
    @Relationship(deleteRule: .cascade, inverse: \WorkLog.mission) var logs: [WorkLog]? = []
    @Relationship(deleteRule: .nullify, inverse: \Expense.mission) var expenses: [Expense]? = []
    @Relationship(deleteRule: .nullify, inverse: \ActivityReportRecord.mission) var reports: [ActivityReportRecord]? = []

    init(title: String, client: Client? = nil, status: MissionStatus = .active, billingMode: BillingMode = .daily,
         rateCents: Int, startDate: Date, endDate: Date, location: WorkLocation = .remote) {
        self.title = title
        self.client = client
        self.statusRaw = status.rawValue
        self.billingModeRaw = billingMode.rawValue
        self.rateCents = rateCents
        self.startDate = startDate
        self.endDate = endDate
        self.locationRaw = location.rawValue
    }

    var status: MissionStatus {
        get { MissionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var billingMode: BillingMode {
        get { BillingMode(rawValue: billingModeRaw) ?? .daily }
        set { billingModeRaw = newValue.rawValue }
    }
    var location: WorkLocation {
        get { WorkLocation(rawValue: locationRaw) ?? .remote }
        set { locationRaw = newValue.rawValue }
    }
    var transport: TransportMode {
        get { TransportMode(rawValue: transportRaw) ?? .car }
        set { transportRaw = newValue.rawValue }
    }
    var travelPolicy: TravelPolicy {
        get { TravelPolicy(rawValue: travelPolicyRaw) ?? .included }
        set { travelPolicyRaw = newValue.rawValue }
    }

    var rate: Money { Money(cents: rateCents) }
    var clientName: String { client?.name ?? "" }
    var sortedLogs: [WorkLog] { (logs ?? []).sorted { $0.date > $1.date } }

    /// Long missions (3 months and more) are the backbone of the year; short ones fill gaps.
    var isLong: Bool { endDate.timeIntervalSince(startDate) >= 86_400 * 90 }
    var needsTravel: Bool { location != .remote }

    var daysLogged: Double { (logs ?? []).reduce(0) { $0 + $1.days } }
    var hoursLogged: Double { (logs ?? []).reduce(0) { $0 + $1.hours } }
    var onSiteDaysLogged: Double { (logs ?? []).filter(\.onSite).reduce(0) { $0 + $1.days } }

    /// Revenue earned by the work logged so far.
    var earnedCents: Int {
        switch billingMode {
        case .daily: Int((daysLogged * Double(rateCents)).rounded())
        case .hourly: Int((hoursLogged * Double(rateCents)).rounded())
        case .fixed: estimatedDays > 0 ? min(rateCents, Int(Double(rateCents) * daysLogged / estimatedDays)) : 0
        }
    }

    /// What one day of work actually pays.
    var effectiveDailyRateCents: Int? {
        switch billingMode {
        case .daily: rateCents
        case .hourly: Int((Double(rateCents) * 7).rounded())
        case .fixed: RateCalculator.effectiveDailyRate(priceCents: rateCents, daysWorked: daysLogged > 0 ? daysLogged : estimatedDays)
        }
    }

    var daysRemaining: Int { max(0, Calendar.current.dateComponents([.day], from: .now, to: endDate).day ?? 0) }

    func travelFees(onSiteDays: Double, ratePerKm: Double) -> TravelFees {
        TravelFees(onSiteDays: onSiteDays, oneWayKm: oneWayKm, mode: transport, policy: travelPolicy,
                   flatPerDayCents: flatTravelPerDayCents, ticketRoundTripCents: ticketRoundTripCents, ratePerKm: ratePerKm)
    }

    func activityReport(for month: Date, calendar: Calendar = .current) -> ActivityReport? {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
        return ActivityReport(month: interval, entries: (logs ?? []).map { ActivityDay(date: $0.date, days: $0.days, onSite: $0.onSite) })
    }
}

// MARK: - Time

@Model
final class WorkLog {
    var date: Date = Date.now
    /// 1 = full day, 0.5 = half day. Used by daily-rate and fixed-price missions.
    var days: Double = 0
    /// Used by hourly missions (and as information for others).
    var hours: Double = 0
    var onSite: Bool = false
    var note: String = ""
    /// Set once the day is part of a signed activity report or an invoice: it can't change anymore.
    var isLocked: Bool = false
    var workspaceName: String = ""
    var mission: Mission?

    init(date: Date, days: Double, hours: Double = 0, onSite: Bool = false, note: String = "") {
        self.date = date
        self.days = days
        self.hours = hours > 0 ? hours : days * 7
        self.onSite = onSite
        self.note = note
    }
}

/// A monthly activity report (CRA) once generated: signature and lock state.
@Model
final class ActivityReportRecord {
    var month: Date = Date.now
    var totalDays: Double = 0
    var onSiteDays: Double = 0
    var signedAt: Date?
    var signerName: String = ""
    @Attribute(.externalStorage) var signature: Data?
    var invoiceNumber: String?
    var mission: Mission?

    init(month: Date, totalDays: Double, onSiteDays: Double) {
        self.month = month
        self.totalDays = totalDays
        self.onSiteDays = onSiteDays
    }

    var isSigned: Bool { signedAt != nil }
}

// MARK: - Expenses

nonisolated enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case transport, mileage, meals, lodging, coworking, software, equipment, training, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .transport: String(localized: "Transport")
        case .mileage: String(localized: "Mileage")
        case .meals: String(localized: "Meals")
        case .lodging: String(localized: "Lodging")
        case .coworking: String(localized: "Coworking")
        case .software: String(localized: "Software")
        case .equipment: String(localized: "Equipment")
        case .training: String(localized: "Training")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .transport: "tram.fill"
        case .mileage: "car.fill"
        case .meals: "fork.knife"
        case .lodging: "bed.double.fill"
        case .coworking: "person.3.fill"
        case .software: "app.badge.fill"
        case .equipment: "laptopcomputer"
        case .training: "graduationcap.fill"
        case .other: "tag.fill"
        }
    }
}

@Model
final class Expense {
    var date: Date = Date.now
    var title: String = ""
    var amountCents: Int = 0
    var vatCents: Int = 0
    var categoryRaw: String = ExpenseCategory.other.rawValue
    /// Can be passed on to the client.
    var isRebillable: Bool = false
    /// Number of the invoice it was rebilled on.
    var rebilledOn: String?
    var km: Double = 0
    @Attribute(.externalStorage) var receipt: Data?
    var mission: Mission?

    init(date: Date, title: String, amountCents: Int, category: ExpenseCategory, isRebillable: Bool = false, vatCents: Int = 0) {
        self.date = date
        self.title = title
        self.amountCents = amountCents
        self.categoryRaw = category.rawValue
        self.isRebillable = isRebillable
        self.vatCents = vatCents
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var money: Money { Money(cents: amountCents) }
    var isPendingRebill: Bool { isRebillable && rebilledOn == nil }
}

// MARK: - Workspaces

nonisolated enum WorkspaceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, coworking, clientSite, travel, cafe
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home office")
        case .coworking: String(localized: "Coworking")
        case .clientSite: String(localized: "Client site")
        case .travel: String(localized: "On the move")
        case .cafe: String(localized: "Café")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .coworking: "person.3.fill"
        case .clientSite: "building.2.fill"
        case .travel: "train.side.front.car"
        case .cafe: "cup.and.saucer.fill"
        }
    }
}

/// A place where the freelancer works. Checking in logs the day there and adds its daily cost.
@Model
final class Workspace {
    var name: String = ""
    var kindRaw: String = WorkspaceKind.home.rawValue
    var address: String = ""
    var dayCostCents: Int = 0
    var lastCheckIn: Date?
    var isDefault: Bool = false

    init(name: String, kind: WorkspaceKind, address: String = "", dayCostCents: Int = 0, isDefault: Bool = false) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.address = address
        self.dayCostCents = dayCostCents
        self.isDefault = isDefault
    }

    var kind: WorkspaceKind {
        get { WorkspaceKind(rawValue: kindRaw) ?? .home }
        set { kindRaw = newValue.rawValue }
    }

    var isCheckedInToday: Bool { lastCheckIn.map { Calendar.current.isDateInToday($0) } ?? false }
}

// MARK: - Journal

@Model
final class JournalEntry {
    var date: Date = Date.now
    var text: String = ""
    /// 1…5
    var energy: Int = 3
    /// What made today's work meaningful.
    var impact: String = ""
    var missionTitle: String = ""
    var sharedOnLinkedIn: Bool = false

    init(date: Date = .now, text: String, energy: Int = 3, impact: String = "") {
        self.date = date
        self.text = text
        self.energy = energy
        self.impact = impact
    }
}
