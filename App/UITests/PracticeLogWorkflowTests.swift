import XCTest

final class PracticeLogWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func reveal(_ element: XCUIElement,in app: XCUIApplication,searchUp: Bool = false) {
        for _ in 0..<24 {
            let surface = app.collectionViews.allElementsBoundByIndex.last ?? app.scrollViews.firstMatch
            let header = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 8 : app.windows.firstMatch.frame.minY + 60
            let top = max(header,surface.frame.minY)
            let bottom = min(app.windows.firstMatch.frame.maxY - 35,surface.frame.maxY)
            if element.exists,element.isHittable,element.frame.minY >= top,element.frame.maxY <= bottom { return }
            if element.exists,element.frame.height <= bottom-top {
                // Full-screen swipes can oscillate around a tall row at the
                // bottom of a large-text sheet. Move only the missing distance
                // inside the sheet's unobscured viewport, then let it settle.
                let needed = element.frame.minY < top ? top-element.frame.minY+12 : bottom-element.frame.maxY-12
                let limit = (bottom-top)*0.6
                let delta = min(limit,max(-limit,needed))
                // Centre both ends in the content viewport. Starting near
                // the bottom can hit Navigate's floating tab controls instead.
                let startY = (top+bottom)/2-delta/2
                let start = surface.coordinate(withNormalizedOffset:.zero).withOffset(.init(dx:surface.frame.width/2,dy:startY-surface.frame.minY))
                let finish = start.withOffset(.init(dx:0,dy:delta))
                start.press(forDuration:0.1,thenDragTo:finish,withVelocity:.slow,thenHoldForDuration:0.3)
            } else if searchUp { surface.swipeDown() }
            else { surface.swipeUp() }
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
            let grid = app.staticTexts["practice-target-grid"]
            reveal(grid,in:app)
            XCTAssertEqual(grid.label,"18S TD 26201 77156")
            capture(night ? "active-course-grouped-grid-largest-night" : "active-course-grouped-grid-day")
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
        let create = app.staticTexts["Create course"]
        // Ending retains this Form's scroll position. On hosted 26.5 the
        // new form opens at Start, with its Create header virtualized above.
        // Reveal and verify that header before checking Start below it.
        reveal(create,in:app,searchUp:true); XCTAssertTrue(create.exists)
        let start = app.buttons["practice-start"]
        reveal(start,in:app); XCTAssertTrue(start.exists); XCTAssertTrue(start.isHittable)
        capture(night ? "active-course-ended-largest-night" : "active-course-ended-day")
    }
    func testLongActiveCourseKeepsControlsReachableAndAllRecordedSplits() { activeLog(night:false) }
    func testLongActiveCourseLargestNightPreservesProgressAndControls() { activeLog(night:true) }
}
