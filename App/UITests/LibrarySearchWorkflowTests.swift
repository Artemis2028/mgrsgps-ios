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
    func testWaypointChoicesDismissBeforeEditingNavigatingAndConfirmedDeletion() {
        launch()
        func openChoices() {
            let actions = app.buttons["Actions for Alpha"]
            XCTAssertTrue(actions.waitForExistence(timeout: 8))
            for _ in 0..<5 { if actions.isHittable { break }; app.swipeUp() }
            tapNativeMenuItem(actions,revealing: app.buttons["Edit"])
            XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        }
        openChoices(); capture("waypoint-choices-day")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].waitForExistence(timeout: 5))
        openChoices(); app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["waypoint-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["waypoint-name"].value as? String,"Alpha")
        app.buttons["waypoint-save"].tap()
        openChoices(); app.buttons["Hide on map"].tap()
        XCTAssertTrue(app.images["library-waypoint-hidden-Alpha"].waitForExistence(timeout: 10))
        openChoices(); app.buttons["Make visible on map"].tap()
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in !self.app.images["library-waypoint-hidden-Alpha"].exists },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [shown],timeout: 10),.completed)
        openChoices(); app.buttons["Show on map"].tap()
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@","map-waypoint-","Alpha")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap()
        openChoices(); capture("waypoint-choices-night")
        app.buttons.matching(NSPredicate(format: "identifier == %@","navigate")).element.tap()
        XCTAssertTrue(app.buttons["Choose navigation target"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Alpha"].exists)
        app.buttons["Waypoints"].tap()
        openChoices(); app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].exists)
        openChoices(); app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["Delete"].tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in !self.app.buttons["edit-waypoint-Alpha"].exists },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [deleted],timeout: 10),.completed)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["edit-waypoint-Alpha"].exists)
        capture("waypoint-choice-deletion-relaunched-night")
    }

    func testNightSearchSortAndClearKeepFieldCardsReadable() {
        launch()
        app.tabBars.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap()
        XCTAssertTrue(app.textFields["library-search"].waitForExistence(timeout: 5))
        capture("library-search-placeholder-night")
        query("Alpha"); XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].waitForExistence(timeout: 5))
        capture("library-search-night")
        app.buttons["library-search-clear"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library-search-clear"].exists)
        tapNativeMenuItem(app.buttons["library-sort"],revealing: app.buttons["Name"]); tapNativeMenuItem(app.buttons["Name"])
        let ordered = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            self.app.buttons["library-sort"].label.contains("Name") &&
            self.app.buttons["edit-waypoint-Alpha"].frame.minY < self.app.buttons["edit-waypoint-Bravo"].frame.minY
        },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ordered],timeout: 10),.completed)
        capture("library-search-cleared-and-sorted-night")
        app.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap()
        XCTAssertTrue(app.textFields["library-search"].waitForExistence(timeout: 5))
        capture("library-search-placeholder-day")
    }
}
