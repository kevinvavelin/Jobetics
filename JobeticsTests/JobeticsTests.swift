//
//  JobeticsTests.swift
//  JobeticsTests
//

import Foundation
import Testing
@testable import Jobetics

@Suite("LinkGuard")
struct LinkGuardTests {
    private func level(_ string: String) -> LinkGuard.Level { LinkGuard.assess(URL(string: string)!).level }

    @Test func trustedDomainsOpenDirectly() {
        #expect(level("https://www.linkedin.com/in/someone") == .trusted)
        #expect(level("https://github.com/apple/swift") == .trusted)
    }

    @Test func dangerousLinksAreBlocked() {
        #expect(level("javascript:alert(1)") == .blocked)
        #expect(level("https://192.168.0.1/login") == .blocked)
        #expect(level("https://linkedin.com@evil.example/login") == .blocked)
        #expect(level("https://linkedin-security-check.com") == .blocked)
        #expect(level("https://paypa1.com/verify") == .blocked)
    }

    @Test func suspiciousLinksNeedConfirmation() {
        #expect(level("http://example.com") == .caution)
        #expect(level("https://bit.ly/abc") == .caution)
        #expect(level("https://xn--pple-43d.com") == .caution)
        #expect(level("https://free-stuff.zip") == .caution)
        #expect(level("https://unknown-studio.design") == .caution)
    }

    @Test func profileLinksMustMatchTheirSite() {
        #expect((try? LinkGuard.validateProfileLink("linkedin.com/in/me", kind: .linkedin).get()) != nil)
        #expect(LinkGuard.validateProfileLink("https://github.com/me", kind: .linkedin) == .failure(.wrongSite(expected: "linkedin.com")))
        #expect(LinkGuard.validateProfileLink("http://behance.net/me", kind: .behance) == .failure(.notHTTPS))
    }
}

@Suite("ContentGuard")
struct ContentGuardTests {
    @Test func redactsContactDetailsBeforeMutualAcceptance() {
        let (text, redacted) = ContentGuard.redactPersonalData("Mail me at jane@example.com or call +33 6 12 34 56 78")
        #expect(redacted)
        #expect(!text.contains("jane@example.com"))
        #expect(!text.contains("12 34 56 78"))
    }

    @Test func flagsUnpaidAndOffPlatformOffers() {
        let categories = Set(ContentGuard.scan("Free trial project for exposure, payment by gift card").map(\.category))
        #expect(categories.contains(.unpaidWork))
        #expect(categories.contains(.offPlatformPayment))
    }

    @Test func leavesNormalMessagesAlone() {
        #expect(ContentGuard.scan("Thanks! I can deliver the first mockups on Thursday.").isEmpty)
    }
}

@Suite("Jobs")
struct JobValidationTests {
    private func job(budget: Int, title: String = "Design a mobile banking app") -> JobPost {
        JobPost(id: "1", ownerId: "o", title: title, summary: String(repeating: "Detailed brief. ", count: 8), discipline: .design,
                skills: ["Figma"], budget: Money(cents: budget), pricing: .fixed, startDate: .now,
                dueDate: .now.addingTimeInterval(86_400), isRemote: true, status: .pendingReview, createdAt: .now,
                proposalCount: 0, employer: .new, moderation: nil)
    }

    @Test func everyJobMustBePaid() {
        #expect(throws: JobPost.ValidationError.unpaid) { try job(budget: 0).validate() }
        #expect(throws: Never.self) { try job(budget: 150_000).validate() }
    }

    @Test func titleIsRequired() {
        #expect(throws: JobPost.ValidationError.missingTitle) { try job(budget: 100, title: "Hi").validate() }
    }
}

@Suite("ScoreEngine")
struct ScoreEngineTests {
    @Test func reliableFreelancersAreTopRated() {
        let score = ScoreEngine.score(DemoData.myProfile.signals)
        #expect(score.overall >= 85)
        #expect(score.tier == .topRated)
    }

    @Test func newcomersStartFromAFairBaseline() {
        let score = ScoreEngine.score(.newcomer)
        #expect((40...75).contains(score.overall))
        #expect(score.tier != .topRated)
    }

    @Test func slowRepliesLowerResponsiveness() {
        #expect(ScoreEngine.responsiveness(medianMinutes: 15) == 1)
        #expect(ScoreEngine.responsiveness(medianMinutes: 270) == 0.5)
    }
}

@Suite("Focus")
struct FocusTests {
    @Test func longBreakComesEveryFourSessions() {
        let settings = FocusSettings()
        var session = FocusSession(phase: .focus, cycleCount: 3)
        #expect(session.nextPhase(settings: settings) == .longBreak)
        session.cycleCount = 1
        #expect(session.nextPhase(settings: settings) == .shortBreak)
        session.phase = .shortBreak
        #expect(session.nextPhase(settings: settings) == .focus)
    }
}
