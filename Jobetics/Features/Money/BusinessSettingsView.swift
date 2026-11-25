import SwiftUI

/// Legal identity, tax profile, vehicle and numbering. Printed on every quote and invoice.
struct BusinessSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                TextField("Legal name", text: $store.settings.legalName).textContentType(.name)
                TextField("Trade name (optional)", text: $store.settings.tradeName).textContentType(.organizationName)
                TextField("Job title", text: $store.settings.jobTitle).textContentType(.jobTitle)
                TextField("Business address", text: $store.settings.address, axis: .vertical).textContentType(.fullStreetAddress)
                TextField("SIRET", text: $store.settings.siret).keyboardType(.numberPad)
                TextField("E-mail", text: $store.settings.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Phone", text: $store.settings.phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                TextField("Website", text: $store.settings.website)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never)
                TextField("IBAN", text: $store.settings.iban).textInputAutocapitalization(.characters).autocorrectionDisabled()
            } header: {
                Text("Identity")
            } footer: {
                Text("Printed on your quotes, invoices and activity reports.")
            }

            Section {
                Picker("Status", selection: $store.settings.status) {
                    ForEach(LegalStatus.allCases) { Text($0.title).tag($0) }
                }
                Stepper(value: $store.settings.contributionRate, in: 0...0.7, step: 0.001) {
                    LabeledContent("Contributions", value: store.settings.contributionRate.formatted(.percent.precision(.fractionLength(1))))
                }
                Toggle("VAT exemption (art. 293 B)", isOn: $store.settings.vatExempt)
                if !store.settings.vatExempt {
                    TextField("VAT number", text: $store.settings.vatNumber).textInputAutocapitalization(.characters)
                    Stepper("Default VAT \(store.settings.defaultVATRate.formatted())%", value: $store.settings.defaultVATRate, in: 0...30, step: 0.5)
                }
                Stepper(value: $store.settings.latePaymentRate, in: 0...0.3, step: 0.0005) {
                    LabeledContent("Late payment rate", value: store.settings.latePaymentRate.formatted(.percent.precision(.fractionLength(2))))
                }
            } header: {
                Text("Taxes")
            } footer: {
                Text("Contribution rates and thresholds change every year. Check urssaf.fr and impots.gouv.fr, or ask your accountant.")
            }

            Section("Thresholds") {
                Stepper("Year \(store.settings.thresholds.year.formatted(.number.grouping(.never)))", value: $store.settings.thresholds.year, in: 2024...2035)
                amountField("Micro-entreprise ceiling", \.thresholds.microCeilingCents)
                amountField("VAT exemption threshold", \.thresholds.vatFranchiseCents)
            }

            Section {
                TextField("Home address", text: $store.settings.homeAddress, axis: .vertical).textContentType(.fullStreetAddress)
                Stepper("Vehicle: \(store.settings.vehicleHorsepower == 7 ? "7+" : "\(store.settings.vehicleHorsepower)") CV",
                        value: $store.settings.vehicleHorsepower, in: 3...7)
                Toggle("Electric vehicle (+20 %)", isOn: $store.settings.vehicleIsElectric)
                Stepper(value: $store.settings.expectedYearlyKm, in: 0...40_000, step: 500) {
                    LabeledContent("Business km per year", value: store.settings.expectedYearlyKm.formatted())
                }
                LabeledContent("Mileage rate", value: store.settings.mileageRatePerKm.formatted(.currency(code: "EUR").precision(.fractionLength(3))) + "/km")
            } header: {
                Text("Travel")
            } footer: {
                Text("Your commute starts from your home address. The mileage rate follows the official French scale (barème kilométrique 2025).")
            }

            Section {
                TextField("Invoice prefix", text: $store.settings.numbering.invoicePrefix).textInputAutocapitalization(.characters)
                TextField("Quote prefix", text: $store.settings.numbering.quotePrefix).textInputAutocapitalization(.characters)
                LabeledContent("Next invoice", value: store.peekNumber(for: .invoice))
                LabeledContent("Next quote", value: store.peekNumber(for: .quote))
            } header: {
                Text("Numbering")
            } footer: {
                Text("Invoice numbers are sequential with no gaps and restart every year, as required by law. Drafts get a number only when issued.")
            }

            Section {
                Stepper("Weekly hours limit: \(store.settings.weeklyHoursCap.formatted())", value: $store.settings.weeklyHoursCap, in: 20...70, step: 1)
                Stepper("Warn \(store.settings.endOfMissionWarningDays) days before a mission ends",
                        value: $store.settings.endOfMissionWarningDays, in: 7...90, step: 7)
            } header: {
                Text("Wellbeing")
            } footer: {
                Text("Jobetics gently tells you when you work too much, and early enough when a long mission ends.")
            }
        }
        .navigationTitle("Business settings")
    }

    private func amountField(_ title: LocalizedStringKey, _ keyPath: WritableKeyPath<BusinessSettings, Int>) -> some View {
        LabeledContent(title) {
            TextField("Amount", value: Binding(get: { Double(store.settings[keyPath: keyPath]) / 100 },
                                               set: { store.settings[keyPath: keyPath] = Int(($0 * 100).rounded()) }),
                      format: .currency(code: "EUR").precision(.fractionLength(0)))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
        }
    }
}
