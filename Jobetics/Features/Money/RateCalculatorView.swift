import SwiftUI

/// "What should I charge?" From the life you want to the daily rate that pays for it.
struct RateCalculatorView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let result = RateCalculator.recommend(settings.settings.rateInputs)
        Form {
            Section {
                VStack(spacing: 6) {
                    Text(Money(cents: result.dailyRateCents).formatted)
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(value: Double(result.dailyRateCents)))
                        .animation(.snappy, value: result.dailyRateCents)
                    Text("per day, excluding VAT").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        figure(Money(cents: result.hourlyRateCents).formatted, "per hour")
                        figure(result.billableDays.formatted(), "billable days")
                        figure(Money(cents: result.grossRevenueCents).compact, "yearly revenue")
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Net income per year") {
                    TextField("Amount", value: euros(\.targetNetCents), format: .currency(code: "EUR").precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Business costs per year") {
                    TextField("Amount", value: euros(\.yearlyCostsCents), format: .currency(code: "EUR").precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            } header: {
                Text("The life you want")
            } footer: {
                Text("Costs: software, hardware, insurance, coworking, accountant…")
            }

            Section {
                Picker("Status", selection: Binding(get: { settings.settings.status }, set: { status in
                    settings.settings.status = status
                    settings.settings.contributionRate = status.defaultContributionRate
                    settings.settings.rateInputs.contributionRate = status.defaultContributionRate
                })) {
                    ForEach(LegalStatus.allCases) { Text($0.title).tag($0) }
                }
                percentStepper("Contributions", value: $settings.settings.rateInputs.contributionRate, range: 0...0.7)
                percentStepper("Income tax (flat)", value: $settings.settings.rateInputs.incomeTaxRate, range: 0...0.3, step: 0.001)
            } header: {
                Text("Charges")
            } footer: {
                Text("Defaults are estimates. Check current rates on urssaf.fr: they change every year.")
            }

            Section("Time off") {
                Stepper("Vacation: \(settings.settings.rateInputs.vacationDays) days", value: $settings.settings.rateInputs.vacationDays, in: 0...80)
                Stepper("Public holidays: \(settings.settings.rateInputs.publicHolidays) days", value: $settings.settings.rateInputs.publicHolidays, in: 0...15)
                Stepper(value: $settings.settings.rateInputs.nonBillableDaysPerMonth, in: 0...10, step: 0.5) {
                    Text("Admin & prospecting: \(settings.settings.rateInputs.nonBillableDaysPerMonth.formatted()) days a month")
                }
                Stepper(value: $settings.settings.rateInputs.hoursPerDay, in: 4...10, step: 0.5) {
                    Text("Hours per day: \(settings.settings.rateInputs.hoursPerDay.formatted())")
                }
            }

            Section {
                LabeledContent("Each billed day leaves you", value: Money(cents: result.netPerDayCents).formatted)
            } footer: {
                Text("Rest, training and finding clients are part of the job: they're built into this rate.")
            }
        }
        .navigationTitle("Daily rate")
        .onChange(of: settings.settings.rateInputs.contributionRate) { _, rate in settings.settings.contributionRate = rate }
        .onChange(of: settings.settings.rateInputs.incomeTaxRate) { _, rate in settings.settings.incomeTaxRate = rate }
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func percentStepper(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.005) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title, value: value.wrappedValue.formatted(.percent.precision(.fractionLength(1))))
        }
    }

    private func euros(_ keyPath: WritableKeyPath<RateInputs, Int>) -> Binding<Double> {
        Binding(get: { Double(settings.settings.rateInputs[keyPath: keyPath]) / 100 },
                set: { settings.settings.rateInputs[keyPath: keyPath] = Int(($0 * 100).rounded()) })
    }
}
