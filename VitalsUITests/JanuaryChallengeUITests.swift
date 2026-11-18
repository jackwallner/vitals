import XCTest

/// The New Year Goal Challenge, the in-app event behind the App Store event
/// card: the Today row, the sheet in each phase, and the
/// `totalcalories://challenge` link. `-challengeNow` sets the date it reads.
final class JanuaryChallengeUITests: XCTestCase {
    private let title = "New Year Goal Challenge"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "dashboard"
        app.launchArguments += args
        app.launch()
        return app
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test1RowOpensTheSheetAndDoneClosesIt() {
        let app = launch(["-challengeNow", "2027-01-12"])
        let row = app.buttons["januaryChallengeRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        keep(app, "01-today-row")
        row.tap()
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["of 31 goal days"].waitForExistence(timeout: 15))
        keep(app, "02-sheet-active")
        bar.buttons["Done"].tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 10))
    }

    func test2TheEventLinkOpensTheSheet() throws {
        let app = launch(["-challengeNow", "2027-01-12"])
        XCTAssertTrue(app.buttons["januaryChallengeRow"].waitForExistence(timeout: 60))
        app.open(try XCTUnwrap(URL(string: "totalcalories://challenge")))
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
        keep(app, "03-sheet-from-link")
    }

    func test3BeforeItStartsTheSheetShowsTheStartDate() {
        let app = launch(["-challengeNow", "2026-12-20", "-openChallenge"])
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["January 1"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["of 31 goal days"].exists)
        keep(app, "04-sheet-upcoming")
    }

    func test4BeforeDecemberEighteenthTodayHasNoRow() {
        let app = launch(["-challengeNow", "2026-12-01"])
        XCTAssertTrue(app.descendants(matching: .any)["today-date"].waitForExistence(timeout: 60))
        sleep(3)
        XCTAssertFalse(app.buttons["januaryChallengeRow"].exists)
    }

    func test5AfterItIsPutAwayTheLinkOpensTodayOnly() throws {
        let app = launch(["-challengeNow", "2027-02-20"])
        XCTAssertTrue(app.descendants(matching: .any)["today-date"].waitForExistence(timeout: 60))
        app.open(try XCTUnwrap(URL(string: "totalcalories://challenge")))
        XCTAssertFalse(app.navigationBars[title].waitForExistence(timeout: 5))
    }
}
