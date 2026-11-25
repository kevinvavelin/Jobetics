import Foundation
import SwiftData
import Testing
@testable import Jobetics

@Suite("Daily rate calculator")
struct RateCalculatorTests {
    @Test func billableDaysRemoveHolidaysAndNonBillableTime() {
        let inputs = RateInputs(targetNetCents: 4_800_000, contributionRate: 0.261, vacationDays: 25, publicHolidays: 11, nonBillableDaysPerMonth: 2)
        #expect(RateCalculator.billableDays(inputs) == 200)
    }

    @Test func recommendsADeterministicRoundedRate() {
        let inputs = RateInputs(targetNetCents: 4_800_000, contributionRate: 0.261, vacationDays: 25, publicHolidays: 11, nonBillableDaysPerMonth: 2)
        let result = RateCalculator.recommend(inputs)
        // 48 000 € / (1 − 26.1 %) / 200 days = 324.76 € → rounded up to the next 5 €.
        #expect(result.dailyRateCents == 32_500)
        #expect(result.hourlyRateCents == 4_643)
        #expect(result.dailyRateCents % 500 == 0)
        #expect(result.netPerDayCents >= 4_800_000 / 200)
    }

    @Test func costsAndIncomeTaxRaiseTheRate() {
        let base = RateInputs(targetNetCents: 4_800_000, contributionRate: 0.261)
        var withCosts = base
        withCosts.yearlyCostsCents = 500_000
        withCosts.incomeTaxRate = 0.022
        #expect(RateCalculator.recommend(withCosts).dailyRateCents > RateCalculator.recommend(base).dailyRateCents)
    }

    @Test func noBillableDaysDoesNotCrash() {
        let inputs = RateInputs(vacationDays: 300)
        #expect(RateCalculator.recommend(inputs).dailyRateCents == 0)
    }

    @Test func fixedPriceEffectiveRate() {
        #expect(RateCalculator.effectiveDailyRate(priceCents: 240_000, daysWorked: 4) == 60_000)
        #expect(RateCalculator.effectiveDailyRate(priceCents: 240_000, daysWorked: 0) == nil)
    }
}

@Suite("Mileage & travel fees")
struct MileageTests {
    @Test func firstBracketFor5CV() {
        // 20 on-site days × 70 km at 5 CV = 1 400 km × 0.636
        let scale = MileageScales.scale(forHorsepower: 5)
        #expect(scale.yearlyAllowance(km: 1_400) == 890.40)
    }

    @Test func secondBracketAddsTheFixedPart() {
        let scale = MileageScales.scale(forHorsepower: 5)
        #expect(scale.yearlyAllowance(km: 10_000) == 10_000 * 0.357 + 1_395)
    }

    @Test func electricBonusAndClamping() {
        let scale = MileageScales.scale(forHorsepower: 12)
        #expect(scale.horsepower == 7)
        #expect(scale.yearlyAllowance(km: 1_000, electric: true) == (1_000 * 0.697 * 1.2 * 100).rounded() / 100)
    }

    @Test func flatFeePerOnSiteDay() {
        let fees = TravelFees(onSiteDays: 8, oneWayKm: 35, mode: .car, policy: .flatPerDay, flatPerDayCents: 3_000)
        #expect(fees.totalCents == 24_000)
    }

    @Test func actualCostsByCarUseRoundTripKm() {
        let fees = TravelFees(onSiteDays: 2, oneWayKm: 35, mode: .car, policy: .actualCosts, ratePerKm: 0.636)
        #expect(fees.totalKm == 140)
        #expect(fees.totalCents == 8_904)
    }

    @Test func actualCostsByTrainUseTickets() {
        let fees = TravelFees(onSiteDays: 3, oneWayKm: 460, mode: .train, policy: .actualCosts, ticketRoundTripCents: 12_800)
        #expect(fees.totalCents == 38_400)
    }

    @Test func includedTravelAddsNothing() {
        #expect(TravelFees(onSiteDays: 10, oneWayKm: 35, mode: .car, policy: .included, ratePerKm: 0.6).totalCents == 0)
    }
}

@Suite("Invoice numbering")
struct NumberingTests {
    @Test func continuesAfterTheLastIssuedNumber() {
        var numbering = DocumentNumbering()
        numbering.register(existing: "FAC-2026-0041")
        #expect(numbering.peek(prefix: "FAC", year: 2026) == "FAC-2026-0042")
        #expect(numbering.next(prefix: "FAC", year: 2026) == "FAC-2026-0042")
        #expect(numbering.next(prefix: "FAC", year: 2026) == "FAC-2026-0043")
    }

    @Test func restartsEveryYearAndPerPrefix() {
        var numbering = DocumentNumbering()
        numbering.register(existing: "FAC-2026-0041")
        #expect(numbering.next(prefix: "FAC", year: 2027) == "FAC-2027-0001")
        #expect(numbering.next(prefix: "DEV", year: 2026) == "DEV-2026-0001")
    }

    @Test func registeringNeverMovesBackwards() {
        var numbering = DocumentNumbering()
        numbering.register(existing: "FAC-2026-0041")
        numbering.register(existing: "FAC-2026-0007")
        #expect(numbering.peek(prefix: "FAC", year: 2026) == "FAC-2026-0042")
    }
}

@Suite("Taxes, thresholds & penalties")
struct TaxTests {
    @Test func setAsideOnPayment() {
        #expect(TaxMath.setAside(paymentCents: 600_000, contributionRate: 0.261) == 156_600)
        #expect(TaxMath.setAside(paymentCents: 600_000, contributionRate: 0.261, incomeTaxRate: 0.022) == 169_800)
    }

    @Test func thresholdAlertsAt80And95Percent() {
        let limit = 7_770_000
        #expect(ThresholdLevel.level(revenue: 6_000_000, limit: limit) == .ok)
        #expect(ThresholdLevel.level(revenue: 6_300_000, limit: limit) == .approaching)
        #expect(ThresholdLevel.level(revenue: 7_500_000, limit: limit) == .critical)
        #expect(ThresholdLevel.level(revenue: 8_000_000, limit: limit) == .exceeded)
    }

    @Test func latePenaltyIncludesTheFortyEuroIndemnity() {
        // 1 000 € × 12.15 % × 30 / 365 = 9.99 € + 40 €
        #expect(TaxMath.latePenalty(amountCents: 100_000, daysLate: 30, yearlyRate: 0.1215) == 4_999)
        #expect(TaxMath.latePenalty(amountCents: 100_000, daysLate: 0, yearlyRate: 0.1215) == 0)
    }

    @Test func legalMentionsForAVATExemptMicroEntrepreneur() {
        var settings = BusinessSettings()
        settings.siret = "912 345 678 00017"
        let mentions = settings.legalMentions.joined(separator: "\n")
        #expect(mentions.contains("SIRET 912 345 678 00017"))
        #expect(mentions.contains("art. 293 B du CGI"))
        #expect(mentions.contains("40"))
    }
}

@Suite("Activity report & cash flow")
struct ActivityTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func reportKeepsOnlyTheMonthAndSplitsOnSiteDays() {
        let month = calendar.dateInterval(of: .month, for: date(2026, 3, 10))!
        let report = ActivityReport(month: month, entries: [
            ActivityDay(date: date(2026, 3, 2), days: 1, onSite: true),
            ActivityDay(date: date(2026, 3, 3), days: 0.5, onSite: false),
            ActivityDay(date: date(2026, 3, 4), days: 0, onSite: false),
            ActivityDay(date: date(2026, 4, 1), days: 1, onSite: true),
        ])
        #expect(report.entries.count == 2)
        #expect(report.totalDays == 1.5)
        #expect(report.onSiteDays == 1)
        #expect(report.remoteDays == 0.5)
    }

    @Test func cashFlowRunsMonthByMonth() {
        let start = date(2026, 1, 15)
        let points = CashFlow.forecast(start: 100_000, from: start, months: 3,
                                       expected: [(date(2026, 2, 10), 500_000), (date(2026, 1, 1), 50_000)],
                                       monthlyCosts: 200_000, calendar: calendar)
        #expect(points.count == 3)
        #expect(points[0].balanceCents == 100_000 + 50_000 - 200_000)
        #expect(points[1].balanceCents == -50_000 + 500_000 - 200_000)
        #expect(points[2].balanceCents == 250_000 - 200_000)
    }
}

@Suite("Sharing")
struct SharingTests {
    @Test func linkedInPostsNeverExceed500Characters() {
        let long = String(repeating: "Shipped a calmer banking app today. ", count: 40)
        let post = SocialShare.linkedInPost(long, hashtags: ["SwiftUI", "Freelance"])
        #expect(post.count <= 500)
        #expect(post.hasSuffix("#SwiftUI #Freelance"))
        #expect(post.contains("…"))
    }

    @Test func shortPostsAreKeptIntact() {
        #expect(SocialShare.linkedInPost("Hello", hashtags: ["ios"]) == "Hello\n\n#ios")
    }

    @Test func shareURLsAreEncoded() {
        let url = SocialShare.whatsAppURL(text: "Voici mon travail & le lien", phone: "+33 6 12 34 56 78")
        #expect(url?.absoluteString.hasPrefix("https://wa.me/33612345678?text=") == true)
        #expect(url?.absoluteString.contains("&le") == false)
        #expect(SocialShare.linkedInComposeURL(text: "Hi")?.host() == "www.linkedin.com")
    }

    @Test func vCardIsValidAndEscaped() {
        let card = ContactCard(fullName: "Camille Laurent", organization: "Studio; Lyon", email: "hello@camille.studio",
                               phone: "+33 6 12 34 56 78", website: "https://camille.studio")
        let vcard = card.vCard
        #expect(vcard.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0"))
        #expect(vcard.hasSuffix("END:VCARD"))
        #expect(vcard.contains("N:Laurent;Camille;;;"))
        #expect(vcard.contains("ORG:Studio\\; Lyon"))
        #expect(vcard.contains("TEL;TYPE=CELL:+33 6 12 34 56 78"))
    }
}

@Suite("Receipt parsing")
struct ReceiptTests {
    @Test func readsTotalVATDateAndCategory() {
        let receipt = ReceiptScanner.parse(lines: ["SNCF", "TGV INOUI Lyon Part-Dieu", "Date 17/02/2026", "TOTAL TTC 128,00 €", "TVA 10% 11,64"])
        #expect(receipt.merchant == "SNCF")
        #expect(receipt.totalCents == 12_800)
        #expect(receipt.vatCents == 1_164)
        #expect(receipt.suggestedCategory == .transport)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: receipt.date!)
        #expect(components.year == 2026 && components.month == 2 && components.day == 17)
    }

    @Test func amountsWithThousandsSeparators() {
        #expect(ReceiptScanner.amount(in: "Total 1 234,56 €") == 123_456)
        #expect(ReceiptScanner.amount(in: "€12.50") == 1_250)
        #expect(ReceiptScanner.amount(in: "No amount here") == nil)
    }
}

@Suite("Reminders")
struct ReminderPlanTests {
    @Test func warnsBeforeALongMissionEndsWithAnEmptyPipeline() {
        let mission = MissionSnapshot(id: "m1", title: "iOS redesign", endDate: .now.addingTimeInterval(86_400 * 30), isActive: true, isLong: true)
        #expect(ReminderScheduler.plan(missions: [mission], invoices: [], pipelineCount: 0, warningDays: 42).count == 1)
        #expect(ReminderScheduler.plan(missions: [mission], invoices: [], pipelineCount: 2, warningDays: 42).isEmpty)
    }

    @Test func remindsAboutUnpaidInvoicesAtTheNextStep() {
        let invoice = InvoiceSnapshot(number: "FAC-2026-0030", client: "Atlas", dueDate: .now.addingTimeInterval(-86_400 * 3), isUnpaid: true)
        let reminders = ReminderScheduler.plan(missions: [], invoices: [invoice], pipelineCount: 1, warningDays: 42)
        #expect(reminders.count == 1)
        #expect(reminders[0].id.hasSuffix("-15"))
    }
}

@Suite("Missions")
@MainActor
struct MissionModelTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(BusinessSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    @Test func dailyMissionEarningsAndTravel() throws {
        let context = try makeContext()
        let mission = Mission(title: "Refonte", rateCents: 62_000, startDate: .now, endDate: .now.addingTimeInterval(86_400 * 300), location: .hybrid)
        mission.oneWayKm = 35
        mission.travelPolicy = .actualCosts
        context.insert(mission)
        for (i, onSite) in [true, true, false].enumerated() {
            let log = WorkLog(date: .now.addingTimeInterval(Double(-i) * 86_400), days: 1, onSite: onSite)
            log.mission = mission
            context.insert(log)
        }
        let half = WorkLog(date: .now, days: 0.5)
        half.mission = mission
        context.insert(half)

        #expect(mission.daysLogged == 3.5)
        #expect(mission.onSiteDaysLogged == 2)
        #expect(mission.earnedCents == 217_000)
        #expect(mission.isLong)
        #expect(mission.travelFees(onSiteDays: mission.onSiteDaysLogged, ratePerKm: 0.636).totalCents == 8_904)
    }

    @Test func fixedPriceEarningsAreCapped() throws {
        let context = try makeContext()
        let mission = Mission(title: "Audit", billingMode: .fixed, rateCents: 240_000, startDate: .now, endDate: .now)
        mission.estimatedDays = 4
        context.insert(mission)
        for i in 0..<5 {
            let log = WorkLog(date: .now.addingTimeInterval(Double(-i) * 86_400), days: 1)
            log.mission = mission
            context.insert(log)
        }
        #expect(mission.earnedCents == 240_000)
        #expect(mission.effectiveDailyRateCents == 48_000)
        #expect(!mission.isLong)
    }

    @Test func issuedInvoicesCannotBeDeleted() {
        let draft = BillingDocument(kind: .invoice, number: "", clientName: "Acme", dueDate: .now)
        let sent = BillingDocument(kind: .invoice, number: "FAC-2026-0042", clientName: "Acme", dueDate: .now, status: .sent)
        #expect(draft.isDeletable)
        #expect(!sent.isDeletable)
        #expect(draft.displayNumber != "")
    }
}
