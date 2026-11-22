import Foundation
import SwiftData

/// Sample private data (projects, tasks, invoices, ledger, portfolio) for demo mode.
enum DemoSeed {
    static func seedIfNeeded(_ context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Project>())) == 0 else { return }
        let cal = Calendar.current
        func day(_ d: Int, hour: Int = 10, minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: d, to: .now)!)!
        }

        let northwind = Project(name: "Northwind Banking", clientName: "Northwind Bank", colorName: "indigo",
                                symbol: "building.columns.fill", startDate: day(-3), dueDate: day(32), budgetCents: 950_000)
        let lumen = Project(name: "Lumen Design System", clientName: "Lumen Health", colorName: "teal",
                            symbol: "heart.text.square.fill", startDate: day(-20), dueDate: day(60), budgetCents: 1_440_000)
        let atlas = Project(name: "Atlas Onboarding", clientName: "Atlas Travel", colorName: "orange",
                            symbol: "airplane", startDate: day(-10), dueDate: day(4), budgetCents: 320_000)
        [northwind, lumen, atlas].forEach(context.insert)

        let tasks: [(Project, String, TaskStatus, Int?, Double)] = [
            (northwind, "Audit current app flows", .doing, 2, 6),
            (northwind, "Accessibility review (Dynamic Type, VoiceOver)", .todo, 6, 4),
            (northwind, "Liquid Glass component inventory", .todo, 8, 8),
            (northwind, "Kickoff workshop agenda", .done, -1, 2),
            (northwind, "Tab bar & toolbar explorations", .review, 3, 5),
            (northwind, "Define color & material tokens", .todo, 10, 6),
            (lumen, "Token pipeline with engineering", .doing, 5, 10),
            (lumen, "Button & form components", .review, 1, 8),
            (lumen, "Contribution guidelines", .todo, 14, 4),
            (lumen, "Documentation site structure", .done, -4, 3),
            (atlas, "Interview synthesis", .done, -2, 4),
            (atlas, "Hi-fi prototype v2", .doing, 1, 8),
            (atlas, "Usability test round 2", .todo, 3, 4),
        ]
        for (i, t) in tasks.enumerated() {
            let task = BoardTask(title: t.1, status: t.2, order: Double(i), dueDate: t.3.map { day($0) }, estimateHours: t.4)
            task.project = t.0
            context.insert(task)
        }

        let meetings: [(Project, String, Date, Bool?)] = [
            (northwind, "Kickoff with Northwind", day(2, hour: 10), nil),
            (lumen, "Design system sync", day(1, hour: 14, minute: 30), nil),
            (atlas, "Prototype review", day(3, hour: 11), nil),
            (lumen, "Weekly sync", day(-6, hour: 14, minute: 30), true),
            (atlas, "Interview debrief", day(-3, hour: 9), true),
            (northwind, "Intro call", day(-4, hour: 16), true),
        ]
        for m in meetings {
            let meeting = Meeting(title: m.1, date: m.2, onTime: m.3)
            meeting.project = m.0
            context.insert(meeting)
        }

        func document(_ kind: BillingKind, _ number: String, _ client: String, issued: Int, due: Int, status: BillingStatus, items: [(String, Double, Int)]) {
            let doc = BillingDocument(kind: kind, number: number, clientName: client, clientEmail: "billing@example.com",
                                      issueDate: day(issued), dueDate: day(due), status: status)
            doc.clientAddress = "12 Example Street\n75000 Paris, France"
            doc.notes = kind == .invoice ? "Payment by bank transfer within 30 days." : "Valid for 30 days. 30% deposit on acceptance."
            context.insert(doc)
            for (i, item) in items.enumerated() {
                let line = LineItem(title: item.0, quantity: item.1, unitPriceCents: item.2, order: Double(i))
                line.document = doc
                context.insert(line)
            }
        }
        document(.invoice, "INV-2026-031", "Lumen Health", issued: -12, due: 18, status: .sent,
                 items: [("Design system: sprint 3", 1, 480_000), ("Component documentation", 12, 9_000)])
        document(.invoice, "INV-2026-030", "Atlas Travel", issued: -40, due: -10, status: .overdue,
                 items: [("Discovery & interviews", 1, 160_000)])
        document(.invoice, "INV-2026-029", "Lumen Health", issued: -42, due: -12, status: .paid,
                 items: [("Design system: sprint 2", 1, 480_000)])
        document(.invoice, "INV-2026-028", "Kite Labs", issued: -70, due: -40, status: .paid,
                 items: [("Brand refresh", 1, 350_000), ("Icon set (24 icons)", 24, 4_500)])
        document(.quote, "Q-2026-014", "Northwind Bank", issued: -2, due: 28, status: .accepted,
                 items: [("UX audit (1 week)", 5, 72_000), ("Liquid Glass component library", 1, 590_000)])
        document(.quote, "Q-2026-015", "Orbit Apps", issued: -1, due: 29, status: .sent,
                 items: [("Widget & watchOS design", 1, 420_000), ("Design QA", 8, 8_500)])
        document(.quote, "Q-2026-013", "Ferris", issued: -15, due: 15, status: .draft,
                 items: [("Pricing page redesign", 1, 260_000)])

        let incomes: [(Int, Int, String)] = [
            (-330, 520_000, "Kite Labs"), (-300, 610_000, "Lumen Health"), (-270, 450_000, "Atlas Travel"),
            (-240, 700_000, "Lumen Health"), (-210, 380_000, "Ferris"), (-180, 820_000, "Northwind Bank"),
            (-150, 640_000, "Lumen Health"), (-120, 560_000, "Kite Labs"), (-90, 910_000, "Lumen Health"),
            (-60, 458_000, "Kite Labs"), (-35, 480_000, "Lumen Health"), (-8, 590_000, "Northwind Bank"),
        ]
        for (i, inc) in incomes.enumerated() {
            context.insert(LedgerEntry(date: day(inc.0), amountCents: inc.1, kind: .income, category: "Client work",
                                       counterparty: inc.2, invoiceNumber: "INV-2026-\(String(format: "%03d", 17 + i))"))
        }
        let expenses: [(Int, Int, String, String)] = [
            (-320, 18_000, "Software", "Figma"), (-290, 120_000, "Equipment", "Studio display"), (-250, 18_000, "Software", "Figma"),
            (-200, 45_000, "Coworking", "Station F"), (-170, 45_000, "Coworking", "Station F"), (-140, 32_000, "Travel", "Train to Lyon"),
            (-110, 45_000, "Coworking", "Station F"), (-80, 18_000, "Software", "Figma"), (-50, 45_000, "Coworking", "Station F"),
            (-30, 9_900, "Software", "Apple Developer"), (-12, 45_000, "Coworking", "Station F"), (-5, 24_000, "Training", "Accessibility course"),
        ]
        for e in expenses {
            context.insert(LedgerEntry(date: day(e.0), amountCents: e.1, kind: .expense, category: e.2, counterparty: e.3))
        }

        let portfolio: [(String, String, Discipline, [String])] = [
            ("Northwind Banking", "Liquid Glass redesign of a retail banking app, 2M users.", .design, ["iOS", "Design system"]),
            ("Lumen Health DS", "Tokens, 80+ components and docs used by 6 squads.", .design, ["Design system", "Docs"]),
            ("Atlas Travel", "Onboarding that lifted activation by 23%.", .design, ["Research", "Prototype"]),
            ("Kite Labs Brand", "Identity, icon set and launch website.", .design, ["Branding", "Icons"]),
            ("Orbit Widgets", "Interactive widgets & Apple Watch companion.", .design, ["WidgetKit", "watchOS"]),
            ("Ferris Pricing", "Pricing page and packaging experiments.", .design, ["Web", "Growth"]),
        ]
        for (i, p) in portfolio.enumerated() {
            context.insert(PortfolioItem(title: p.0, summary: p.1, discipline: p.2, link: URL(string: "https://www.behance.net/example"),
                                         tags: p.3, createdAt: day(-30 * i)))
        }
        try? context.save()
    }
}
