import SwiftData
import SwiftUI

/// Calendar of the freelancer's work, laid out like Apple Calendar:
/// iPad: full-bleed month grid with events inside each day, and a day inspector.
/// iPhone: compact month with dots, and the selected day's agenda below.
struct JobCalendarView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var projects: [Project]
    @Query(sort: \Meeting.date) private var meetings: [Meeting]
    @Query private var tasks: [BoardTask]
    @Query private var missions: [Mission]
    @Query(filter: #Predicate<BillingDocument> { $0.kindRaw == "invoice" }) private var invoices: [BillingDocument]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var showsInspector = true

    struct Event: Identifiable {
        var id: String
        var date: Date
        var title: String
        var subtitle: String
        var symbol: String
        var tint: Color
        var isAllDay: Bool
        var durationMinutes: Int = 0
    }

    // MARK: Events

    private var events: [Event] {
        var list: [Event] = []
        for m in meetings {
            list.append(Event(id: "m\(m.persistentModelID.hashValue)", date: m.date, title: m.title, subtitle: m.project?.clientName ?? "",
                              symbol: "video.fill", tint: Color.named(m.project?.colorName ?? ""), isAllDay: false, durationMinutes: m.durationMinutes))
        }
        for mission in missions where mission.status == .active || mission.status.isPipeline {
            let tint = Color.named(mission.colorName)
            for log in mission.logs ?? [] {
                let amount = mission.billingMode == .hourly ? "\(log.hours.formatted()) h" : (log.days == 1 ? String(localized: "Full day") : String(localized: "Half day"))
                list.append(Event(id: "l\(log.persistentModelID.hashValue)", date: log.date, title: mission.title,
                                  subtitle: log.onSite ? String(localized: "\(amount) · on site") : amount,
                                  symbol: log.onSite ? "building.2.fill" : "house.fill", tint: tint, isAllDay: true))
            }
            if mission.status.isPipeline {
                list.append(Event(id: "s\(mission.persistentModelID.hashValue)", date: mission.startDate, title: mission.title,
                                  subtitle: String(localized: "Possible start · \(mission.status.title)"), symbol: "sparkle.magnifyingglass", tint: tint, isAllDay: true))
            } else {
                list.append(Event(id: "e\(mission.persistentModelID.hashValue)", date: mission.endDate, title: mission.title,
                                  subtitle: String(localized: "Mission ends"), symbol: "flag.checkered", tint: tint, isAllDay: true))
            }
        }
        for p in projects where !p.isArchived {
            list.append(Event(id: "p\(p.persistentModelID.hashValue)", date: p.dueDate, title: p.name, subtitle: String(localized: "Project deadline"),
                              symbol: "flag.checkered", tint: Color.named(p.colorName), isAllDay: true))
        }
        for t in tasks where t.status != .done {
            if let due = t.dueDate {
                list.append(Event(id: "t\(t.persistentModelID.hashValue)", date: due, title: t.title, subtitle: t.project?.name ?? "",
                                  symbol: t.status.symbol, tint: Color.named(t.project?.colorName ?? ""), isAllDay: true))
            }
        }
        for invoice in invoices where (invoice.status == .sent || invoice.status == .overdue) && !invoice.isCancelled {
            list.append(Event(id: "i\(invoice.number)", date: invoice.dueDate, title: String(localized: "\(invoice.clientName) pays \(invoice.total.formatted)"),
                              subtitle: invoice.number, symbol: "eurosign.circle.fill", tint: invoice.isOverdue ? Brand.danger : Brand.positive, isAllDay: true))
        }
        for j in store.matchedJobs.prefix(8) {
            list.append(Event(id: "j\(j.id)", date: j.startDate, title: j.title, subtitle: String(localized: "Job starts · \(j.budget.formatted)"),
                              symbol: "briefcase.fill", tint: j.discipline.tint, isAllDay: true))
        }
        return list
    }

    private func events(on day: Date, in all: [Event]) -> [Event] {
        all.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.date) < ($1.isAllDay ? 0 : 1, $1.date) }
    }

    // MARK: Body

    var body: some View {
        let all = events
        Group {
            if sizeClass == .regular {
                MonthGrid(month: month, selected: $selected, events: all, eventsOn: events(on:in:))
                    .inspector(isPresented: $showsInspector) {
                        DayAgenda(day: selected, events: events(on: selected, in: all))
                            .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                    }
            } else {
                CompactMonth(month: $month, selected: $selected, events: all, eventsOn: events(on:in:)) { shift($0) }
            }
        }
        .navigationTitle(Text(month, format: .dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") { goToToday() }
                    .disabled(Calendar.current.isDateInToday(selected) && Calendar.current.isDate(month, equalTo: .now, toGranularity: .month))
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Previous month", systemImage: "chevron.left") { shift(-1) }
                Button("Next month", systemImage: "chevron.right") { shift(1) }
            }
            if sizeClass == .regular {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Day details", systemImage: "sidebar.trailing") { showsInspector.toggle() }
                }
            }
        }
    }

    private func shift(_ months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.snappy) {
            month = next
            if !Calendar.current.isDate(selected, equalTo: next, toGranularity: .month) {
                selected = Calendar.current.isDate(next, equalTo: .now, toGranularity: .month) ? Calendar.current.startOfDay(for: .now) : next
            }
        }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            month = Calendar.current.dateInterval(of: .month, for: .now)!.start
            selected = Calendar.current.startOfDay(for: .now)
        }
    }
}

// MARK: - Shared helpers

enum CalendarMath {
    /// Full weeks covering the month, including the trailing/leading days of adjacent months.
    static func weeks(for month: Date, calendar cal: Calendar = .current) -> [[Date]] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let firstWeek = cal.dateInterval(of: .weekOfYear, for: interval.start),
              let lastWeek = cal.dateInterval(of: .weekOfYear, for: interval.end.addingTimeInterval(-1)) else { return [] }
        var weeks: [[Date]] = []
        var day = firstWeek.start
        while day < lastWeek.end {
            weeks.append((0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: day) })
            day = cal.date(byAdding: .day, value: 7, to: day)!
        }
        return weeks
    }

    static var weekdaySymbols: [String] {
        let cal = Calendar.current
        let symbols = cal.shortStandaloneWeekdaySymbols
        return Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
    }

    static var narrowWeekdaySymbols: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
    }
}

/// Day number as Apple Calendar draws it: today in a filled tint circle, selection in a filled primary circle.
private struct DayNumber: View {
    var day: Date
    var isSelected: Bool
    var inMonth: Bool
    var size: CGFloat = 30
    var font: Font = .callout

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        Text(day, format: .dateTime.day())
            .font(font.weight(isToday || isSelected ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(isToday && isSelected || isToday ? AnyShapeStyle(.white) : isSelected ? AnyShapeStyle(Color(.systemBackground))
                             : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: size, height: size)
            .background {
                if isToday { Circle().fill(.tint) } else if isSelected { Circle().fill(.primary) }
            }
    }
}

// MARK: - iPad month grid

private struct MonthGrid: View {
    var month: Date
    @Binding var selected: Date
    var events: [JobCalendarView.Event]
    var eventsOn: (Date, [JobCalendarView.Event]) -> [JobCalendarView.Event]

    var body: some View {
        let weeks = CalendarMath.weeks(for: month)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(CalendarMath.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
            }
            .padding(.vertical, 6)
            Divider()
            GeometryReader { proxy in
                let rowHeight = proxy.size.height / CGFloat(max(weeks.count, 1))
                VStack(spacing: 0) {
                    ForEach(weeks, id: \.first) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                MonthCell(day: day, inMonth: Calendar.current.isDate(day, equalTo: month, toGranularity: .month),
                                          isSelected: Calendar.current.isDate(day, inSameDayAs: selected),
                                          events: eventsOn(day, events), height: rowHeight) {
                                    withAnimation(.snappy) { selected = day }
                                }
                                if day != week.last { Divider() }
                            }
                        }
                        .frame(height: rowHeight)
                        Divider()
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

private struct MonthCell: View {
    var day: Date
    var inMonth: Bool
    var isSelected: Bool
    var events: [JobCalendarView.Event]
    var height: CGFloat
    var onSelect: () -> Void

    var body: some View {
        // ~18 pt per event line under a 34 pt header.
        let capacity = max(Int((height - 38) / 18), 0)
        let visible = events.count > capacity ? Array(events.prefix(max(capacity - 1, 0))) : events
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                DayNumber(day: day, isSelected: isSelected, inMonth: inMonth, size: 28, font: .subheadline)
            }
            .padding(.top, 4)
            .padding(.trailing, 4)
            ForEach(visible) { event in EventPill(event: event) }
            if visible.count < events.count {
                Text("\(events.count - visible.count) more")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.06) : inMonth ? .clear : Color(.secondarySystemBackground).opacity(0.5))
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(Text(events.isEmpty ? "No events" : events.map(\.title).joined(separator: ", ")))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Apple Calendar-style event: all-day events are tinted pills, timed events a dot, title and time.
private struct EventPill: View {
    var event: JobCalendarView.Event

    var body: some View {
        if event.isAllDay {
            Text(event.title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(event.tint.mix(with: .primary, by: 0.35))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(event.tint.opacity(0.18), in: .rect(cornerRadius: 4, style: .continuous))
        } else {
            HStack(spacing: 4) {
                Circle().fill(event.tint).frame(width: 6, height: 6)
                Text(event.title).font(.caption2).lineLimit(1)
                Spacer(minLength: 2)
                Text(event.date, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 5)
        }
    }
}

// MARK: - iPhone

private struct CompactMonth: View {
    @Binding var month: Date
    @Binding var selected: Date
    var events: [JobCalendarView.Event]
    var eventsOn: (Date, [JobCalendarView.Event]) -> [JobCalendarView.Event]
    var shift: (Int) -> Void

    var body: some View {
        let weeks = CalendarMath.weeks(for: month)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(CalendarMath.narrowWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
                ForEach(weeks, id: \.first) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            let inMonth = Calendar.current.isDate(day, equalTo: month, toGranularity: .month)
                            let dayEvents = eventsOn(day, events)
                            Button {
                                withAnimation(.snappy) {
                                    selected = day
                                    if !inMonth { shift(day < month ? -1 : 1) }
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    DayNumber(day: day, isSelected: Calendar.current.isDate(day, inSameDayAs: selected), inMonth: inMonth, size: 32, font: .body)
                                    HStack(spacing: 2) {
                                        ForEach(Array(Set(dayEvents.map(\.tint)).prefix(3).enumerated()), id: \.offset) { _, tint in
                                            Circle().fill(tint).frame(width: 5, height: 5)
                                        }
                                    }
                                    .frame(height: 5)
                                    .opacity(inMonth ? 1 : 0.4)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 3)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
                            .accessibilityValue(Text("^[\(dayEvents.count) event](inflect: true)"))
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -50 { shift(1) } else if value.translation.width > 50 { shift(-1) }
            })
            Divider()
            DayAgenda(day: selected, events: eventsOn(selected, events))
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Day agenda

private struct DayAgenda: View {
    var day: Date
    var events: [JobCalendarView.Event]

    var body: some View {
        List {
            Section {
                if events.isEmpty {
                    Label("Nothing planned. A good day for deep work.", systemImage: "sun.max")
                        .foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .trailing, spacing: 0) {
                            if event.isAllDay {
                                Text("all-day").font(.caption)
                            } else {
                                Text(event.date, format: .dateTime.hour().minute()).font(.caption.monospacedDigit())
                                if event.durationMinutes > 0 {
                                    Text(event.date.addingTimeInterval(Double(event.durationMinutes) * 60), format: .dateTime.hour().minute())
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(width: 52, alignment: .trailing)
                        RoundedRectangle(cornerRadius: 2).fill(event.tint).frame(width: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Label(event.subtitle, systemImage: event.symbol).font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
    }
}
