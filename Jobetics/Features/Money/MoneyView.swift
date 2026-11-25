import Charts
import SwiftData
import SwiftUI

/// Everything about money in one calm place: what to set aside, thresholds, cash flow and documents.
struct MoneyView: View {
    var embedded = false

    var body: some View {
        if embedded { MoneyContent() } else { NavigationStack { MoneyContent() } }
    }
}

struct MoneyContent: View {
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query(filter: #Predicate<BillingDocument> { $0.kindRaw == "invoice" }) private var invoices: [BillingDocument]
    @Query(filter: #Predicate<Mission> { $0.statusRaw == "active" }) private var activeMissions: [Mission]
    @Query private var expenses: [Expense]

    private var yearStart: Date { Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now }
    private var revenueThisYear: Int { ledger.filter { $0.kind == .income && $0.date >= yearStart }.reduce(0) { $0 + $1.amountCents } }
    private var unpaid: [BillingDocument] { invoices.filter { ($0.status == .sent || $0.status == .overdue) && !$0.isCancelled } }

    var body: some View {
        List {
            Section { setAsideCard.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }

            Section {
                ThresholdRow(title: "Micro-entreprise ceiling", revenue: revenueThisYear, limit: settings.settings.thresholds.microCeilingCents)
                if settings.settings.vatExempt {
                    ThresholdRow(title: "VAT exemption threshold", revenue: revenueThisYear, limit: settings.settings.thresholds.vatFranchiseCents)
                }
            } header: {
                Text("Thresholds \(settings.settings.thresholds.year.formatted(.number.grouping(.never)))")
            } footer: {
                Text("Revenue received this year. You'll be alerted at 80 % and 95 %. Thresholds are editable in Business settings.")
            }

            Section("Cash flow, next 6 months") { cashFlowChart }

            if !unpaid.isEmpty {
                Section("Awaiting payment") {
                    ForEach(unpaid.sorted { $0.dueDate < $1.dueDate }.prefix(4)) { doc in
                        NavigationLink { BillingDetailView(document: doc) } label: { BillingRow(document: doc) }
                    }
                }
            }

            Section("Documents") {
                link("Invoices", "doc.text.fill", detail: unpaid.isEmpty ? nil : String(localized: "\(unpaid.count) awaiting")) { BillingListView(kind: .invoice) }
                link("Quotes", "doc.text.magnifyingglass") { BillingListView(kind: .quote) }
                link("Expenses", "creditcard.fill", detail: pendingRebillText) { ExpensesView() }
                link("Clients", "person.2.fill") { ClientsView() }
            }

            Section("Insights") {
                link("Daily rate calculator", "function", detail: Money(cents: RateCalculator.recommend(settings.settings.rateInputs).dailyRateCents).formatted) { RateCalculatorView() }
                link("Accounting", "chart.bar.xaxis") { AccountingView() }
                link("Payouts", "banknote.fill") { PayoutsView() }
            }

            Section {
                link("Business settings", "building.columns.fill", detail: settings.settings.isComplete ? nil : String(localized: "Incomplete")) { BusinessSettingsView() }
            } footer: {
                if !settings.settings.isComplete {
                    Text("Add your legal name, SIRET and address: they're required on your invoices.")
                }
            }
        }
        .navigationTitle("Money")
    }

    private var pendingRebillText: String? {
        let pending = expenses.filter(\.isPendingRebill).count
        return pending > 0 ? String(localized: "\(pending) to rebill") : nil
    }

    private func link<Destination: View>(_ title: LocalizedStringKey, _ symbol: String, detail: String? = nil,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            LabeledContent {
                if let detail { Text(detail) }
            } label: {
                Label(title, systemImage: symbol)
            }
        }
    }

    // MARK: Set aside

    private var setAsideCard: some View {
        let s = settings.settings
        let quarter = Calendar.current.dateInterval(of: .quarter, for: .now) ?? DateInterval(start: .now, duration: 0)
        let receivedThisQuarter = ledger.filter { $0.kind == .income && quarter.contains($0.date) }.reduce(0) { $0 + $1.amountCents }
        let toSetAside = TaxMath.setAside(paymentCents: receivedThisQuarter, contributionRate: s.contributionRate, incomeTaxRate: s.incomeTaxRate)
        return VStack(alignment: .leading, spacing: 12) {
            Label("To set aside this quarter", systemImage: "building.columns")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Money(cents: toSetAside).formatted)
                .font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                .contentTransition(.numericText())
            Text("\((s.contributionRate + s.incomeTaxRate).formatted(.percent.precision(.fractionLength(1)))) of \(Money(cents: receivedThisQuarter).formatted) received since \(quarter.start.formatted(.dateTime.day().month(.wide))).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Money(cents: revenueThisYear).formatted).font(.headline.monospacedDigit())
                    Text("Received this year").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money(cents: revenueThisYear - TaxMath.setAside(paymentCents: revenueThisYear, contributionRate: s.contributionRate, incomeTaxRate: s.incomeTaxRate)).formatted)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Brand.positive)
                    Text("Yours to keep").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Cash flow

    private var forecast: [CashFlowPoint] {
        let s = settings.settings
        let cash = ledger.reduce(0) { $0 + ($1.kind == .income ? $1.amountCents : -$1.amountCents) }
        var expected: [(Date, Int)] = unpaid.map { ($0.dueDate, $0.total.cents) }
        let cal = Calendar.current
        // Active daily-rate missions: planned days of each future month, paid the month after.
        for mission in activeMissions where mission.billingMode != .fixed {
            for offset in 1...6 {
                guard let month = cal.date(byAdding: .month, value: offset, to: .now), month <= mission.endDate.addingTimeInterval(86_400 * 31) else { continue }
                let days = mission.billingMode == .daily ? 18.0 : 0
                let hours = mission.billingMode == .hourly ? 6.0 : 0
                let amount = Int(Double(mission.rateCents) * (days + hours))
                if amount > 0 { expected.append((month, amount)) }
            }
        }
        let monthlyCosts = s.rateInputs.yearlyCostsCents / 12 + Int(Double(s.rateInputs.targetNetCents) / 12)
        return CashFlow.forecast(start: cash, from: .now, months: 6, expected: expected, monthlyCosts: monthlyCosts)
    }

    private var cashFlowChart: some View {
        let points = forecast
        return VStack(alignment: .leading, spacing: 8) {
            Chart(points) { point in
                BarMark(x: .value("Month", point.month, unit: .month), y: .value("Expected income", Double(point.incomingCents) / 100))
                    .foregroundStyle(Brand.blue.gradient)
                    .cornerRadius(4)
                LineMark(x: .value("Month", point.month, unit: .month), y: .value("Balance", Double(point.balanceCents) / 100))
                    .foregroundStyle(Brand.positive)
                    .interpolationMethod(.catmullRom)
                    .symbol(.circle)
            }
            .chartYAxis { AxisMarks(format: .currency(code: "EUR").notation(.compactName)) }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .frame(height: 180)
            .accessibilityLabel("Cash flow forecast")
            if let low = points.first(where: { $0.balanceCents < 0 }) {
                Label("Your balance could go negative in \(low.month.formatted(.dateTime.month(.wide))). Time to line up the next mission.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Brand.warning)
            } else {
                Label("Bars: expected payments. Line: projected balance after your target pay and costs.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ThresholdRow: View {
    var title: LocalizedStringKey
    var revenue: Int
    var limit: Int

    var body: some View {
        let level = ThresholdLevel.level(revenue: revenue, limit: limit)
        let tint: Color = switch level {
        case .ok: Brand.positive
        case .approaching: Brand.warning
        case .critical, .exceeded: Brand.danger
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Money(cents: revenue).compact) / \(Money(cents: limit).compact)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Gauge(value: min(Double(revenue) / Double(max(limit, 1)), 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
            if level >= .approaching {
                Text(level == .exceeded ? "Threshold exceeded: check your status with your accountant."
                     : "You're getting close. Plan ahead with your accountant.")
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
