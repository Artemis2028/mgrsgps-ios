import XCTest

final class WaypointRecoveryWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func revealChoice(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists, element.isHittable {
                let frame = element.frame
                if frame.minY > app.navigationBars.firstMatch.frame.maxY + 10, frame.midY < app.frame.maxY - 60 { return }
            }
            app.swipeUp()
        }
        XCTFail("Recovery choice is not in the visible list")
    }
    func testActionsShowRecoveryOnHealthyLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestLibrary", "-startTab", "waypoints"]
        app.launch(); tapNativeMenuItem(app.buttons["Waypoint actions"])
        let history = app.buttons["library-waypoint-recovery"]
        revealChoice(history, app: app); tapNativeMenuItem(history)
        XCTAssertTrue(app.staticTexts["waypoint-recovery-available"].waitForExistence(timeout: 8))
    }
    private func run(night: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestWaypointRecovery", "-uiTestDeferredFieldLoad", "-startTab", "waypoints"]
        if night { app.launchArguments.append("-uiTestWaypointRecoveryNight") }
        app.launch()
        let warning = app.staticTexts["waypoint-library-load-error"], recovery = app.buttons["waypoint-library-recovery"]
        XCTAssertTrue(warning.waitForExistence(timeout: 15)); tapNativeMenuItem(recovery)
        let retry = app.buttons["waypoint-recovery-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); tapNativeMenuItem(retry)
        let error = app.staticTexts["waypoint-recovery-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8)); XCTAssertTrue(error.label.contains("Unable to reload"))
        capture(night ? "waypoint-recovery-retry-night" : "waypoint-recovery-retry-day")
        tapNativeMenuItem(app.buttons["waypoint-recovery-preserve"])
        let share = app.buttons.matching(identifier: "waypoint-recovery-share").firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(retry.exists, "Preserving a copy must not clear the unreadable library")
        if !night {
            revealSettingsControl(share, in: app); tapNativeMenuItem(share)
            let save = app.cells["Save to Files"]
            XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription); tapNativeMenuItem(save)
            let filename = app.textFields["DOCPicker.filenameTextField"]
            XCTAssertTrue(filename.waitForExistence(timeout: 10))
            replaceTextInput(filename, "recovery-original-" + String(UUID().uuidString.prefix(8)))
            saveNativeFile(in: app)
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: retry)
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
        }
        let fresh = app.buttons["waypoint-recovery-fresh"]
        revealSettingsControl(fresh, in: app); tapNativeMenuItem(fresh)
        let confirm = app.alerts["Start an empty waypoint library?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); tapNativeMenuItem(confirm.buttons["Cancel"])
        XCTAssertTrue(retry.exists)
        revealSettingsControl(fresh, in: app); tapNativeMenuItem(fresh)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); tapNativeMenuItem(confirm.buttons["Archive and start fresh"])
        XCTAssertTrue(app.staticTexts["waypoint-recovery-available"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "waypoint-recovery-share").count, 1)
        capture(night ? "waypoint-recovery-original-kept-night" : "waypoint-recovery-original-kept-day")
        tapNativeMenuItem(app.buttons["waypoint-recovery-done"])
        XCTAssertFalse(warning.exists)
        tapNativeMenuItem(app.buttons["add-waypoint"])
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); tapTextInput(name); name.typeText("After recovery")
        dismissFieldKeyboard(); selectNativeSegment(app.segmentedControls.buttons["Lat / Lon"])
        let latitude = app.textFields["waypoint-latitude"], longitude = app.textFields["waypoint-longitude"]
        XCTAssertTrue(latitude.waitForExistence(timeout: 5)); tapTextInput(latitude); latitude.typeText("24.4539")
        tapTextInput(longitude); longitude.typeText("54.3773"); tapNativeMenuItem(app.buttons["waypoint-save"])
        let point = app.buttons["edit-waypoint-After recovery"]
        XCTAssertTrue(point.waitForExistence(timeout: 10))
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        XCTAssertTrue(point.waitForExistence(timeout: 15)); XCTAssertFalse(warning.exists)
        tapNativeMenuItem(app.buttons["Waypoint actions"])
        let history = app.buttons["library-waypoint-recovery"]
        revealChoice(history, app: app)
        XCTAssertTrue(history.waitForExistence(timeout: 5)); tapNativeMenuItem(history)
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["waypoint-recovery-available"].exists)
        capture(night ? "waypoint-recovery-relaunched-history-night" : "waypoint-recovery-relaunched-history-day")
    }
    func testPreserveShareCancelRecoverCreateAndRelaunchInDay() { run(night: false) }
    func testPreserveCancelRecoverCreateAndRelaunchAtNight() { run(night: true) }
}
