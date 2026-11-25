import Foundation

/// How the freelancer travels to a client site.
nonisolated enum TransportMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case car, transit, train, bike, walk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: String(localized: "Car")
        case .transit: String(localized: "Public transport")
        case .train: String(localized: "Train")
        case .bike: String(localized: "Bike")
        case .walk: String(localized: "Walk")
        }
    }

    var symbol: String {
        switch self {
        case .car: "car.fill"
        case .transit: "tram.fill"
        case .train: "train.side.front.car"
        case .bike: "bicycle"
        case .walk: "figure.walk"
        }
    }

    /// Only a personal vehicle gives right to the mileage allowance.
    var usesMileageAllowance: Bool { self == .car }
}

/// One bracket of the French "barème kilométrique": allowance = km × rate + fixed.
nonisolated struct MileageBracket: Codable, Hashable, Sendable {
    /// Upper bound of yearly km for this bracket (nil = no limit).
    var upToKm: Double?
    var ratePerKm: Double
    var fixedEuros: Double
}

/// Official scale for one fiscal horsepower class. Published yearly by the tax office:
/// stored as data (and editable in Settings) rather than hard-coded logic.
nonisolated struct MileageScale: Codable, Hashable, Sendable {
    var year: Int
    /// Fiscal horsepower (CV). 7 means "7 CV and more".
    var horsepower: Int
    var brackets: [MileageBracket]
    /// Electric vehicles get +20 %.
    var electricBonus: Double = 0.20

    /// Yearly allowance for `km` driven for business in the year.
    func yearlyAllowance(km: Double, electric: Bool = false) -> Double {
        guard km > 0, let bracket = brackets.first(where: { $0.upToKm.map { km <= $0 } ?? true }) else { return 0 }
        let base = km * bracket.ratePerKm + bracket.fixedEuros
        return (base * (electric ? 1 + electricBonus : 1) * 100).rounded() / 100
    }

    /// Rate per km for rebilling a trip to a client, using the bracket matching the
    /// expected yearly business mileage.
    func ratePerKm(expectedYearlyKm: Double, electric: Bool = false) -> Double {
        guard expectedYearlyKm > 0 else { return (brackets.first?.ratePerKm ?? 0) * (electric ? 1 + electricBonus : 1) }
        return yearlyAllowance(km: expectedYearlyKm, electric: electric) / expectedYearlyKm
    }
}

nonisolated enum MileageScales {
    /// Barème kilométrique applicable to 2025 trips (unchanged from 2024). Verify on impots.gouv.fr each year.
    static let france2025: [MileageScale] = [
        scale(3, (0.529, 0), (0.316, 1065), (0.370, 0)),
        scale(4, (0.606, 0), (0.340, 1330), (0.407, 0)),
        scale(5, (0.636, 0), (0.357, 1395), (0.427, 0)),
        scale(6, (0.665, 0), (0.374, 1457), (0.447, 0)),
        scale(7, (0.697, 0), (0.394, 1515), (0.470, 0)),
    ]

    static func scale(forHorsepower cv: Int) -> MileageScale {
        let clamped = min(max(cv, 3), 7)
        return france2025.first { $0.horsepower == clamped } ?? france2025[2]
    }

    private static func scale(_ cv: Int, _ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> MileageScale {
        MileageScale(year: 2025, horsepower: cv, brackets: [
            MileageBracket(upToKm: 5_000, ratePerKm: a.0, fixedEuros: a.1),
            MileageBracket(upToKm: 20_000, ratePerKm: b.0, fixedEuros: b.1),
            MileageBracket(upToKm: nil, ratePerKm: c.0, fixedEuros: c.1),
        ])
    }
}

/// How travel costs of an on-site mission are passed on to the client.
nonisolated enum TravelPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Travel is included in the daily rate: nothing is added to the invoice.
    case included
    /// A fixed amount per on-site day.
    case flatPerDay
    /// Round-trip km × the mileage rate (car) or the actual ticket price (other modes).
    case actualCosts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .included: String(localized: "Included in rate")
        case .flatPerDay: String(localized: "Flat fee per on-site day")
        case .actualCosts: String(localized: "Actual costs (mileage or tickets)")
        }
    }
}

/// Travel fees for a set of on-site days. Pure function, used by invoices and the mission screen.
nonisolated struct TravelFees: Hashable, Sendable {
    var onSiteDays: Double
    var oneWayKm: Double
    var mode: TransportMode
    var policy: TravelPolicy
    var flatPerDayCents: Int = 0
    /// Round-trip ticket price for non-car modes.
    var ticketRoundTripCents: Int = 0
    var ratePerKm: Double = 0

    var roundTripKm: Double { oneWayKm * 2 }
    var totalKm: Double { roundTripKm * onSiteDays }

    var totalCents: Int {
        guard onSiteDays > 0 else { return 0 }
        switch policy {
        case .included: return 0
        case .flatPerDay: return Int((Double(flatPerDayCents) * onSiteDays).rounded())
        case .actualCosts:
            if mode.usesMileageAllowance { return Int((totalKm * ratePerKm * 100).rounded()) }
            return Int((Double(ticketRoundTripCents) * onSiteDays).rounded())
        }
    }
}
