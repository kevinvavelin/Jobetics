import MapKit
import SwiftData
import SwiftUI

struct MissionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings
    @Environment(SafeBrowser.self) private var browser
    @Bindable var mission: Mission
    @State private var editing = false
    @State private var addingExpense: Expense?
    @State private var createdInvoice: BillingDocument?
    @State private var createdQuote: BillingDocument?

    private var monthStart: Date { Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now }

    var body: some View {
        List {
            Section { header }

            if mission.status.isPipeline {
                leadSection
            } else {
                Section {
                    TimeLogWeek(mission: mission)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: {
                    Text("This week")
                } footer: {
                    Text(mission.billingMode == .hourly
                         ? "Tap a day to log hours. Touch and hold to mark it on site."
                         : "Tap a day: full day, half day, off. Touch and hold to mark it on site.")
                }
            }

            if mission.needsTravel {
                TravelSection(mission: mission)
            }

            if !mission.status.isPipeline { monthSection }

            expensesSection
            ClientContactSection(mission: mission)
        }
        .navigationTitle(mission.title)
        .navigationSubtitle(mission.clientName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText, subject: Text(mission.title)) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) { MissionEditorView(mission: mission) }
        .sheet(item: $addingExpense) { ExpenseEditorView(expense: $0) }
        .navigationDestination(item: $createdInvoice) { BillingDetailView(document: $0) }
        .navigationDestination(item: $createdQuote) { BillingDetailView(document: $0) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(mission.rate.formatted).font(.largeTitle.bold().monospacedDigit())
                Text("/ \(mission.billingMode.unit)").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Status", selection: $mission.status) {
                        ForEach(MissionStatus.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Label(mission.status.title, systemImage: mission.status.symbol)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    metric("Earned", Money(cents: mission.earnedCents).formatted)
                    metric(mission.billingMode == .hourly ? "Hours" : "Days", (mission.billingMode == .hourly ? mission.hoursLogged : mission.daysLogged).formatted())
                    if let effective = mission.effectiveDailyRateCents, mission.billingMode != .daily {
                        metric("Per day", Money(cents: effective).formatted)
                    } else {
                        metric("Ends", mission.endDate.formatted(.dateTime.day().month(.abbreviated)))
                    }
                }
            }
            if mission.estimatedDays > 0 {
                ProgressView(value: min(mission.daysLogged / mission.estimatedDays, 1)) {
                    Text("\(mission.daysLogged.formatted()) of \(mission.estimatedDays.formatted()) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(Color.named(mission.colorName))
            }
        }
        .padding(.vertical, 6)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Lead

    @ViewBuilder private var leadSection: some View {
        Section("Lead") {
            if !mission.source.isEmpty { LabeledContent("Found on", value: mission.source) }
            if let url = mission.sourceURL {
                Button { browser.open(url) } label: { Label("Open listing", systemImage: "safari") }
            }
            LabeledContent("Planned start", value: mission.startDate.formatted(date: .abbreviated, time: .omitted))
            if mission.estimatedDays > 0 {
                LabeledContent("Potential", value: Money(cents: Int(Double(mission.rateCents) * (mission.billingMode == .fixed ? 1 : mission.estimatedDays))).formatted)
            }
            Button { createdQuote = createQuote() } label: { Label("Create a quote", systemImage: "doc.text.magnifyingglass") }
            Button {
                withAnimation { mission.status = .active }
            } label: {
                Label("Mission won: start it", systemImage: "checkmark.seal.fill")
            }
        }
    }

    // MARK: Month

    private var monthSection: some View {
        let report = mission.activityReport(for: .now)
        let lines = MissionInvoicing.lines(for: mission, month: .now, settings: settings.settings)
        let total = lines.reduce(0) { $0 + $1.totalCents }
        return Section {
            if let report {
                LabeledContent("Days worked", value: report.totalDays.formatted())
                if mission.needsTravel {
                    LabeledContent("On site", value: report.onSiteDays.formatted())
                }
            }
            LabeledContent("Ready to invoice", value: Money(cents: total).formatted)
                .fontWeight(.semibold)
            if mission.billingMode != .fixed {
                NavigationLink {
                    ActivityReportView(mission: mission, month: .now)
                } label: {
                    Label("Activity report", systemImage: "signature")
                }
            }
            Button {
                createdInvoice = MissionInvoicing.createInvoice(for: mission, month: .now, settings: settings, in: context)
            } label: {
                Label("Create invoice", systemImage: "doc.badge.plus")
            }
            .disabled(lines.isEmpty)
        } header: {
            Text(Date.now, format: .dateTime.month(.wide).year())
        } footer: {
            Text("The invoice includes logged days, travel fees and rebillable expenses not invoiced yet. It starts as a draft you can review.")
        }
    }

    // MARK: Expenses

    private var expensesSection: some View {
        Section {
            ForEach((mission.expenses ?? []).sorted { $0.date > $1.date }) { expense in
                ExpenseRow(expense: expense)
            }
            Button {
                let expense = Expense(date: .now, title: "", amountCents: 0, category: .transport, isRebillable: mission.travelPolicy == .actualCosts)
                expense.mission = mission
                context.insert(expense)
                addingExpense = expense
            } label: {
                Label("Add expense", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Expenses")
        }
    }

    // MARK: Helpers

    private var shareText: String {
        var text = "\(mission.title)"
        if !mission.clientName.isEmpty { text += " · \(mission.clientName)" }
        text += "\n" + String(localized: "\(mission.daysLogged.formatted()) days delivered so far.")
        return text
    }

    private func createQuote() -> BillingDocument {
        let quote = BillingDocument(kind: .quote, number: settings.nextNumber(for: .quote), clientName: mission.clientName,
                                    clientEmail: mission.client?.email ?? "", dueDate: .now.addingTimeInterval(86_400 * 30),
                                    taxRate: settings.settings.vatExempt ? 0 : settings.settings.defaultVATRate)
        quote.clientAddress = mission.client?.address ?? ""
        quote.missionTitle = mission.title
        context.insert(quote)
        let quantity = mission.billingMode == .fixed ? 1 : max(mission.estimatedDays, 1)
        let item = LineItem(title: mission.title, quantity: quantity, unitPriceCents: mission.rateCents)
        item.document = quote
        context.insert(item)
        mission.status = .quoted
        return quote
    }
}

// MARK: - Time logging

/// One week of days. Tap cycles full day → half day → off; touch and hold toggles "on site".
struct TimeLogWeek: View {
    @Environment(\.modelContext) private var context
    var mission: Mission
    @State private var weekOffset = 0
    @State private var hoursDay: Date?

    private var days: [Date] {
        let cal = Calendar.current
        let reference = cal.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
        guard let start = cal.dateInterval(of: .weekOfYear, for: reference)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Previous week", systemImage: "chevron.left") { withAnimation { weekOffset -= 1 } }
                    .labelStyle(.iconOnly)
                Spacer()
                Text(days.first ?? .now, format: .dateTime.day().month(.abbreviated))
                    .font(.subheadline.weight(.semibold))
                + Text(" – ") + Text(days.last ?? .now, format: .dateTime.day().month(.abbreviated)).font(.subheadline.weight(.semibold))
                Spacer()
                Button("Next week", systemImage: "chevron.right") { withAnimation { weekOffset += 1 } }
                    .labelStyle(.iconOnly)
                    .disabled(weekOffset >= 0)
            }
            .buttonStyle(.borderless)

            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, log: log(on: day), mission: mission) { tap(day) } onToggleSite: { toggleSite(day) }
                }
            }
        }
        .sheet(item: $hoursDay) { day in
            HoursSheet(day: day, hours: log(on: day)?.hours ?? 0) { hours in setHours(hours, on: day) }
                .presentationDetents([.height(260)])
        }
    }

    private func log(on day: Date) -> WorkLog? {
        (mission.logs ?? []).first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private func tap(_ day: Date) {
        if mission.billingMode == .hourly { hoursDay = day; return }
        let existing = log(on: day)
        guard existing?.isLocked != true else { return }
        withAnimation(.snappy) {
            switch existing?.days ?? 0 {
            case 0:
                if let existing { existing.days = 1; existing.hours = 7 } else { insert(day: day, days: 1) }
            case 1:
                existing?.days = 0.5
                existing?.hours = 3.5
            default:
                if let existing { context.delete(existing) }
            }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func toggleSite(_ day: Date) {
        guard mission.needsTravel else { return }
        if let existing = log(on: day) {
            guard !existing.isLocked else { return }
            existing.onSite.toggle()
        } else {
            insert(day: day, days: 1, onSite: true)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func insert(day: Date, days: Double, onSite: Bool? = nil) {
        let log = WorkLog(date: Calendar.current.startOfDay(for: day), days: days,
                          onSite: onSite ?? (mission.location == .onSite))
        log.mission = mission
        context.insert(log)
    }

    private func setHours(_ hours: Double, on day: Date) {
        if let existing = log(on: day) {
            guard !existing.isLocked else { return }
            if hours == 0 { context.delete(existing) } else { existing.hours = hours }
        } else if hours > 0 {
            let log = WorkLog(date: Calendar.current.startOfDay(for: day), days: 0, hours: hours)
            log.mission = mission
            context.insert(log)
        }
    }
}

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSinceReferenceDate }
}

private struct DayCell: View {
    var day: Date
    var log: WorkLog?
    var mission: Mission
    var onTap: () -> Void
    var onToggleSite: () -> Void

    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var amount: Double { mission.billingMode == .hourly ? (log?.hours ?? 0) : (log?.days ?? 0) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                ZStack {
                    Circle().fill(.fill.tertiary)
                    if amount > 0 {
                        Circle()
                            .trim(from: 0, to: mission.billingMode == .hourly ? min(amount / 7, 1) : amount)
                            .fill(Color.named(mission.colorName).gradient)
                            .rotationEffect(.degrees(-90))
                    }
                    Text(Calendar.current.component(.day, from: day), format: .number)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(amount >= 1 || (mission.billingMode == .hourly && amount > 0) ? .white : .primary)
                }
                .frame(width: 38, height: 38)
                .overlay(alignment: .topTrailing) {
                    if log?.isLocked == true {
                        Image(systemName: "lock.fill").font(.system(size: 9)).padding(3).background(.background, in: .circle)
                    }
                }
                Image(systemName: log?.onSite == true ? "building.2.fill" : "house")
                    .font(.system(size: 10))
                    .foregroundStyle(log?.onSite == true ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .opacity(mission.needsTravel && amount > 0 ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .opacity(isWeekend && amount == 0 ? 0.55 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.4, perform: onToggleSite)
        .accessibilityElement()
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month()))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(mission.billingMode == .hourly ? "Double-tap to log hours." : "Double-tap to change: full day, half day, off.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Toggle on site", onToggleSite)
    }

    private var accessibilityValue: Text {
        let base: Text = switch amount {
        case 0: Text("Not worked")
        case 0.5 where mission.billingMode != .hourly: Text("Half day")
        case 1 where mission.billingMode != .hourly: Text("Full day")
        default: Text("\(amount.formatted()) hours")
        }
        return log?.onSite == true ? base + Text(", on site") : base
    }
}

private struct HoursSheet: View {
    @Environment(\.dismiss) private var dismiss
    var day: Date
    @State var hours: Double
    var onSave: (Double) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $hours, in: 0...14, step: 0.25) {
                    LabeledContent("Hours", value: hours.formatted(.number.precision(.fractionLength(0...2))))
                }
            }
            .navigationTitle(Text(day, format: .dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) { onSave(hours); dismiss() }
                }
            }
        }
    }
}
