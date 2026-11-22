import Charts
import SwiftData
import SwiftUI

struct AccountingView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(filter: #Predicate<BillingDocument> { $0.kindRaw == "invoice" }) private var invoices: [BillingDocument]
    @State private var showsNewEntry = false

    private var yearStart: Date { Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now }
    private var last12: [LedgerEntry] { entries.filter { $0.date > Calendar.current.date(byAdding: .month, value: -12, to: .now)! } }
    private func sum(_ kind: LedgerKind, since: Date) -> Int { entries.filter { $0.kind == kind && $0.date >= since }.reduce(0) { $0 + $1.amountCents } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let revenue = sum(.income, since: yearStart)
                let expenses = sum(.expense, since: yearStart)
                let outstanding = invoices.filter { $0.status == .sent || $0.status == .overdue }.reduce(0) { $0 + $1.total.cents }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 200 : 150), spacing: 12)], spacing: 12) {
                    StatTile(title: "Revenue this year", value: Money(cents: revenue).formatted, symbol: "arrow.up.right", tint: Brand.positive)
                    StatTile(title: "Expenses", value: Money(cents: expenses).formatted, symbol: "arrow.down.right", tint: Brand.danger)
                    StatTile(title: "Net profit", value: Money(cents: revenue - expenses).formatted, symbol: "equal.circle.fill", tint: Brand.indigo)
                    StatTile(title: "Outstanding", value: Money(cents: outstanding).formatted, symbol: "hourglass", tint: Brand.warning)
                }

                Card {
                    Text("Income vs. expenses").font(.headline)
                    Chart(last12) { entry in
                        BarMark(x: .value("Month", entry.date, unit: .month),
                                y: .value("Amount", Double(entry.amountCents) / 100))
                            .foregroundStyle(by: .value("Type", entry.kind.title))
                            .position(by: .value("Type", entry.kind.title))
                            .cornerRadius(4)
                    }
                    .chartForegroundStyleScale([LedgerKind.income.title: Brand.indigo, LedgerKind.expense.title: Brand.danger.opacity(0.8)])
                    .chartYAxis { AxisMarks(format: .currency(code: "EUR").notation(.compactName)) }
                    .frame(height: 240)
                }

                HStack(alignment: .top, spacing: 20) {
                    Card {
                        Text("Expenses by category").font(.headline)
                        let byCategory = Dictionary(grouping: last12.filter { $0.kind == .expense }, by: \.category)
                            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amountCents }) }
                            .sorted { $0.total > $1.total }
                        Chart(byCategory, id: \.category) { item in
                            SectorMark(angle: .value("Total", item.total), innerRadius: .ratio(0.6), angularInset: 2)
                                .foregroundStyle(by: .value("Category", item.category))
                                .cornerRadius(4)
                        }
                        .frame(height: 200)
                    }
                    if sizeClass == .regular {
                        Card {
                            Text("Top clients").font(.headline)
                            let clients = Dictionary(grouping: last12.filter { $0.kind == .income }, by: \.counterparty)
                                .map { (name: $0.key, total: $0.value.reduce(0) { $0 + $1.amountCents }) }
                                .sorted { $0.total > $1.total }
                            ForEach(clients.prefix(5), id: \.name) { client in
                                LabeledContent(client.name, value: Money(cents: client.total).formatted)
                            }
                        }
                    }
                }

                SectionHeader("Transactions")
                Card(padding: 4) {
                    ForEach(entries.prefix(15)) { entry in
                        HStack {
                            Image(systemName: entry.kind == .income ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                                .foregroundStyle(entry.kind == .income ? Brand.positive : Brand.danger)
                                .font(.title3)
                            VStack(alignment: .leading) {
                                Text(entry.counterparty).font(.subheadline.weight(.medium))
                                Text("\(entry.category) · \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((entry.kind == .income ? "+" : "−") + entry.money.formatted)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(entry.kind == .income ? Brand.positive : .primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Accounting")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Add entry", systemImage: "plus") { showsNewEntry = true } }
        }
        .sheet(isPresented: $showsNewEntry) { LedgerEntryEditor() }
    }
}

struct LedgerEntryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: LedgerKind = .expense
    @State private var amount: Double = 0
    @State private var category = ""
    @State private var counterparty = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) { ForEach(LedgerKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                TextField("Amount", value: $amount, format: .currency(code: "EUR")).keyboardType(.decimalPad)
                TextField(kind == .income ? "Client" : "Vendor", text: $counterparty)
                TextField("Category", text: $category)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("New entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) {
                        context.insert(LedgerEntry(date: date, amountCents: Int((amount * 100).rounded()), kind: kind,
                                                   category: category, counterparty: counterparty))
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Payouts received, month by month, with an estimated amount to set aside for taxes.
struct PayoutsView: View {
    @Query(filter: #Predicate<LedgerEntry> { $0.kindRaw == "income" }, sort: \LedgerEntry.date, order: .reverse)
    private var payouts: [LedgerEntry]
    @AppStorage("taxSetAside") private var taxRate = 25.0

    private var months: [(month: Date, entries: [LedgerEntry])] {
        Dictionary(grouping: payouts) { Calendar.current.dateInterval(of: .month, for: $0.date)!.start }
            .map { ($0.key, $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        List {
            Section {
                let total = payouts.reduce(0) { $0 + $1.amountCents }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Received in the last 12 months").font(.subheadline).foregroundStyle(.secondary)
                    Text(Money(cents: total).formatted).font(.largeTitle.bold()).foregroundStyle(Brand.gradient)
                    Text("Set aside for taxes: \(Money(cents: Int(Double(total) * taxRate / 100)).formatted)")
                        .font(.footnote).foregroundStyle(.secondary)
                    Chart(months.reversed(), id: \.month) { month in
                        AreaMark(x: .value("Month", month.month, unit: .month),
                                 y: .value("Net", Double(month.entries.reduce(0) { $0 + $1.amountCents }) / 100 * (1 - taxRate / 100)))
                            .foregroundStyle(Brand.gradient.opacity(0.35))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Month", month.month, unit: .month),
                                 y: .value("Net", Double(month.entries.reduce(0) { $0 + $1.amountCents }) / 100 * (1 - taxRate / 100)))
                            .foregroundStyle(Brand.indigo)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYAxis { AxisMarks(format: .currency(code: "EUR").notation(.compactName)) }
                    .frame(height: 160)
                }
                .padding(.vertical, 6)
                Stepper("Tax set-aside: \(taxRate.formatted())%", value: $taxRate, in: 0...60, step: 1)
            }
            ForEach(months, id: \.month) { month in
                Section(month.month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(month.entries) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.counterparty).font(.subheadline.weight(.medium))
                                if let number = entry.invoiceNumber { Text(number).font(.caption.monospaced()).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(entry.money.formatted).font(.subheadline.weight(.semibold).monospacedDigit())
                                Text("Net \(Money(cents: Int(Double(entry.amountCents) * (1 - taxRate / 100))).formatted)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Payouts")
    }
}
