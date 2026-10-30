import XCTest

final class FieldReadRecoveryWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func gone(_ element: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:element)],timeout:15),.completed)
    }
    private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<24 {
            let top = app.navigationBars["Routes & tracks"].exists ? app.navigationBars["Routes & tracks"].frame.maxY + 8 : app.windows.firstMatch.frame.minY + 65
            let bottom = app.windows.firstMatch.frame.maxY - (app.navigationBars["Routes & tracks"].exists ? 35 : 105)
            if element.exists,element.isHittable,element.frame.minY >= top,element.frame.maxY <= bottom { return }
            let middle = (top + bottom) / 2
            let shift = element.exists ? min(140,max(-140,middle-element.frame.midY)) : -140
            let start = app.coordinate(withNormalizedOffset:.zero).withOffset(.init(dx:app.windows.firstMatch.frame.midX,dy:middle))
            start.press(forDuration:0.1,thenDragTo:start.withOffset(.init(dx:0,dy:shift)),withVelocity:.slow,thenHoldForDuration:0.2)
        }
        XCTFail("Library control is not fully visible: " + app.debugDescription)
    }
    private func run(night: Bool,inModal: Bool,largeText: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestFieldReadRecovery","-uiTestDeferredFieldLoad","-uiTestBoundaryMap","-startTab","waypoints"]
        if night { app.launchArguments.append("-uiTestFieldReadRecoveryNight") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let primaryError = app.staticTexts["field-data-read-error"]
        XCTAssertTrue(primaryError.waitForExistence(timeout:20),app.debugDescription)
        XCTAssertFalse(app.staticTexts["No waypoints yet"].exists,"Unreadable saved data is not an empty library")
        if largeText { capture("largest-library-heading"); reveal(app.buttons["field-data-retry"],in:app) }
        if inModal {
            if largeText { reveal(app.buttons["open-field-library"],in:app) }
            tapNativeMenuItem(app.buttons["open-field-library"],revealing:app.buttons["field-library-retry"])
        }
        let prefix = inModal ? "field-library" : "field-data"
        let warning = app.staticTexts[prefix + "-read-error"]
        let retry = app.buttons[prefix + "-retry"]
        XCTAssertTrue(warning.waitForExistence(timeout:10)); XCTAssertTrue(retry.isHittable)
        capture(night ? "field-read-failure-night" : "field-read-failure-day")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(retry.frame.minY,window.minY)
        XCTAssertLessThanOrEqual(retry.frame.maxY,window.maxY)
        XCTAssertGreaterThan(retry.frame.width,44)
        tapNativeMenuItem(retry)
        XCTAssertTrue(warning.waitForExistence(timeout:15)); XCTAssertTrue(retry.waitForExistence(timeout:15))
        XCTAssertFalse(app.buttons["route-Recovered CAFÉ route"].exists)
        if largeText { reveal(app.buttons[prefix + "-test-repair"],in:app) }
        tapNativeMenuItem(app.buttons[prefix + "-test-repair"])
        let repaired = app.staticTexts[prefix + "-test-repair-status"]
        XCTAssertTrue(repaired.waitForExistence(timeout:5)); XCTAssertEqual(repaired.label,"Synthetic source repaired")
        XCTAssertTrue(warning.exists,"Repairing source alone must not publish a library")
        if largeText { reveal(retry,in:app) }
        tapNativeMenuItem(retry); gone(warning)
        if !inModal {
            if largeText { reveal(app.buttons["library-graphic-Recovered CAFÉ route"],in:app) }
            XCTAssertTrue(app.buttons["library-graphic-Recovered CAFÉ route"].waitForExistence(timeout:15))
            if largeText { reveal(app.buttons["open-field-library"],in:app) }
            tapNativeMenuItem(app.buttons["open-field-library"],revealing:app.buttons["route-Recovered CAFÉ route"])
        }
        let route = app.buttons["route-Recovered CAFÉ route"],track = app.buttons["track-Recovered patrol"]
        XCTAssertTrue(route.waitForExistence(timeout:15))
        if largeText { reveal(track,in:app) }
        XCTAssertTrue(track.waitForExistence(timeout:10))
        capture(night ? "field-read-recovered-night" : "field-read-recovered-day")
        tapNativeMenuItem(track)
        XCTAssertTrue(app.staticTexts["2 points"].waitForExistence(timeout:10),"The original point log must remain readable")
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        XCTAssertTrue(app.buttons["open-field-library"].waitForExistence(timeout:20))
        XCTAssertFalse(primaryError.exists)
        if largeText { reveal(app.buttons["open-field-library"],in:app) }
        tapNativeMenuItem(app.buttons["open-field-library"],revealing:route)
        XCTAssertTrue(route.waitForExistence(timeout:10))
        if largeText { reveal(track,in:app) }
        XCTAssertTrue(track.waitForExistence(timeout:10))
    }
    func testEmptyLibraryFailureAndExplicitRetryRecoverRoutesAndTrackInDay() { run(night:false,inModal:false) }
    func testModalFailureAndExplicitRetryRecoverRoutesAndTrackAtNight() { run(night:true,inModal:true) }
    func testLargestTextRetainsEmptyLibraryRecoveryAndSavedTrackAccess() { run(night:false,inModal:false,largeText:true) }
    func testLargestTextRetainsModalRecoveryAndSavedTrackAccessAtNight() { run(night:true,inModal:true,largeText:true) }
}
