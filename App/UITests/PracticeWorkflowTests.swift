import XCTest

final class PracticeWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["-uiTesting","-uiTestPractice","-startTab","navigate"]+extra
        app.launch()
    }
    private func startFolder(allowCompleted: Bool = false,allowFailure: Bool = false) {
        let open = app.buttons["open-practice"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        selectNativeSegment(app.segmentedControls.buttons["From folder"])
        tapNativeMenuItem(app.buttons["practice-folder"])
        tapNativeMenuItem(app.buttons["Drill"])
        let start = app.buttons["practice-start"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 5),.completed,app.debugDescription)
        tapNativeMenuItem(start)
        if allowFailure {
            XCTAssertTrue(app.staticTexts["practice-error"].waitForExistence(timeout: 10),app.debugDescription)
        } else if allowCompleted {
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
        app.terminate(); app.launchArguments += ["-keepUITestData","-uiTestDeferredFieldLoad"]; app.launch()
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
    func testRealCompletionWhileViewingRecordedSplitsRetainsFinalLog() {
        let token = UUID().uuidString
        print("PRACTICE_SPLITS_HOLD \(token)")
        defer { print("PRACTICE_SPLITS_RELEASE \(token)") }
        launch(); startFolder()
        let link = app.buttons["practice-open-active-splits"]
        XCTAssertTrue(link.waitForExistence(timeout:25),app.debugDescription)
        tapNativeMenuItem(link)
        XCTAssertTrue(app.navigationBars["Checkpoint splits"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"practice-split-1").firstMatch.exists)
        capture("practice-live-split-before-completion")
        print("PRACTICE_SPLITS_ADVANCE \(token)")
        let complete = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            let banner = self.app.buttons["practice-banner"]
            return banner.exists && banner.label.contains("Course complete")
        },object:app)
        XCTAssertEqual(XCTWaiter.wait(for:[complete],timeout:40),.completed,app.debugDescription)
        if app.staticTexts["Course complete"].exists { tapNativeMenuItem(app.buttons["practice-open-splits"]) }
        let last = app.descendants(matching:.any).matching(identifier:"practice-split-2").firstMatch
        XCTAssertTrue(last.waitForExistence(timeout:10)); XCTAssertTrue(last.isHittable)
        XCTAssertFalse(app.staticTexts["This course is no longer active."].exists)
        capture("practice-live-split-after-completion")
        tapNativeMenuItem(app.navigationBars.buttons["Practice course"])
        XCTAssertTrue(app.staticTexts["Course complete"].waitForExistence(timeout:10))
        tapNativeMenuItem(app.buttons["practice-summary-done"])
        tapNativeMenuItem(app.buttons["open-practice"])
        XCTAssertTrue(app.staticTexts["Practice log"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","2 points · Drill")).count,1)
    }
    private func failedStartRetry(night: Bool) {
        launch(["-uiTestPracticeFar","-uiTestPracticeProgressWriteFailure"] + (night ? ["-uiTestPracticeNight"] : []))
        startFolder(allowFailure: true)
        XCTAssertTrue(app.buttons["practice-retry-write"].isEnabled); XCTAssertFalse(app.buttons["practice-start"].isEnabled)
        capture(night ? "practice-start-save-error-night" : "practice-start-save-error-day")
        app.buttons["Close"].tap()
        let banner = app.buttons["practice-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5)); XCTAssertTrue(banner.label.contains("Course save needs attention"))
        banner.tap(); tapNativeMenuItem(app.buttons["practice-repair-progress"]); tapNativeMenuItem(app.buttons["practice-retry-write"])
        XCTAssertTrue(app.staticTexts["practice-progress"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 2")
        capture(night ? "practice-start-retried-night" : "practice-start-retried-day")
        app.buttons["Close"].tap(); app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.buttons["practice-banner"].waitForExistence(timeout: 10)); app.buttons["practice-banner"].tap()
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 2")
        XCTAssertTrue(app.staticTexts["Alpha checkpoint"].exists)
        capture(night ? "practice-start-reopened-night" : "practice-start-reopened-day")
    }
    func testFailedStartRetryAndRelaunchDay() { failedStartRetry(night: false) }
    func testFailedStartRetryAndRelaunchNight() { failedStartRetry(night: true) }
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
    private func failedRandomPointsRetry(night: Bool) {
        launch(["-uiTestPracticePointsWriteFailure"] + (night ? ["-uiTestPracticeNight"] : []))
        XCTAssertTrue(app.buttons["open-practice"].waitForExistence(timeout: 10)); app.buttons["open-practice"].tap()
        let start = app.buttons["practice-start"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 20),.completed,app.debugDescription)
        tapNativeMenuItem(start)
        XCTAssertTrue(app.staticTexts["practice-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["practice-error"].label.contains("Checkpoints could not be saved"))
        XCTAssertTrue(app.buttons["practice-retry-write"].isEnabled); XCTAssertFalse(start.isEnabled)
        capture(night ? "practice-points-save-error-night" : "practice-points-save-error-day")
        tapNativeMenuItem(app.navigationBars.buttons["Close"])
        XCTAssertTrue(app.buttons["Choose navigation target"].isEnabled)
        app.buttons["practice-banner"].tap()
        tapNativeMenuItem(app.buttons["practice-repair-points"]); tapNativeMenuItem(app.buttons["practice-retry-write"])
        XCTAssertTrue(app.staticTexts["practice-progress"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 5")
        capture(night ? "practice-points-retried-night" : "practice-points-retried-day")
        tapNativeMenuItem(app.navigationBars.buttons["Close"])
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.buttons["practice-banner"].waitForExistence(timeout: 10)); app.buttons["practice-banner"].tap()
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 5")
        capture(night ? "practice-points-reopened-night" : "practice-points-reopened-day")
        tapNativeMenuItem(app.buttons["practice-end"]); tapNativeMenuItem(app.buttons["End course"])
        XCTAssertTrue(app.buttons["practice-start"].waitForExistence(timeout: 10))
        tapNativeMenuItem(app.navigationBars.buttons["Close"])
        if night { app.buttons["Waypoints"].tap() } else { app.tabBars.buttons["Waypoints"].tap() }
        let search = app.textFields["library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("CP \n")
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("5 waypoints"),app.debugDescription)
        for name in ["CP 1","CP 2","CP 3","CP 4","CP 5"] {
            app.buttons["library-search-clear"].tap(); search.tap(); search.typeText(name+"\n")
            XCTAssertTrue(app.buttons["edit-waypoint-"+name].waitForExistence(timeout: 5),app.debugDescription)
        }
    }
    func testRandomCheckpointWriteFailureRetryAndRelaunchDay() { failedRandomPointsRetry(night: false) }
    func testRandomCheckpointWriteFailureRetryAndRelaunchNight() { failedRandomPointsRetry(night: true) }
    private func failedTargetRetry(night: Bool) {
        launch(["-uiTestPracticeFar","-uiTestPracticeTargetWriteFailure"] + (night ? ["-uiTestPracticeNight"] : []))
        startFolder(allowFailure: true)
        XCTAssertTrue(app.staticTexts["practice-error"].label.contains("Course target could not be saved"))
        XCTAssertTrue(app.buttons["practice-retry-write"].isEnabled)
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 2")
        capture(night ? "practice-target-save-error-night" : "practice-target-save-error-day")
        tapNativeMenuItem(app.navigationBars.buttons["Close"])
        XCTAssertFalse(app.buttons["Choose navigation target"].isEnabled)
        app.buttons["practice-banner"].tap()
        tapNativeMenuItem(app.buttons["practice-repair-points"]); tapNativeMenuItem(app.buttons["practice-retry-write"])
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            !self.app.staticTexts["practice-error"].exists && !self.app.descendants(matching: .any).matching(identifier: "practice-saving-progress").firstMatch.exists
        },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [saved],timeout: 10),.completed,app.debugDescription)
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 2")
        capture(night ? "practice-target-retried-night" : "practice-target-retried-day")
        tapNativeMenuItem(app.navigationBars.buttons["Close"])
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.buttons["practice-banner"].waitForExistence(timeout: 10)); app.buttons["practice-banner"].tap()
        XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP 1 of 2")
        XCTAssertFalse(app.staticTexts["practice-error"].exists)
        capture(night ? "practice-target-reopened-night" : "practice-target-reopened-day")
        tapNativeMenuItem(app.buttons["practice-end"]); tapNativeMenuItem(app.buttons["End course"])
        XCTAssertTrue(app.buttons["practice-start"].waitForExistence(timeout: 10))
        tapNativeMenuItem(app.navigationBars.buttons["Close"])
        XCTAssertTrue(app.buttons["Choose navigation target"].isEnabled)
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons["practice-banner"].exists)
    }
    func testTargetWriteFailureRetryAndRelaunchDay() { failedTargetRetry(night: false) }
    func testTargetWriteFailureRetryAndRelaunchNight() { failedTargetRetry(night: true) }
    func testNightCourseFormKeepsProgressAndCoordinatesVisible() {
        launch(["-uiTestPracticeFar","-uiTestPracticeNight"]); startFolder()
        XCTAssertTrue(app.staticTexts["Alpha checkpoint"].exists); capture("practice-night")
    }
    private func damagedRecovery(night: Bool) {
        launch(["-uiTestPracticeFar","-uiTestPracticeDamage","-uiTestDeferredFieldLoad"]+(night ? ["-uiTestPracticeNight"] : []))
        let open = app.buttons["open-practice"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); tapNativeMenuItem(open)
        let reset = app.buttons["practice-reset-damaged"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10)); XCTAssertTrue(app.staticTexts["practice-error"].exists)
        XCTAssertFalse(app.buttons["practice-start"].exists)
        capture(night ? "practice-damaged-course-night" : "practice-damaged-course-day")
        tapNativeMenuItem(reset)
        let cancel = app.buttons["Keep saved session"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); tapNativeMenuItem(cancel)
        XCTAssertTrue(reset.exists); XCTAssertFalse(app.buttons["practice-start"].exists)
        tapNativeMenuItem(reset); tapNativeMenuItem(app.buttons["Reset course session"])
        XCTAssertTrue(app.buttons["practice-start"].waitForExistence(timeout: 10))
        XCTAssertFalse(reset.exists); XCTAssertFalse(app.staticTexts["practice-error"].exists)
        capture(night ? "practice-reset-course-night" : "practice-reset-course-day")
        tapNativeMenuItem(app.navigationBars.buttons["Close"])
        let target = app.buttons["Choose navigation target"]
        let unlocked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [unlocked],timeout: 10),.completed)
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        XCTAssertTrue(open.waitForExistence(timeout: 10)); tapNativeMenuItem(open)
        XCTAssertTrue(app.buttons["practice-start"].waitForExistence(timeout: 10))
        XCTAssertFalse(reset.exists); XCTAssertFalse(app.staticTexts["practice-error"].exists)
        capture(night ? "practice-reset-relaunched-night" : "practice-reset-relaunched-day")
    }
    func testDamagedCoursePreserveResetCancelAndColdRelaunchDay() { damagedRecovery(night: false) }
    func testDamagedCoursePreserveResetCancelAndColdRelaunchNight() { damagedRecovery(night: true) }

}
