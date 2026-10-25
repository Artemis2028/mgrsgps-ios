import XCTest

final class ProjectionWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestTerrainNoData","-uiTestBoundaryMap","-startTab","waypoints"]; app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if element.exists && element.frame.midY < 150 { app.swipeDown() } else { app.swipeUp() }
        }
    }
    private func field(_ id: String,_ value: String) {
        let input = app.textFields[id]; reveal(input)
        replaceTextInput(input,value)
        XCTAssertEqual(input.value as? String,value)
        let done = app.buttons["waypoint-keyboard-done"]; XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
    }
    private func project() {
        let method = app.segmentedControls["waypoint-position-method"]
        reveal(method); XCTAssertTrue(method.waitForExistence(timeout: 5)); tapNativeMenuItem(method.buttons["Project"])
        tapNativeMenuItem(app.buttons["projection-base"])
        tapNativeMenuItem(app.buttons["projection-base-West observer"].firstMatch)
        let base = app.buttons["projection-base"]
        let selected = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in base.label.contains("West observer") },object:base)
        XCTAssertEqual(XCTWaiter.wait(for:[selected],timeout:5),.completed,app.debugDescription)
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testProjectFromSavedPointSavesAndKeepsFullCoordinateAfterEditAndRelaunch() {
        app.buttons["add-waypoint"].tap(); field("waypoint-name","Projected Alpha")
        project(); field("projection-azimuth","90"); field("projection-distance","1000")
        let preview = app.staticTexts["waypoint-coordinate-preview"]; reveal(preview); XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let grid = preview.label; XCTAssertTrue(grid.hasPrefix("40R BN")); XCTAssertNotEqual(grid,"40R BN 34124 07001")
        capture("waypoint-projection-preview")
        app.buttons["waypoint-save"].tap()
        let edit = app.buttons["edit-waypoint-Projected Alpha"]; XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        reveal(preview); XCTAssertTrue(preview.waitForExistence(timeout: 5)); XCTAssertEqual(preview.label,grid)
        app.buttons["waypoint-save"].tap()
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(edit.waitForExistence(timeout: 8)); edit.tap(); reveal(preview); XCTAssertEqual(preview.label,grid)
        capture("projected-waypoint-reloaded")
    }
    func testInvalidProjectionDisablesSaveAndCoordinateModeKeepsOriginalInNightMode() {
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        // The padded summary must open the editor even when touched off-glyph.
        app.buttons["edit-waypoint-West observer"].coordinate(withNormalizedOffset: .init(dx: 0.95,dy: 0.9)).tap()
        let preview = app.staticTexts["waypoint-coordinate-preview"]; reveal(preview); let original = preview.label
        project(); field("projection-azimuth","90"); field("projection-distance","200001")
        let error = app.staticTexts["projection-error"]; reveal(error); XCTAssertTrue(error.label.contains("200,000"))
        XCTAssertFalse(app.buttons["waypoint-save"].isEnabled); capture("waypoint-projection-night-invalid")
        field("projection-distance","1000")
        reveal(preview); XCTAssertTrue(preview.waitForExistence(timeout: 5)); XCTAssertNotEqual(preview.label,original)
        XCTAssertTrue(app.buttons["waypoint-save"].isEnabled); capture("waypoint-projection-night-valid")
        reveal(app.segmentedControls["waypoint-position-method"])
        tapNativeMenuItem(app.segmentedControls["waypoint-position-method"].buttons["Coordinate"])
        reveal(preview); XCTAssertEqual(preview.label,original); XCTAssertTrue(app.buttons["waypoint-save"].isEnabled)
        app.buttons["waypoint-save"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-West observer"].waitForExistence(timeout: 5))
    }
}
