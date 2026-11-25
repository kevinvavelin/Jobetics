import Foundation
import SwiftData

/// Builds invoice lines from logged work, travel and rebillable expenses.
nonisolated struct DraftLine: Hashable, Sendable {
    var title: String
    var quantity: Double
    var unitPriceCents: Int
    var totalCents: Int { Int((Double(unitPriceCents) * quantity).rounded()) }
}

enum MissionInvoicing {
    /// Lines for one month of a mission: work, travel fees and rebillable expenses not yet invoiced.
    static func lines(for mission: Mission, month: Date, settings: BusinessSettings, calendar: Calendar = .current) -> [DraftLine] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let monthName = month.formatted(.dateTime.month(.wide).year())
        let logs = (mission.logs ?? []).filter { interval.contains($0.date) && !$0.isLocked }
        var lines: [DraftLine] = []

        switch mission.billingMode {
        case .daily:
            let days = logs.reduce(0) { $0 + $1.days }
            if days > 0 {
                lines.append(DraftLine(title: String(localized: "\(mission.title): \(monthName)"), quantity: days, unitPriceCents: mission.rateCents))
            }
        case .hourly:
            let hours = logs.reduce(0) { $0 + $1.hours }
            if hours > 0 {
                lines.append(DraftLine(title: String(localized: "\(mission.title): \(monthName) (hours)"), quantity: hours, unitPriceCents: mission.rateCents))
            }
        case .fixed:
            lines.append(DraftLine(title: mission.title, quantity: 1, unitPriceCents: mission.rateCents))
        }

        let onSite = logs.filter(\.onSite).reduce(0) { $0 + $1.days }
        let fees = mission.travelFees(onSiteDays: onSite, ratePerKm: settings.mileageRatePerKm)
        if fees.totalCents > 0 {
            switch mission.travelPolicy {
            case .flatPerDay:
                lines.append(DraftLine(title: String(localized: "Travel: on-site days"), quantity: onSite, unitPriceCents: mission.flatTravelPerDayCents))
            case .actualCosts where mission.transport.usesMileageAllowance:
                let rate = Int((settings.mileageRatePerKm * 100).rounded())
                lines.append(DraftLine(title: String(localized: "Mileage: \(onSite.formatted()) round trips × \(Int(fees.roundTripKm)) km"),
                                       quantity: fees.totalKm, unitPriceCents: rate))
            case .actualCosts:
                lines.append(DraftLine(title: String(localized: "Travel tickets: \(onSite.formatted()) round trips"), quantity: onSite,
                                       unitPriceCents: mission.ticketRoundTripCents))
            case .included:
                break
            }
        }

        for expense in (mission.expenses ?? []).filter(\.isPendingRebill).sorted(by: { $0.date < $1.date }) {
            // Rebilled at cost, excluding VAT when the freelancer recovers it.
            let amount = settings.vatExempt ? expense.amountCents : expense.amountCents - expense.vatCents
            lines.append(DraftLine(title: String(localized: "Expense: \(expense.title)"), quantity: 1, unitPriceCents: amount))
        }
        return lines
    }

    /// Creates a draft invoice and marks the work and expenses as billed.
    @discardableResult
    static func createInvoice(for mission: Mission, month: Date, settings: SettingsStore, in context: ModelContext,
                              calendar: Calendar = .current) -> BillingDocument? {
        let draft = lines(for: mission, month: month, settings: settings.settings, calendar: calendar)
        guard !draft.isEmpty, let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
        let client = mission.client
        let terms = client?.paymentTermsDays ?? 30
        let invoice = BillingDocument(kind: .invoice, number: "", clientName: client?.name ?? "", clientEmail: client?.email ?? "",
                                      dueDate: .now.addingTimeInterval(Double(terms) * 86_400),
                                      taxRate: settings.settings.vatExempt ? 0 : settings.settings.defaultVATRate)
        invoice.clientAddress = client?.address ?? ""
        invoice.missionTitle = mission.title
        invoice.notes = [mission.purchaseOrder.isEmpty ? nil : String(localized: "Purchase order \(mission.purchaseOrder)"),
                         String(localized: "Payment by bank transfer within \(terms) days.")]
            .compactMap { $0 }.joined(separator: "\n")
        context.insert(invoice)
        for (index, line) in draft.enumerated() {
            let item = LineItem(title: line.title, quantity: line.quantity, unitPriceCents: line.unitPriceCents, order: Double(index))
            item.document = invoice
            context.insert(item)
        }
        for log in (mission.logs ?? []) where interval.contains(log.date) { log.isLocked = true }
        for expense in (mission.expenses ?? []) where expense.isPendingRebill { expense.rebilledOn = String(localized: "Draft invoice") }
        return invoice
    }
}
