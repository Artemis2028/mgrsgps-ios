import XCTest

final class PracticeWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["-uiTesting","-uiTestPractice","-startTab","navigate"]+extra
        app.launch()
    }
    private func startFolder(allowCompleted: Bool = false) {
        let open = app.buttons["open-practice"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        tapNativeMenuItem(app.segmentedControls.buttons["From folder"])
        tapNativeMenuItem(app.buttons["practice-folder"])
        tapNativeMenuItem(app.buttons["Drill"])
        let start = app.buttons["practice-start"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 5),.completed,app.debugDescription)
        tapNativeMenuItem(start)
        if allowCompleted {
            // Real simulator fixes keep arriving during native UI interactions.
            // A fast course can finish before XCTest observes its progress row.
            let started = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
                self.app.staticTexts["practice-progress"].exists || self.app.staticTexts["Course complete"].exists
            },object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [started],timeout: 10),.completed,app.debugDescription)
        } else {
            XCTAssertTrue(app.staticTexts["practice-progress"].waitForExistence(timeout: 10),app.debugDescription)
        }
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testFolderCoursePersistsLockAndEndKeepsCheckpoints() {
        launch(["-uiTestPracticeFar"]); startFolder(); capture("practice-active")
        app.buttons["Close"].tap()
        XCTAssertFalse(app.buttons["Choose navigation target"].isEnabled)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.buttons["practice-banner"].waitForExistence(timeout: 10)); app.buttons["practice-banner"].tap()
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 2")
        app.buttons["practice-end"].tap(); app.buttons["End course"].tap()
        XCTAssertTrue(app.buttons["practice-start"].waitForExistence(timeout: 10)); app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Choose navigation target"].isEnabled)
        app.tabBars.buttons["Waypoints"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Alpha checkpoint"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo checkpoint"].exists)
    }
    /// Host feeds the two real simulator locations in a loop; app never injects fixes.
    func testRealLocationsAdvanceCourseAndPublishSummary() {
        launch(); startFolder(allowCompleted: true)
        let result = app.otherElements["practice-result"]
        let predicate = NSPredicate(format: "exists == true")
        let summary = app.staticTexts["Course complete"]
        let wait = XCTNSPredicateExpectation(predicate: predicate,object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [wait],timeout: 75),.completed,app.debugDescription)
        XCTAssertTrue(result.exists || app.staticTexts["2 points · Drill"].exists)
        capture("practice-complete")
        app.buttons["practice-summary-done"].tap()
        app.buttons["open-practice"].tap()
        XCTAssertTrue(app.staticTexts["Practice log"].waitForExistence(timeout: 5))
        capture("practice-history")
    }
    private func failedResultRetry(night: Bool) {
        launch(["-uiTestPracticeHistoryWriteFailure"] + (night ? ["-uiTestPracticeNight"] : []))
        startFolder(allowCompleted: true)
        XCTAssertTrue(app.staticTexts["practice-error"].waitForExistence(timeout: 75),app.debugDescription)
        let retry = app.buttons["practice-retry-result"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); XCTAssertTrue(retry.isEnabled)
        XCTAssertFalse(app.buttons["practice-end"].isEnabled)
        capture(night ? "practice-result-save-error-night" : "practice-result-save-error-day")
        app.buttons["Close"].tap()
        let banner = app.buttons["practice-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5)); XCTAssertTrue(banner.label.contains("Completed run kept"))
        capture(night ? "practice-result-pending-banner-night" : "practice-result-pending-banner-day")
        banner.tap()
        tapNativeMenuItem(app.buttons["practice-repair-result"])
        tapNativeMenuItem(retry)
        XCTAssertTrue(app.staticTexts["Course complete"].waitForExistence(timeout: 15))
        capture(night ? "practice-result-retried-night" : "practice-result-retried-day")
        app.buttons["practice-summary-done"].tap()
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.buttons["open-practice"].waitForExistence(timeout: 10)); app.buttons["open-practice"].tap()
        XCTAssertTrue(app.staticTexts["Practice log"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@","2 points · Drill")).count,1,app.debugDescription)
        capture(night ? "practice-result-history-night" : "practice-result-history-day")
    }
    func testResultFailureRetryAndRelaunchDay() { failedResultRetry(night: false) }
    func testResultFailureRetryAndRelaunchNight() { failedResultRetry(night: true) }
    func testRandomSetupCreatesFiveSeparatedSavedCheckpoints() {
        launch()
        XCTAssertTrue(app.buttons["open-practice"].waitForExistence(timeout: 10)); app.buttons["open-practice"].tap()
        let start = app.buttons["practice-start"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 20),.completed,app.debugDescription)
        capture("practice-random-setup"); start.tap()
        XCTAssertTrue(app.staticTexts["practice-progress"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 5")
        capture("practice-random-progress")
    }
    func testNightCourseFormKeepsProgressAndCoordinatesVisible() {
        launch(["-uiTestPracticeFar","-uiTestPracticeNight"]); startFolder()
        XCTAssertTrue(app.staticTexts["Alpha checkpoint"].exists); capture("practice-night")
    }
}
