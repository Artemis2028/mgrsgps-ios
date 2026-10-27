import XCTest

final class PracticeLogWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<24 {
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 8 : app.windows.firstMatch.frame.minY + 60
            let bottom = app.windows.firstMatch.frame.maxY - 35
            if element.exists,element.isHittable,element.frame.minY >= top,element.frame.maxY <= bottom { return }
            let surface = app.collectionViews.allElementsBoundByIndex.last ?? app.scrollViews.firstMatch
            if element.exists,element.frame.midY < top { surface.swipeDown() } else { surface.swipeUp() }
        }
        XCTFail("Saved course control is not fully visible: " + app.debugDescription)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func openLog(_ app: XCUIApplication) {
        let open = app.buttons["open-practice"]
        XCTAssertTrue(open.waitForExistence(timeout:20)); tapNativeMenuItem(open)
        let history = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Long course")).firstMatch
        reveal(history,in:app); tapNativeMenuItem(history)
        let splits = app.buttons["practice-open-splits"]
        reveal(splits,in:app); tapNativeMenuItem(splits)
        XCTAssertTrue(app.navigationBars["Checkpoint splits"].waitForExistence(timeout:10))
    }
    private func run(night: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestPracticeLog","-uiTestBoundaryMap","-startTab","navigate"]
        if night { app.launchArguments += ["-uiTestPracticeLogNight","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); openLog(app)
        let first = app.descendants(matching:.any).matching(identifier:"practice-split-1").firstMatch
        let last = app.descendants(matching:.any).matching(identifier:"practice-split-10000").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout:10)); XCTAssertTrue(first.label.contains("0:01"))
        tapNativeMenuItem(app.buttons["practice-splits-last"])
        XCTAssertTrue(last.waitForExistence(timeout:15)); XCTAssertTrue(last.label.contains("0:01")); XCTAssertTrue(last.isHittable)
        capture(night ? "practice-log-last-largest-night" : "practice-log-last-day")
        tapNativeMenuItem(app.buttons["practice-splits-first"])
        XCTAssertTrue(first.waitForExistence(timeout:15)); XCTAssertTrue(first.isHittable)
        capture(night ? "practice-log-first-largest-night" : "practice-log-first-day")
        app.terminate(); app.launchArguments += ["-keepUITestData","-uiTestDeferredFieldLoad"]; app.launch(); openLog(app)
        tapNativeMenuItem(app.buttons["practice-splits-last"])
        XCTAssertTrue(last.waitForExistence(timeout:15)); XCTAssertTrue(last.label.contains("0:01"))
    }
    func testAllTenThousandSavedSplitsRemainReachableAndSurviveRelaunch() { run(night:false) }
    func testLargestTextNightLogRetainsCompleteSplitsAndJumpControls() { run(night:true) }
    private func activeLog(night: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestPracticeActiveLog","-uiTestBoundaryMap","-startTab","navigate"]
        if night { app.launchArguments += ["-uiTestPracticeLogNight","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        func openActive() {
            let open = app.buttons["open-practice"]
            XCTAssertTrue(open.waitForExistence(timeout:20)); reveal(open,in:app); tapNativeMenuItem(open)
            XCTAssertTrue(app.staticTexts["practice-progress"].waitForExistence(timeout:15))
            XCTAssertEqual(app.staticTexts["practice-progress"].label,"CP \(10_000.formatted()) of \(10_000.formatted())")
            XCTAssertTrue(app.staticTexts["Last checkpoint"].exists)
            let end = app.buttons["practice-end"]
            reveal(end,in:app); XCTAssertTrue(end.isHittable)
            capture(night ? "active-course-controls-largest-night" : "active-course-controls-day")
            let splits = app.buttons["practice-open-active-splits"]
            reveal(splits,in:app); tapNativeMenuItem(splits)
            XCTAssertTrue(app.navigationBars["Checkpoint splits"].waitForExistence(timeout:10))
        }
        app.launch(); openActive()
        let first = app.descendants(matching:.any).matching(identifier:"practice-split-1").firstMatch
        let last = app.descendants(matching:.any).matching(identifier:"practice-split-9999").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout:10)); XCTAssertTrue(first.label.contains("0:01"))
        tapNativeMenuItem(app.buttons["practice-splits-last"])
        XCTAssertTrue(last.waitForExistence(timeout:15)); XCTAssertTrue(last.isHittable); XCTAssertTrue(last.label.contains("0:01"))
        capture(night ? "active-course-last-largest-night" : "active-course-last-day")
        tapNativeMenuItem(app.buttons["practice-splits-first"])
        XCTAssertTrue(first.waitForExistence(timeout:15)); XCTAssertTrue(first.isHittable)
        app.terminate(); app.launchArguments += ["-keepUITestData","-uiTestDeferredFieldLoad"]; app.launch(); openActive()
        tapNativeMenuItem(app.buttons["practice-splits-last"])
        XCTAssertTrue(last.waitForExistence(timeout:15)); XCTAssertTrue(last.label.contains("0:01"))
        tapNativeMenuItem(app.navigationBars.buttons["Practice course"])
        let end = app.buttons["practice-end"]; reveal(end,in:app); tapNativeMenuItem(end)
        tapNativeMenuItem(app.buttons["End course"])
        XCTAssertTrue(app.buttons["practice-start"].waitForExistence(timeout:15))
    }
    func testLongActiveCourseKeepsControlsReachableAndAllRecordedSplits() { activeLog(night:false) }
    func testLongActiveCourseLargestNightPreservesProgressAndControls() { activeLog(night:true) }
}
