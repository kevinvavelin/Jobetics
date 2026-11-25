import Foundation
import Observation

/// The freelancer's business identity and preferences. Small, so it's stored as JSON in
/// UserDefaults and mirrored to iCloud key-value storage to follow the user across devices.
nonisolated struct BusinessSettings: Codable, Hashable, Sendable {
    // Identity printed on quotes and invoices
    var legalName = ""
    var tradeName = ""
    var address = ""
    var siret = ""
    var vatNumber = ""
    var iban = ""
    var email = ""
    var phone = ""
    var website = ""
    var jobTitle = ""

    // Tax profile
    var status: LegalStatus = .microBNC
    var contributionRate = LegalStatus.microBNC.defaultContributionRate
    var incomeTaxRate = 0.0
    /// VAT-exempt micro-entrepreneurs print "TVA non applicable, art. 293 B du CGI".
    var vatExempt = true
    var defaultVATRate = 20.0
    /// Yearly late-payment rate printed on invoices (legal minimum: 3 × the legal interest rate).
    var latePaymentRate = 0.1215
    var thresholds = Thresholds()

    // Rates
    var rateInputs = RateInputs()

    // Travel
    var homeAddress = ""
    var vehicleHorsepower = 5
    var vehicleIsElectric = false
    /// Expected yearly business km, to pick the right mileage bracket.
    var expectedYearlyKm = 8_000.0

    // Wellbeing
    var weeklyHoursCap = 45.0
    var endOfMissionWarningDays = 42

    var numbering = DocumentNumbering()

    var displayName: String { tradeName.isEmpty ? legalName : tradeName }

    var mileageRatePerKm: Double {
        MileageScales.scale(forHorsepower: vehicleHorsepower)
            .ratePerKm(expectedYearlyKm: expectedYearlyKm, electric: vehicleIsElectric)
    }

    /// Mentions required on French invoices.
    var legalMentions: [String] {
        var lines: [String] = []
        if !siret.isEmpty { lines.append("SIRET \(siret)") }
        if vatExempt {
            lines.append("TVA non applicable, art. 293 B du CGI")
        } else if !vatNumber.isEmpty {
            lines.append("TVA intracommunautaire \(vatNumber)")
        }
        let rate = (latePaymentRate * 100).formatted(.number.precision(.fractionLength(0...2)))
        lines.append(String(localized: "Late payment penalties: \(rate)% per year. Fixed recovery indemnity: €40 (art. L441-10 Code de commerce). No discount for early payment."))
        if !iban.isEmpty { lines.append("IBAN \(iban)") }
        return lines
    }

    var isComplete: Bool { !legalName.isEmpty && !siret.isEmpty && !address.isEmpty }
}

@Observable
final class SettingsStore {
    private static let key = "business.settings.v1"
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?

    var settings: BusinessSettings {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard, syncsWithICloud: Bool = true) {
        self.defaults = defaults
        self.cloud = syncsWithICloud ? NSUbiquitousKeyValueStore.default : nil
        let data = cloud?.data(forKey: Self.key) ?? defaults.data(forKey: Self.key)
        settings = data.flatMap { try? JSONDecoder().decode(BusinessSettings.self, from: $0) } ?? BusinessSettings()
        if let cloud {
            NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                   object: cloud, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadFromCloud() }
            }
            cloud.synchronize()
        }
    }

    private func reloadFromCloud() {
        guard let data = cloud?.data(forKey: Self.key),
              let remote = try? JSONDecoder().decode(BusinessSettings.self, from: data), remote != settings else { return }
        settings = remote
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
        cloud?.set(data, forKey: Self.key)
    }

    /// Reserves the next legal number for a document kind.
    func nextNumber(for kind: BillingKind, date: Date = .now) -> String {
        let year = Calendar.current.component(.year, from: date)
        return settings.numbering.next(prefix: prefix(for: kind), year: year)
    }

    func peekNumber(for kind: BillingKind, date: Date = .now) -> String {
        settings.numbering.peek(prefix: prefix(for: kind), year: Calendar.current.component(.year, from: date))
    }

    func prefix(for kind: BillingKind) -> String {
        switch kind {
        case .invoice: settings.numbering.invoicePrefix
        case .quote: settings.numbering.quotePrefix
        case .creditNote: settings.numbering.creditNotePrefix
        }
    }
}
