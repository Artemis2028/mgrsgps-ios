import XCTest

final class LargeLibraryWorkflowTests: XCTestCase {
    private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<24 {
            let window = app.windows.firstMatch.frame, top = app.windows.firstMatch.frame.minY + 65, bottom = app.windows.firstMatch.frame.maxY - 105
            if element.exists,element.isHittable,element.frame.minY >= top,element.frame.maxY <= bottom { return }
            let middle = (top + bottom) / 2
            let shift = element.exists ? min(150,max(-150,middle-element.frame.midY)) : -150
            let start = app.coordinate(withNormalizedOffset:.zero).withOffset(.init(dx:window.midX,dy:middle))
            start.press(forDuration:0.1,thenDragTo:start.withOffset(.init(dx:0,dy:shift)),withVelocity:.slow,thenHoldForDuration:0.2)
        }
        XCTFail("Library control is not fully visible: " + app.debugDescription)
    }
    private func runLargestCard(night: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLargeLibrary","-uiTestBoundaryMap","-startTab","waypoints",
                               "-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        if night { app.launchArguments.append("-uiTestLargeLibraryNight") }
        app.launch()
        let input = app.textFields["library-search"]
        XCTAssertTrue(input.waitForExistence(timeout:20)); reveal(input,in:app)
        tapNativeMenuItem(input); input.typeText("Point 0000\n")
        let count = app.staticTexts["library-listed-count"]
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","1 waypoints · 0 graphics · 0 tracks"),object:count)],timeout:15),.completed)
        let point = app.buttons["edit-waypoint-Point 0000"]
        reveal(point,in:app)
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); image.name = "largest-waypoint-card"; image.lifetime = .keepAlways; add(image)
        XCTAssertGreaterThan(point.frame.width,app.windows.firstMatch.frame.width * 0.6,"The coordinate summary needs most of the card width, rather than being squeezed between icons and actions")
        let actions = app.buttons["Actions for Point 0000"]
        reveal(actions,in:app)
        XCTAssertGreaterThanOrEqual(actions.frame.width,44); XCTAssertGreaterThanOrEqual(actions.frame.height,44)
        tapNativeMenuItem(actions)
        let edit = app.buttons["edit"]
        XCTAssertTrue(edit.waitForExistence(timeout:8),app.debugDescription); edit.tap()
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout:8)); XCTAssertEqual(name.value as? String,"Point 0000")
        tapNativeMenuItem(app.buttons["Cancel"])
        let navigate = app.buttons["Navigate to Point 0000"]
        reveal(navigate,in:app); tapNativeMenuItem(navigate)
        let target = app.staticTexts["navigation-target-name"]
        XCTAssertTrue(target.waitForExistence(timeout:15)); XCTAssertEqual(target.label,"Point 0000")
    }
    func testLargestTextWaypointGridAndActionsRemainReadable() { runLargestCard(night:false) }
    func testLargestTextWaypointGridAndActionsRemainReadableAtNight() { runLargestCard(night:true) }
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
