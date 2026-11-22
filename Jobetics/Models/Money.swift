import Foundation

/// Money stored in minor units (cents) to avoid floating-point rounding in invoices.
nonisolated struct Money: Codable, Hashable, Sendable, Comparable {
    var cents: Int
    var currency: String

    init(cents: Int, currency: String = "EUR") {
        self.cents = cents
        self.currency = currency
    }

    init(_ amount: Double, currency: String = "EUR") {
        self.init(cents: Int((amount * 100).rounded()), currency: currency)
    }

    var amount: Double { Double(cents) / 100 }
    var isPositive: Bool { cents > 0 }

    var formatted: String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(cents % 100 == 0 ? 0 : 2)))
    }

    var compact: String {
        amount.formatted(.currency(code: currency).notation(.compactName).precision(.significantDigits(1...3)))
    }

    static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }
    static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents, currency: lhs.currency) }
    static let zero = Money(cents: 0)
}
