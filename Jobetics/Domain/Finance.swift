import Foundation

// MARK: - Invoice numbering

/// Gapless, chronological numbering required by French law: `FAC-2026-0042`.
/// The counter restarts every year. Numbers are never reused, even if a draft is abandoned.
nonisolated struct DocumentNumbering: Codable, Hashable, Sendable {
    var invoicePrefix = "FAC"
    var quotePrefix = "DEV"
    var creditNotePrefix = "AV"
    var digits = 4
    /// Last number issued per "prefix-year" key, e.g. ["FAC-2026": 41].
    var counters: [String: Int] = [:]

    func key(prefix: String, year: Int) -> String { "\(prefix)-\(year)" }

    func peek(prefix: String, year: Int) -> String {
        format(prefix: prefix, year: year, number: (counters[key(prefix: prefix, year: year)] ?? 0) + 1)
    }

    /// Reserves and returns the next number.
    mutating func next(prefix: String, year: Int) -> String {
        let k = key(prefix: prefix, year: year)
        let n = (counters[k] ?? 0) + 1
        counters[k] = n
        return format(prefix: prefix, year: year, number: n)
    }

    /// Makes sure the counter is past numbers already used (e.g. imported or demo documents).
    mutating func register(existing number: String) {
        let parts = number.split(separator: "-")
        guard parts.count >= 3, let year = Int(parts[parts.count - 2]), let n = Int(parts[parts.count - 1]) else { return }
        let prefix = parts.dropLast(2).joined(separator: "-")
        let k = key(prefix: prefix, year: year)
        counters[k] = max(counters[k] ?? 0, n)
    }

    func format(prefix: String, year: Int, number: Int) -> String {
        "\(prefix)-\(year)-\(String(number).leftPadded(to: digits))"
    }
}

private extension String {
    nonisolated func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}

// MARK: - Taxes & thresholds

/// Yearly thresholds. Values change with finance laws, so they're data the user can edit.
nonisolated struct Thresholds: Codable, Hashable, Sendable {
    var year = 2026
    /// Micro-entreprise revenue ceiling for services (BNC / BIC services).
    var microCeilingCents = 7_770_000
    /// VAT exemption ("franchise en base") threshold for services.
    var vatFranchiseCents = 3_750_000
    /// Above this, VAT is due from the first day of overshoot.
    var vatFranchiseHardCents = 4_125_000
}

nonisolated enum ThresholdLevel: Int, Comparable, Sendable {
    case ok, approaching, critical, exceeded
    static func < (a: ThresholdLevel, b: ThresholdLevel) -> Bool { a.rawValue < b.rawValue }

    static func level(revenue: Int, limit: Int) -> ThresholdLevel {
        guard limit > 0 else { return .ok }
        let ratio = Double(revenue) / Double(limit)
        switch ratio {
        case ..<0.8: return .ok
        case ..<0.95: return .approaching
        case ..<1: return .critical
        default: return .exceeded
        }
    }
}

nonisolated enum TaxMath {
    /// Amount to put aside when a payment is received.
    static func setAside(paymentCents: Int, contributionRate: Double, incomeTaxRate: Double = 0) -> Int {
        Int((Double(paymentCents) * (contributionRate + incomeTaxRate)).rounded())
    }

    /// French late-payment penalties: rate × amount × days late / 365, plus the 40 € recovery indemnity.
    static func latePenalty(amountCents: Int, daysLate: Int, yearlyRate: Double, indemnityCents: Int = 4_000) -> Int {
        guard daysLate > 0 else { return 0 }
        let interest = Double(amountCents) * yearlyRate * Double(daysLate) / 365
        return Int(interest.rounded()) + indemnityCents
    }
}

// MARK: - Activity report (CRA)

/// One day in a monthly activity report.
nonisolated struct ActivityDay: Hashable, Sendable {
    var date: Date
    var days: Double
    var onSite: Bool
}

/// Monthly activity report ("compte rendu d'activité") for a daily-rate mission.
nonisolated struct ActivityReport: Hashable, Sendable {
    var month: DateInterval
    var entries: [ActivityDay]

    var totalDays: Double { entries.reduce(0) { $0 + $1.days } }
    var onSiteDays: Double { entries.filter(\.onSite).reduce(0) { $0 + $1.days } }
    var remoteDays: Double { totalDays - onSiteDays }

    init(month: DateInterval, entries: [ActivityDay]) {
        self.month = month
        self.entries = entries.filter { month.contains($0.date) && $0.days > 0 }.sorted { $0.date < $1.date }
    }
}

// MARK: - Cash-flow forecast

nonisolated struct CashFlowPoint: Hashable, Sendable, Identifiable {
    var month: Date
    var incomingCents: Int
    var outgoingCents: Int
    var balanceCents: Int
    var id: Date { month }
}

nonisolated enum CashFlow {
    /// Projects the balance month by month.
    /// - Parameters:
    ///   - start: current cash.
    ///   - expected: dated incoming payments (unpaid invoices by due date, missions by month).
    ///   - monthlyCosts: recurring costs including the tax set-aside.
    static func forecast(start: Int, from: Date, months: Int, expected: [(Date, Int)], monthlyCosts: Int,
                         calendar: Calendar = .current) -> [CashFlowPoint] {
        guard let first = calendar.dateInterval(of: .month, for: from)?.start else { return [] }
        var balance = start
        return (0..<months).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: first),
                  let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
            let incoming = expected.filter { interval.contains($0.0) || (offset == 0 && $0.0 < interval.start) }
                .reduce(0) { $0 + $1.1 }
            balance += incoming - monthlyCosts
            return CashFlowPoint(month: month, incomingCents: incoming, outgoingCents: monthlyCosts, balanceCents: balance)
        }
    }
}
