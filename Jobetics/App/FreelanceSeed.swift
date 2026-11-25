import Foundation
import SwiftData

/// Demo data for the freelance ERP: a Lyon-based freelancer with one long on-site mission,
/// a short fixed-price audit, an hourly coaching gig, leads, expenses and journal entries.
enum FreelanceSeed {
    static func seedIfNeeded(_ context: ModelContext, settings: SettingsStore) {
        guard (try? context.fetchCount(FetchDescriptor<Mission>())) == 0 else { return }
        let cal = Calendar.current
        func day(_ d: Int) -> Date { cal.startOfDay(for: cal.date(byAdding: .day, value: d, to: .now)!) }

        var s = BusinessSettings()
        s.legalName = "Camille Laurent"
        s.tradeName = "Camille Laurent Studio"
        s.jobTitle = String(localized: "Product designer & iOS developer")
        s.address = "8 place Bellecour\n69002 Lyon"
        s.homeAddress = "8 place Bellecour, 69002 Lyon, France"
        s.siret = "912 345 678 00017"
        s.email = "hello@camille.studio"
        s.phone = "+33 6 12 34 56 78"
        s.website = "https://camille.studio"
        s.iban = "FR76 3000 6000 0112 3456 7890 189"
        s.vehicleHorsepower = 5
        s.vatExempt = false
        s.vatNumber = "FR12912345678"
        s.rateInputs = RateInputs(targetNetCents: 4_800_000, contributionRate: 0.261, yearlyCostsCents: 450_000,
                                  vacationDays: 25, publicHolidays: 11, nonBillableDaysPerMonth: 2)
        for number in ["FAC-2026-0031", "DEV-2026-0015"] { s.numbering.register(existing: number) }
        settings.settings = s

        let acme = Client(name: "Acme Banque SA", contactName: "Claire Martin", email: "claire.martin@acme-banque.example",
                          phone: "+33 6 98 76 54 32", address: "12 rue de la Bourse\n69002 Lyon", siret: "552 120 222 00013", paymentTermsDays: 30)
        let nuage = Client(name: "Studio Nuage SAS", contactName: "Hugo Bernard", email: "hugo@studionuage.example",
                           address: "40 rue du Faubourg Poissonnière\n75010 Paris", siret: "812 345 678 00021", paymentTermsDays: 30)
        let verdi = Client(name: "Verdi Health", contactName: "Inès Moreau", email: "ines@verdi.example",
                           address: "5 quai de la Fosse\n44000 Nantes", paymentTermsDays: 45)
        let orbit = Client(name: "Orbit Apps", contactName: "Léa Petit", email: "lea@orbit.example", address: "Bordeaux")
        [acme, nuage, verdi, orbit].forEach(context.insert)

        let refonte = Mission(title: String(localized: "iOS app redesign"), client: acme, status: .active, billingMode: .daily,
                              rateCents: 62_000, startDate: day(-300), endDate: day(23), location: .hybrid)
        refonte.siteAddress = "Parc Technologique, 69800 Saint-Priest, France"
        refonte.onSiteDaysPerWeek = 3
        refonte.oneWayKm = 35
        refonte.commuteMinutes = 40
        refonte.transport = .car
        refonte.travelPolicy = .actualCosts
        refonte.colorName = "indigo"
        refonte.symbol = "building.columns.fill"
        refonte.estimatedDays = 210
        refonte.purchaseOrder = "PO-2026-118"

        let audit = Mission(title: String(localized: "SwiftUI accessibility audit"), client: nuage, status: .active, billingMode: .fixed,
                            rateCents: 240_000, startDate: day(-3), endDate: day(2), location: .remote)
        audit.estimatedDays = 4
        audit.colorName = "teal"
        audit.symbol = "accessibility"

        let coaching = Mission(title: String(localized: "CTO coaching"), client: verdi, status: .active, billingMode: .hourly,
                               rateCents: 8_500, startDate: day(-120), endDate: day(180), location: .remote)
        coaching.colorName = "pink"
        coaching.symbol = "person.2.wave.2.fill"

        let lead = Mission(title: String(localized: "Widgets & watchOS companion"), client: orbit, status: .quoted, billingMode: .daily,
                           rateCents: 65_000, startDate: day(30), endDate: day(120), location: .remote)
        lead.source = "Malt"
        lead.estimatedDays = 40
        lead.colorName = "orange"
        lead.symbol = "applewatch"

        let lead2 = Mission(title: String(localized: "Design system for a fintech"), status: .lead, billingMode: .daily,
                            rateCents: 60_000, startDate: day(45), endDate: day(225), location: .hybrid)
        lead2.source = "LinkedIn"
        lead2.sourceURL = URL(string: "https://www.linkedin.com/jobs/")
        lead2.colorName = "purple"
        lead2.symbol = "square.stack.3d.up.fill"
        [refonte, audit, coaching, lead, lead2].forEach(context.insert)

        // This month: 3 days on site, 2 remote per week for the long mission.
        let month = cal.dateInterval(of: .month, for: .now)!
        var date = month.start
        while date < cal.startOfDay(for: .now) {
            let weekday = cal.component(.weekday, from: date)
            if (2...6).contains(weekday) {
                let onSite = [2, 3, 5].contains(weekday)
                let log = WorkLog(date: date, days: weekday == 6 ? 0.5 : 1, onSite: onSite)
                log.workspaceName = onSite ? "Acme Saint-Priest" : String(localized: "Home office")
                log.mission = refonte
                context.insert(log)
                if weekday == 6 {
                    let half = WorkLog(date: date, days: 0, hours: 2, note: String(localized: "Architecture review"))
                    half.mission = coaching
                    context.insert(half)
                }
            }
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        for d in [-3, -2, -1] {
            let log = WorkLog(date: day(d), days: 1, note: String(localized: "VoiceOver & Dynamic Type review"))
            log.mission = audit
            context.insert(log)
        }

        let expenses: [(Int, String, Int, Int, ExpenseCategory, Bool, Mission?)] = [
            (-8, "SNCF TGV Lyon → Paris (A/R)", 12_800, 1_164, .transport, true, audit),
            (-6, "Parking Saint-Priest", 1_200, 200, .transport, true, refonte),
            (-4, "La Cordée Lyon: day pass", 2_500, 417, .coworking, false, nil),
            (-15, "Figma Professional", 1_500, 250, .software, false, nil),
            (-2, "Lunch workshop Acme", 3_400, 309, .meals, false, refonte),
        ]
        for e in expenses {
            let expense = Expense(date: day(e.0), title: e.1, amountCents: e.2, category: e.4, isRebillable: e.5, vatCents: e.3)
            expense.mission = e.6
            context.insert(expense)
        }

        context.insert(Workspace(name: String(localized: "Home office"), kind: .home, address: s.homeAddress, isDefault: true))
        context.insert(Workspace(name: "La Cordée Lyon", kind: .coworking, address: "La Cordée, Lyon", dayCostCents: 2_500))
        context.insert(Workspace(name: "Acme Saint-Priest", kind: .clientSite, address: refonte.siteAddress))
        context.insert(Workspace(name: "TGV", kind: .travel))

        let journal: [(Int, String, Int, String)] = [
            (-1, String(localized: "Ran the accessibility review with the Nuage team. Three screens were unusable with VoiceOver; we fixed two together in an hour."), 4,
             String(localized: "Blind users can now book an appointment on their own.")),
            (-3, String(localized: "Long day on site. Presented the new tab bar to the bank's design committee, approved without changes."), 3,
             String(localized: "Two million customers will get a calmer app.")),
            (-6, String(localized: "Coaching session: helped Verdi's CTO split the monolith roadmap into 3 deliverable steps."), 5,
             String(localized: "A small team got a plan they believe in.")),
        ]
        for j in journal { context.insert(JournalEntry(date: day(j.0), text: j.1, energy: j.2, impact: j.3)) }

        try? context.save()
    }
}
