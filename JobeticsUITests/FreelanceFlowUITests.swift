import XCTest

/// End-to-end checks of the freelancer's daily flows on demo data.
final class FreelanceFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-screenshots", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-tabs.compact.v1", "home,missions,money,jobs,messages"]
        app.launch()
    }

    @MainActor
    func testMissionDetailShowsTimeTravelAndInvoicing() throws {
        app.tabBars.buttons["Missions"].tap()
        let mission = app.buttons.containing(NSPredicate(format: "label CONTAINS 'iOS app redesign'")).firstMatch
        XCTAssertTrue(mission.waitForExistence(timeout: 5))
        mission.tap()

        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Travel"].exists || app.staticTexts["TRAVEL"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["Create invoice"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Activity report"].exists)
    }

    @MainActor
    func testMoneyShowsSetAsideAndRateCalculator() throws {
        app.tabBars.buttons["Money"].tap()
        XCTAssertTrue(app.staticTexts["To set aside this quarter"].waitForExistence(timeout: 5))
        app.swipeUp()
        let calculator = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Daily rate calculator'")).firstMatch
        XCTAssertTrue(calculator.waitForExistence(timeout: 3))
        calculator.tap()
        XCTAssertTrue(app.staticTexts["per day, excluding VAT"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTodayLogsADayAndOpensProfile() throws {
        let fullDay = app.buttons["Full day"].firstMatch
        XCTAssertTrue(fullDay.waitForExistence(timeout: 5))
        fullDay.tap()

        app.buttons["Profile"].firstMatch.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Tab bar'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'My card'")).firstMatch.exists)
    }

    /// Live network: searches the public job APIs, opens a listing and checks the parsed details.
    @MainActor
    func testFindMissionsShowsParsedListingDetails() throws {
        app.terminate()
        app.launchArguments += ["-tabs.compact.v1", "home,web,missions,money,messages", "-tab", "web", "-leads.query", "swift"]
        app.launch()
        let row = app.descendants(matching: .any)["lead-row"].firstMatch
        guard row.waitForExistence(timeout: 30) else { throw XCTSkip("No network or no listings right now") }
        row.tap()
        let apply = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Apply on'")).firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Contract"].exists)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Save as lead'")).firstMatch.exists)
    }
}
