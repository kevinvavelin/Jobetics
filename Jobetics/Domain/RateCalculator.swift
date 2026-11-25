import Foundation

/// Legal status of the freelancer's business. Drives the default social-contribution rate
/// and which thresholds apply. Every rate is editable: the values below are defaults only.
nonisolated enum LegalStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case microBNC, microBIC, eurl, sasu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microBNC: String(localized: "Micro-entrepreneur (BNC)")
        case .microBIC: String(localized: "Micro-entrepreneur (BIC services)")
        case .eurl: String(localized: "EURL")
        case .sasu: String(localized: "SASU")
        }
    }

    /// Default share of revenue to set aside for social contributions (and, for companies,
    /// an approximation of contributions + corporate tax on a salary/dividend mix).
    var defaultContributionRate: Double {
        switch self {
        case .microBNC: 0.261
        case .microBIC: 0.212
        case .eurl: 0.45
        case .sasu: 0.50
        }
    }

    var isMicro: Bool { self == .microBNC || self == .microBIC }
}

/// Inputs of the daily-rate (TJM) calculator.
nonisolated struct RateInputs: Codable, Hashable, Sendable {
    /// What the freelancer wants to keep per year, after contributions (and income tax if `incomeTaxRate` > 0).
    var targetNetCents: Int = 4_800_000
    /// Share of revenue paid as contributions (0.261 = 26.1 %).
    var contributionRate: Double = LegalStatus.microBNC.defaultContributionRate
    /// Optional flat income-tax rate on revenue (e.g. 0.022 for the micro BNC "versement libératoire").
    var incomeTaxRate: Double = 0
    /// Yearly business costs (software, hardware, insurance, coworking…).
    var yearlyCostsCents: Int = 0
    var vacationDays: Int = 25
    var publicHolidays: Int = 11
    /// Admin, prospecting and training days per month that cannot be billed.
    var nonBillableDaysPerMonth: Double = 2
    var hoursPerDay: Double = 7
}

nonisolated struct RateResult: Hashable, Sendable {
    var billableDays: Double
    var grossRevenueCents: Int
    var dailyRateCents: Int
    var hourlyRateCents: Int
    /// What one billed day really leaves in the pocket.
    var netPerDayCents: Int
}

nonisolated enum RateCalculator {
    /// Working days in a year: weekdays only (52 weeks × 5).
    static let workingDaysPerYear = 260.0

    static func billableDays(_ inputs: RateInputs) -> Double {
        let days = workingDaysPerYear - Double(inputs.vacationDays) - Double(inputs.publicHolidays)
            - inputs.nonBillableDaysPerMonth * 12
        return max(days, 0)
    }

    /// Recommended daily rate so that `revenue × (1 − charges) − costs = target net`.
    /// Daily rates are rounded up to the next 5 € (what clients expect to read on a quote).
    static func recommend(_ inputs: RateInputs) -> RateResult {
        let days = billableDays(inputs)
        let keepRatio = max(1 - inputs.contributionRate - inputs.incomeTaxRate, 0.01)
        let gross = (Double(inputs.targetNetCents) + Double(inputs.yearlyCostsCents)) / keepRatio
        guard days > 0 else {
            return RateResult(billableDays: 0, grossRevenueCents: Int(gross.rounded()), dailyRateCents: 0, hourlyRateCents: 0, netPerDayCents: 0)
        }
        let rawDaily = gross / days
        let daily = (rawDaily / 500).rounded(.up) * 500
        let hourly = inputs.hoursPerDay > 0 ? (daily / inputs.hoursPerDay).rounded() : 0
        let netPerDay = daily * keepRatio - Double(inputs.yearlyCostsCents) / days
        return RateResult(billableDays: days, grossRevenueCents: Int(gross.rounded()), dailyRateCents: Int(daily),
                          hourlyRateCents: Int(hourly), netPerDayCents: Int(netPerDay.rounded()))
    }

    /// For a fixed-price mission: what the price really pays per day worked.
    static func effectiveDailyRate(priceCents: Int, daysWorked: Double) -> Int? {
        guard daysWorked > 0 else { return nil }
        return Int((Double(priceCents) / daysWorked).rounded())
    }
}
