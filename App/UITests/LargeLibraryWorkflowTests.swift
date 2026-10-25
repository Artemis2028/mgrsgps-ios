import XCTest

final class LargeLibraryWorkflowTests: XCTestCase {
    func testLargeLibrarySearchGridSelectionAndNightCards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLargeLibrary","-uiTestBoundaryMap","-startTab","waypoints"]
        app.launch()
        let count = app.staticTexts["library-listed-count"]
        func counts(_ expected: String) {
            let predicate = NSPredicate(format: "label CONTAINS %@",expected)
            XCTAssertTrue(count.waitForExistence(timeout: 10))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate,object: count)],timeout: 10),.completed,app.debugDescription)
            XCTAssertFalse(app.progressIndicators["library-updating"].exists)
        }
        func query(_ text: String) {
            let clear = app.buttons["library-search-clear"]
            if clear.exists { clear.tap() }
            let input = app.textFields["library-search"]
            XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text+"\n")
        }
        func capture(_ name: String) {
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        }
        counts("5,000 waypoints · 1,000 graphics · 0 tracks")
        XCTAssertTrue(app.buttons["edit-waypoint-Point 4999"].waitForExistence(timeout: 5))
        capture("large-library-favourite-first")
        query("Folder 099"); counts("50 waypoints · 0 graphics · 0 tracks")
        app.buttons["library-select-button"].tap(); app.buttons["library-select-all"].tap()
        XCTAssertEqual(app.staticTexts["library-selected-count"].label,"50 selected")
        query("Route 0999")
        XCTAssertTrue(app.buttons["Select graphic Route 0999"].waitForExistence(timeout: 10))
        app.buttons["library-select-all"].tap()
        XCTAssertEqual(app.staticTexts["library-selected-count"].label,"1 selected")
        app.buttons["library-selection-done"].tap()
        counts("0 waypoints · 1 graphics · 0 tracks")
        query("Point 0000"); counts("1 waypoints · 0 graphics · 0 tracks")
        let point = app.buttons["edit-waypoint-Point 0000"]
        XCTAssertTrue(point.waitForExistence(timeout: 5))
        // Search the exact displayed MGRS, rather than hardcoding a grid fixture.
        let range = point.label.range(of: #"40R [A-Z]{2} [0-9]{5} [0-9]{5}"#,options: .regularExpression)
        XCTAssertNotNil(range,point.debugDescription)
        query(range.map { String(point.label[$0]) } ?? "missing grid"); counts("1 waypoints · 0 graphics · 0 tracks")
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        XCTAssertTrue(point.waitForExistence(timeout: 10))
        capture("large-library-grid-search-night")
    }
}
