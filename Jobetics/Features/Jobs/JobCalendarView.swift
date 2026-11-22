import SwiftData
import SwiftUI

/// Month calendar of job milestones, project deadlines and meetings, with a day agenda.
struct JobCalendarView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var projects: [Project]
    @Query(sort: \Meeting.date) private var meetings: [Meeting]
    @Query private var tasks: [BoardTask]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selected = Calendar.current.startOfDay(for: .now)

    struct Event: Identifiable {
        let id = UUID()
        var date: Date
        var title: String
        var subtitle: String
        var symbol: String
        var tint: Color
    }

    private var events: [Event] {
        var list: [Event] = []
        for m in meetings {
            list.append(Event(date: m.date, title: m.title, subtitle: m.date.formatted(date: .omitted, time: .shortened),
                              symbol: "video.fill", tint: Color.named(m.project?.colorName ?? "")))
        }
        for p in projects {
            list.append(Event(date: p.dueDate, title: p.name, subtitle: String(localized: "Project deadline"), symbol: "flag.checkered", tint: Color.named(p.colorName)))
        }
        for t in tasks where t.status != .done {
            if let due = t.dueDate {
                list.append(Event(date: due, title: t.title, subtitle: t.project?.name ?? "", symbol: t.status.symbol, tint: Color.named(t.project?.colorName ?? "")))
            }
        }
        for j in store.matchedJobs.prefix(8) {
            list.append(Event(date: j.startDate, title: j.title, subtitle: String(localized: "Job starts · \(j.budget.formatted)"), symbol: "briefcase.fill", tint: j.discipline.tint))
        }
        return list
    }

    var body: some View {
        let cal = Calendar.current
        let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: selected) }.sorted { $0.date < $1.date }
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 20) {
                    monthGrid.frame(maxWidth: 520)
                    agenda(dayEvents)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        monthGrid
                        agenda(dayEvents)
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calendar")
    }

    private var monthGrid: some View {
        let cal = Calendar.current
        let days = monthDays()
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shifted = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return Card {
            HStack {
                Text(month, format: .dateTime.month(.wide).year()).font(.title3.bold())
                Spacer()
                Button("Previous month", systemImage: "chevron.left") { shift(-1) }.labelStyle(.iconOnly)
                Button("Next month", systemImage: "chevron.right") { shift(1) }.labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(shifted.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 44) }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let tints = events.filter { cal.isDate($0.date, inSameDayAs: day) }.prefix(3).map(\.tint)
        return Button {
            withAnimation(.snappy) { selected = day }
        } label: {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.day())
                    .font(.callout.weight(isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : isToday ? Brand.indigo : .primary)
                HStack(spacing: 2) {
                    ForEach(Array(tints.enumerated()), id: \.offset) { _, tint in
                        Circle().fill(isSelected ? .white : tint).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isSelected { Circle().fill(Brand.gradient).frame(width: 40, height: 40) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(Text("\(tints.count) events"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func agenda(_ dayEvents: [Event]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selected, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title3.bold())
                .padding(.horizontal, 4)
            if dayEvents.isEmpty {
                Card {
                    Label("Nothing planned. A good day for deep work.", systemImage: "sun.max.fill")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(dayEvents) { event in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2).fill(event.tint).frame(width: 4)
                    Image(systemName: event.symbol).foregroundStyle(event.tint).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(event.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func shift(_ months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: month) {
            withAnimation(.snappy) { month = next }
        }
    }

    private func monthDays() -> [Date?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
    }
}
