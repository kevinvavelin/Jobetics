import Foundation
import Testing
@testable import Jobetics

/// Fixtures mirror the real payload shapes of each provider (checked against live responses).
@Suite("Lead search parsing")
struct LeadSearchTests {
    @Test func parsesRemotive() throws {
        let json = """
        {"00-warning":"…","job-count":1,"jobs":[{"id":1,"url":"https://remotive.com/remote-jobs/software-dev/ios-1",
        "title":"Senior iOS Engineer (Contract)","company_name":"Acme","company_logo":"https://remotive.com/job/1/logo",
        "category":"Software Development","tags":["swift","swiftui"],"job_type":"contract","publication_date":"2026-11-19T14:58:42",
        "candidate_required_location":"Europe","salary":"€550 - €650 / day",
        "description":"<p>Build our <strong>SwiftUI</strong> app.</p><ul><li>Liquid Glass</li><li>Widgets</li></ul>"}]}
        """
        let results = try LeadParsers.remotive(Data(json.utf8))
        let lead = try #require(results.first)
        #expect(lead.title == "Senior iOS Engineer (Contract)")
        #expect(lead.company == "Acme")
        #expect(lead.contract == .freelance)
        #expect(lead.rate == ParsedRate(minCents: 55_000, maxCents: 65_000, currency: "EUR", unit: .day))
        #expect(lead.details.contains("• Liquid Glass"))
        #expect(!lead.details.contains("<"))
        #expect(lead.postedAt != nil)
        #expect(lead.source == .remotive)
    }

    @Test func parsesJobicyWithStructuredSalary() throws {
        let json = """
        {"apiVersion":"2","jobs":[{"id":2,"url":"https://jobicy.com/jobs/2-ios","jobTitle":"iOS Developer &amp; Designer",
        "companyName":"GitLab","companyLogo":"https://jobicy.com/logo.jpg","jobIndustry":["Software Engineering"],
        "jobType":["Full-Time"],"jobGeo":"Canada,  UK","jobExcerpt":"Short","jobDescription":"<p>Long text</p>",
        "pubDate":"2026-11-25T03:20:23+00:00","salaryMin":176000,"salaryMax":242000,"salaryCurrency":"USD","salaryPeriod":"yearly"}]}
        """
        let lead = try #require(try LeadParsers.jobicy(Data(json.utf8)).first)
        #expect(lead.title == "iOS Developer & Designer")
        #expect(lead.contract == .fullTime)
        #expect(lead.rate?.unit == .year)
        #expect(lead.rate?.currency == "USD")
        #expect(lead.rate?.minCents == 17_600_000)
    }

    @Test func parsesHimalayasContractor() throws {
        let json = """
        {"comments":"…","jobs":[{"title":"SwiftUI Contractor","excerpt":"Remote contract","companyName":"Xperteez",
        "companyLogo":"https://cdn.himalayas.app/logo","employmentType":"Contractor","minSalary":60,"maxSalary":80,
        "salaryPeriod":"hourly","currency":"EUR","locationRestrictions":["France","Spain"],"categories":["iOS-Developer"],
        "description":"<p>Hello</p>","pubDate":1795600453,"guid":"https://himalayas.app/companies/x/jobs/swiftui"}]}
        """
        let lead = try #require(try LeadParsers.himalayas(Data(json.utf8)).first)
        #expect(lead.contract == .freelance)
        #expect(lead.location == "France, Spain")
        #expect(lead.rate == ParsedRate(minCents: 6_000, maxCents: 8_000, currency: "EUR", unit: .hour))
        #expect(lead.rate?.dailyCents == 49_000)
        #expect(lead.tags == ["iOS Developer"])
    }

    @Test func parsesWebSearchResults() throws {
        let brave = """
        {"web":{"results":[{"title":"Développeur iOS freelance – Banque Lyon | Malt","url":"https://www.malt.fr/projects/123",
        "description":"Mission de 6 mois, TJM 600 €, télétravail partiel","page_age":"2026-11-20T10:00:00"}]}}
        """
        let lead = try #require(try LeadParsers.brave(Data(brave.utf8)).first)
        #expect(lead.title == "Développeur iOS freelance")
        #expect(lead.company == "Banque Lyon")
        #expect(lead.location == "malt.fr")
        #expect(lead.isRemote)
        #expect(lead.contract == .freelance)
        #expect(lead.rate?.minCents == 60_000)
        #expect(lead.rate?.unit == .day)

        let google = """
        {"items":[{"title":"Freelance SwiftUI developer","link":"https://www.free-work.com/fr/job/1","snippet":"Contract, 550€/jour"}]}
        """
        let g = try #require(try LeadParsers.google(Data(google.utf8)).first)
        #expect(g.source == .google)
        #expect(g.rate == ParsedRate(minCents: 55_000, currency: "EUR", unit: .day))
    }

    @Test func emptyOrMissingListsDoNotThrow() throws {
        #expect(try LeadParsers.jobicy(Data(#"{"success":true}"#.utf8)).isEmpty)
        #expect(try LeadParsers.google(Data(#"{"kind":"customsearch#search"}"#.utf8)).isEmpty)
        #expect(try LeadParsers.brave(Data("{}".utf8)).isEmpty)
    }
}

@Suite("Rate extraction & text")
struct RateExtractionTests {
    @Test(arguments: [
        ("€500/day", ParsedRate(minCents: 50_000, currency: "EUR", unit: .day)),
        ("TJM : 650", ParsedRate(minCents: 65_000, currency: "EUR", unit: .day)),
        ("550 € par jour", ParsedRate(minCents: 55_000, currency: "EUR", unit: .day)),
        ("$80-100/hour", ParsedRate(minCents: 8_000, maxCents: 10_000, currency: "USD", unit: .hour)),
        ("60k€/an", ParsedRate(minCents: 6_000_000, currency: "EUR", unit: .year)),
    ])
    func extractsRates(text: String, expected: ParsedRate) {
        #expect(RateExtractor.parse(text) == expected)
    }

    @Test func ignoresNumbersThatAreNotRates() {
        #expect(RateExtractor.parse("We have 200 employees and 3 offices") == nil)
        #expect(RateExtractor.parse("5 days a week") == nil)
    }

    @Test func htmlBecomesReadableText() {
        let text = HTMLText.plain("<style>p{}</style><h2>Role</h2><p>Build &amp; ship&nbsp;apps.</p><ul><li>Swift</li><li>Café &#233;</li></ul><script>x()</script>")
        #expect(text == "Role\n\nBuild & ship apps.\n\n• Swift\n• Café é", "got: \(text)")
        #expect(!text.contains("x()"))
    }

    @Test func rankingPrefersFreelanceMatchesAndRemovesDuplicates() {
        let base = LeadResult(title: "iOS dev", company: "A", location: "", isRemote: true, contract: .fullTime, rate: nil, tags: [],
                              postedAt: .now, summary: "", details: "", url: URL(string: "https://a.example/1")!, logoURL: nil, source: .remotive)
        var freelance = base
        freelance.title = "SwiftUI freelance"
        freelance.contract = .freelance
        freelance.url = URL(string: "https://a.example/2")!
        var duplicate = base
        duplicate.url = URL(string: "https://b.example/1")!
        duplicate.source = .jobicy

        let ranked = LeadRanking.rank([base, duplicate, freelance], skills: ["SwiftUI"], freelanceOnly: false)
        #expect(ranked.count == 2)
        #expect(ranked.first?.title == "SwiftUI freelance")
        #expect(LeadRanking.rank([base, freelance], skills: [], freelanceOnly: true).map(\.title) == ["SwiftUI freelance"])
    }

    @Test func requestsSendOnlyTheQuery() throws {
        let config = LeadSearchConfiguration(enabled: [.remotive, .brave], braveKey: "k", googleKey: nil, googleEngineID: nil)
        let remotive = try #require(LeadSearchService.request(for: .remotive, query: "swift ui", freelanceOnly: true, configuration: config))
        #expect(remotive.url?.absoluteString == "https://remotive.com/api/remote-jobs?search=swift%20ui&limit=30")
        let brave = try #require(LeadSearchService.request(for: .brave, query: "swift", freelanceOnly: true, configuration: config))
        #expect(brave.value(forHTTPHeaderField: "X-Subscription-Token") == "k")
        #expect(brave.url?.query()?.contains("malt.fr") == true)
    }
}
