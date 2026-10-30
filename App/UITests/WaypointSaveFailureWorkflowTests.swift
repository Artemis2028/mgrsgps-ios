import XCTest

final class WaypointSaveFailureWorkflowTests: XCTestCase {
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func run(night: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestWaypointWriteFailure", "-startTab", "waypoints"]
        if night { app.launchArguments.append("-uiTestWaypointWriteFailureNight") }
        app.launch()
        let add = app.buttons["add-waypoint"]
        XCTAssertTrue(add.waitForExistence(timeout: 15)); add.tap()
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Durable point")
        dismissFieldKeyboard()
        tapNativeMenuItem(app.segmentedControls.buttons["Lat / Lon"])
        let latitude = app.textFields["waypoint-latitude"], longitude = app.textFields["waypoint-longitude"]
        XCTAssertTrue(latitude.waitForExistence(timeout: 5),app.debugDescription)
        tapTextInput(latitude); latitude.typeText("24.4539"); tapTextInput(longitude); longitude.typeText("54.3773")
        tapNativeMenuItem(app.buttons["waypoint-save"])
        let error = app.staticTexts["waypoint-save-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8),app.debugDescription)
        for _ in 0..<5 { if name.exists && name.isHittable { break }; app.swipeDown() }
        XCTAssertEqual(name.value as? String,"Durable point")
        XCTAssertTrue(app.buttons["waypoint-save"].isEnabled)
        capture(night ? "waypoint-save-failure-night" : "waypoint-save-failure-day")
        let repair = app.buttons["waypoint-repair-test-storage"]
        for _ in 0..<5 { if repair.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(repair.isHittable); tapNativeMenuItem(repair); tapNativeMenuItem(app.buttons["waypoint-save"])
        let edit = app.buttons["edit-waypoint-Durable point"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8),app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "edit-waypoint-Durable point").count,1)
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        XCTAssertTrue(app.buttons["edit-waypoint-Durable point"].waitForExistence(timeout: 8))
        capture(night ? "waypoint-save-retry-night" : "waypoint-save-retry-day")
    }
    func testFailedSaveKeepsDraftAndRetriesDurablyInDay() { run(night: false) }
    func testFailedSaveKeepsDraftAndRetriesDurablyAtNight() { run(night: true) }
}
