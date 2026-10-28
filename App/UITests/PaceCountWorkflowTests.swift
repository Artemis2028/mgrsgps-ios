import XCTest

final class PaceCountWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<24 {
            let top = app.navigationBars.firstMatch.frame.maxY + 8, bottom = app.windows.firstMatch.frame.maxY - 35
            if element.exists,element.isHittable,element.frame.minY >= top,element.frame.maxY <= bottom { return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTFail("Pace control is not fully visible: " + app.debugDescription)
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func run(night: Bool,large: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","position"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); tapNativeMenuItem(app.buttons["Settings"])
        if night { setNativeSwitch(app.switches["Night mode"],to:true) }
        let field = app.textFields["pace-count-input"]
        reveal(field,in:app); tapNativeMenuItem(field); replaceTextInput(field,"100")
        XCTAssertEqual(field.value as? String,"100")
        replaceTextInput(field,"29")
        XCTAssertTrue(app.staticTexts["pace-count-validation"].waitForExistence(timeout:5))
        let keyboardDone = app.buttons["pace-entry-keyboard-done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout:5)); tapNativeMenuItem(keyboardDone)
        reveal(app.staticTexts["pace-count-validation"],in:app)
        XCTAssertTrue(app.staticTexts["pace-count-validation"].label.contains("still use 100"))
        capture(large ? "pace-entry-largest-night-invalid" : (night ? "pace-entry-night-invalid" : "pace-entry-day-invalid"))
        reveal(field,in:app); replaceTextInput(field,"100")
        XCTAssertFalse(app.staticTexts["pace-count-validation"].exists)
        tapNativeMenuItem(app.navigationBars.buttons["Done"])
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        tapNativeMenuItem(app.buttons["Settings"]); reveal(field,in:app)
        XCTAssertEqual(field.value as? String,"100")
        capture(large ? "pace-entry-largest-night-restored" : (night ? "pace-entry-night-restored" : "pace-entry-day-restored"))
        tapNativeMenuItem(app.navigationBars.buttons["Done"])
        if large { return }
        tapNativeMenuItem(app.buttons["Waypoints"])
        tapNativeMenuItem(app.buttons["open-field-library"])
        tapNativeMenuItem(app.buttons["route-Recon route"])
        let pace = app.staticTexts["route-card-pace"]
        reveal(pace,in:app); XCTAssertTrue(pace.label.hasPrefix("Pace 100/100 m"))
        XCTAssertEqual(app.staticTexts["route-card-total"].label,"TOTAL  211 m · 211 paces")
        capture(night ? "pace-route-card-night" : "pace-route-card-day")
    }
    func testTypedPaceRejectsInvalidDraftPersistsAndUpdatesRouteCardInDay() { run(night:false) }
    func testTypedPaceRejectsInvalidDraftPersistsAndUpdatesRouteCardAtNight() { run(night:true) }
    func testLargestNightPaceEntryAndValidationRemainReachable() { run(night:true,large:true) }
}
