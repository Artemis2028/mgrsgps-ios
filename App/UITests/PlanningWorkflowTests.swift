import XCTest

final class PlanningWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestTerrainNoData","-uiTestBoundaryMap","-startTab","map"]; app.launch()
    }
    private func open(_ id: String,_ title: String) {
        let menu = mapTool(app, "map-measure"); XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        tapNativeMenuItem(app.buttons[id]); XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8),app.debugDescription)
    }
    private func reveal(_ element: XCUIElement) { for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() } }
    private func top() {
        // Stop as soon as the controls are reachable. Whole-app overscroll
        // at the top dismisses the native worksheet instead of scrolling it.
        let previous = app.buttons["planning-prev"]
        let form = app.tables.firstMatch
        for _ in 0..<6 { if previous.isHittable { return }; form.swipeDown() }
        XCTAssertTrue(previous.isHittable,app.debugDescription)
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testSunMoonDateNavigationLocalZuluAndDeclinationDiagram() {
        open("field-sunmoon","Sun & moon")
        let day = app.staticTexts["planning-day"]; reveal(day); XCTAssertTrue(day.waitForExistence(timeout: 8))
        let today = day.label
        XCTAssertTrue(app.staticTexts["sunmoon-sunrise-zulu"].label.hasSuffix("Z")); capture("sun-moon-day")
        top(); app.buttons["planning-prev"].tap(); reveal(day); XCTAssertNotEqual(day.label,today)
        top(); app.buttons["planning-next"].tap(); reveal(day); XCTAssertEqual(day.label,today)
        top(); app.buttons["planning-next"].tap(); reveal(day); XCTAssertNotEqual(day.label,today)
        top(); app.buttons["planning-today"].tap(); reveal(day); XCTAssertEqual(day.label,today)
        let moon = app.staticTexts["moon-phase"]; reveal(moon); XCTAssertTrue(moon.waitForExistence(timeout: 5)); XCTAssertTrue(moon.label.contains("illumination")); capture("moon-planning-times")
        app.navigationBars["Sun & moon"].buttons["Close"].tap()
        open("field-declination","Declination")
        XCTAssertTrue(app.staticTexts["declination-magnetic"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["declination-magnetic"].label,"Unavailable")
        XCTAssertNotEqual(app.staticTexts["declination-grid-magnetic"].label,"Unavailable"); capture("declination-diagram-day")
        app.navigationBars["Declination"].buttons["Close"].tap()
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists); XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
        open("field-course","Practice course")
        XCTAssertTrue(app.buttons["practice-start"].waitForExistence(timeout: 5)); capture("map-tools-practice-setup")
        app.navigationBars["Practice course"].buttons["Close"].tap()
        open("field-los","Terrain visibility")
        app.navigationBars["Terrain visibility"].buttons["Done"].tap()
    }
    func testNightPlanningTimesAndDiagramStayReadable() {
        mapTool(app, "Toggle map night mode").tap(); open("field-sunmoon","Sun & moon")
        let dusk = app.staticTexts["sunmoon-eent-zulu"]; reveal(dusk); XCTAssertTrue(dusk.waitForExistence(timeout: 5)); capture("sun-moon-night")
        app.navigationBars["Sun & moon"].buttons["Close"].tap(); open("field-declination","Declination")
        XCTAssertTrue(app.staticTexts["declination-source"].waitForExistence(timeout: 5)); capture("declination-diagram-night")
        app.navigationBars["Declination"].buttons["Close"].tap()
    }
}
