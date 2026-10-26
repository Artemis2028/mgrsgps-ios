import XCTest

final class LibrarySearchWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(_ extras: [String] = []) {
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","waypoints"]+extras
        app.launch()
    }
    private func query(_ value: String) {
        let input = app.textFields["library-search"]; XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText(value+"\n")
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testSearchFiltersEverySectionAndSelectAllUsesOnlyCurrentResults() {
        launch(); query("Recon")
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"),app.debugDescription)
        XCTAssertFalse(app.buttons["edit-waypoint-Alpha"].exists)
        capture("library-search-mixed")
        app.buttons["library-select-button"].tap()
        app.buttons["library-select-all"].tap()
        XCTAssertEqual(app.staticTexts["library-selected-count"].label,"3 selected")
        app.buttons["library-selection-done"].tap()
        app.buttons["library-search-clear"].tap()
        query("no-such-coordinate-or-name")
        XCTAssertTrue(app.staticTexts["library-no-matches"].waitForExistence(timeout: 5))
        capture("library-search-empty")
    }
    func testFavouriteSurvivesRelaunchLeadsNameSortAndCanBeRemoved() {
        launch()
        tapNativeMenuItem(app.buttons["Actions for Bravo"])
        tapNativeMenuItem(app.buttons["toggle-favorite-Bravo"])
        tapNativeMenuItem(app.buttons["library-sort"],revealing: app.buttons["Name"]); tapNativeMenuItem(app.buttons["Name"])
        let bravo = app.buttons["edit-waypoint-Bravo"], alpha = app.buttons["edit-waypoint-Alpha"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 5)); XCTAssertLessThan(bravo.frame.minY,alpha.frame.minY)
        capture("library-favourite-first")
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.images["favorite-Bravo"].waitForExistence(timeout: 5))
        tapNativeMenuItem(app.buttons["Actions for Bravo"]); tapNativeMenuItem(app.buttons["toggle-favorite-Bravo"])
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in !self.app.images["favorite-Bravo"].exists },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed],timeout: 10),.completed)
        tapNativeMenuItem(app.buttons["library-sort"],revealing: app.buttons["Name"]); tapNativeMenuItem(app.buttons["Name"])
        let ordered = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            self.app.buttons["edit-waypoint-Alpha"].frame.minY < self.app.buttons["edit-waypoint-Bravo"].frame.minY
        },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ordered],timeout: 10),.completed)
        XCTAssertLessThan(app.buttons["edit-waypoint-Alpha"].frame.minY,app.buttons["edit-waypoint-Bravo"].frame.minY)
    }
    func testNightSearchSortAndClearKeepFieldCardsReadable() {
        launch()
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        query("Alpha"); XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].waitForExistence(timeout: 5))
        capture("library-search-night")
    }
}
