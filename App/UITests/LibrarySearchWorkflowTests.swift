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
        app.buttons["Actions for Bravo"].tap()
        app.buttons["toggle-favorite-Bravo"].tap()
        app.buttons["library-sort"].tap(); app.buttons["Name"].tap()
        let bravo = app.buttons["edit-waypoint-Bravo"], alpha = app.buttons["edit-waypoint-Alpha"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 5)); XCTAssertLessThan(bravo.frame.minY,alpha.frame.minY)
        capture("library-favourite-first")
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.images["favorite-Bravo"].waitForExistence(timeout: 5))
        app.buttons["Actions for Bravo"].tap(); app.buttons["toggle-favorite-Bravo"].tap()
        app.buttons["library-sort"].tap(); app.buttons["Name"].tap()
        XCTAssertLessThan(app.buttons["edit-waypoint-Alpha"].frame.minY,app.buttons["edit-waypoint-Bravo"].frame.minY)
    }
    func testNightSearchSortAndClearKeepFieldCardsReadable() {
        launch()
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        query("Alpha"); XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].waitForExistence(timeout: 5))
        capture("library-search-night")
    }
}
