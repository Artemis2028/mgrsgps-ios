import XCTest

final class GridNamingWorkflowTests: XCTestCase {
    func testUSNGNamePersistsAndLabelledEntrySavesWithoutChangingGrid() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting","-startTab","position","-startFace","glance"]; app.launch()
        app.buttons["Settings"].tap()
        let names = app.segmentedControls["grid-system"]
        for _ in 0..<6 { if names.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(names.waitForExistence(timeout: 5)); names.buttons["USNG"].tap()
        let settingsShot = XCTAttachment(screenshot: app.screenshot()); settingsShot.name = "usng-settings"; settingsShot.lifetime = .keepAlways; add(settingsShot)
        app.navigationBars.buttons["Done"].tap()
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["add-waypoint"].tap()
        let name = app.textFields["waypoint-name"]; name.tap(); name.typeText("USNG Alpha")
        let grid = app.textFields["waypoint-mgrs"]; grid.tap(); grid.typeKey("a",modifierFlags: .command); grid.typeText("USNG: 40R BN 3412 0700")
        app.buttons["waypoint-keyboard-done"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["USNG"].exists)
        XCTAssertTrue(app.buttons["waypoint-save"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "usng-labelled-coordinate"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["waypoint-save"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-USNG Alpha"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["edit-waypoint-USNG Alpha"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["USNG"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textFields["waypoint-mgrs"].value as? String ?? "").hasPrefix("40R BN 341"))
    }
}
