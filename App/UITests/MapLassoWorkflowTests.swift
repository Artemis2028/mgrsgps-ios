import XCTest

final class MapLassoWorkflowTests: XCTestCase {
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func begin(_ app: XCUIApplication) {
        let tools = app.buttons["map-measure"]
        XCTAssertTrue(tools.waitForExistence(timeout: 12)); tools.tap()
        let lasso = app.buttons["map-lasso"]
        XCTAssertTrue(lasso.waitForExistence(timeout: 5)); lasso.tap()
        XCTAssertTrue(app.buttons["lasso-select-visible"].waitForExistence(timeout: 5))
    }
    private func selectLoop(_ app: XCUIApplication) {
        // Actual taps flow through the native map overlay's recognizer and
        // projection. This is the accessible corner-tap alternative to dragging.
        for point in [CGVector(dx: 0.18,dy: 0.43),.init(dx: 0.58,dy: 0.43),.init(dx: 0.58,dy: 0.60),.init(dx: 0.18,dy: 0.60)] {
            app.coordinate(withNormalizedOffset: point).tap()
        }
        XCTAssertTrue(app.buttons["lasso-select-loop"].isEnabled,app.debugDescription)
        app.buttons["lasso-select-loop"].tap()
        XCTAssertGreaterThanOrEqual(app.buttons["lasso-hide"].frame.height,44)
        let summary = app.staticTexts["lasso-summary"]
        let selected = NSPredicate(format: "label == %@","Lasso · 2 waypoints · 1 graphic")
        expectation(for: selected,evaluatedWith: summary)
        waitForExpectations(timeout: 5)
    }
    private func run(night: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-uiTestLasso","-startTab","map"]
        if night { app.launchArguments.append("-uiTestLassoNight") }
        app.launch(); begin(app); selectLoop(app)
        capture(night ? "lasso-selection-night" : "lasso-selection-day")
        if night {
            app.buttons["lasso-delete"].tap()
            capture("lasso-confirm-delete-night")
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 4)); app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["lasso-hide"].waitForExistence(timeout: 4))
            app.buttons["lasso-delete"].tap()
            app.buttons["Delete selected"].tap()
        } else { app.buttons["lasso-hide"].tap() }
        XCTAssertTrue(app.staticTexts["lasso-summary"].waitForNonExistence(timeout: 8))
        begin(app); app.buttons["lasso-select-visible"].tap()
        let summary = app.staticTexts["lasso-summary"]
        expectation(for: NSPredicate(format: "label == %@","Lasso · 0 waypoints · 0 graphics"),evaluatedWith: summary)
        waitForExpectations(timeout: 5)
        capture(night ? "lasso-deleted-night" : "lasso-hidden-day")
        app.buttons["lasso-close"].tap()
        // Starting a new draw mode ends lasso and restores map interaction.
        begin(app); app.buttons["map-graphics"].tap()
        // Opening the chooser is safe; choosing a graphic performs the mode switch.
        let choose = app.buttons["choose-graphic-type"]
        XCTAssertTrue(choose.waitForExistence(timeout: 4)); choose.tap()
        let phase = app.buttons["draw-graphic-phase_line"]
        XCTAssertTrue(phase.waitForExistence(timeout: 4)); phase.tap()
        XCTAssertTrue(app.staticTexts["lasso-summary"].waitForNonExistence(timeout: 4))
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        begin(app); app.buttons["lasso-select-visible"].tap()
        expectation(for: NSPredicate(format: "label == %@","Lasso · 0 waypoints · 0 graphics"),evaluatedWith: app.staticTexts["lasso-summary"])
        waitForExpectations(timeout: 5)
    }
    func testLoopHideAndRelaunchInDay() { run(night: false) }
    func testLoopConfirmedDeleteAndRelaunchAtNight() { run(night: true) }
}
