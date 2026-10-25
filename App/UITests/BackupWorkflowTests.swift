import XCTest

final class BackupWorkflowTests: XCTestCase {
    func testNativeBackupExportDeleteRestoreAndRelaunchInNightMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","waypoints"]
        app.launch()
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        let actions = app.buttons["Waypoint actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        tapNativeMenuItem(app.buttons["Export"])
        tapNativeMenuItem(app.buttons["Export backup"])
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 15),app.debugDescription)
        let name = "gridfix-backup-ui-"+UUID().uuidString.prefix(8)
        replaceTextInput(filename,String(name)); saveNativeFile(in: app)
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        app.buttons["Recon"].tap()
        app.buttons["library-select-button"].tap(); app.buttons["library-select-all"].tap()
        XCTAssertEqual(app.staticTexts["library-selected-count"].label,"3 selected")
        app.buttons["Selected item actions"].tap(); tapNativeMenuItem(app.buttons["library-delete-selected"])
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); tapNativeMenuItem(confirmation.buttons["Delete"])
        XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].waitForExistence(timeout: 5))
        actions.tap(); tapNativeMenuItem(app.buttons["Import backup"])
        let recents = app.tabBars["DOC.browsingModeTabBar"].buttons["Recents"]
        XCTAssertTrue(recents.waitForExistence(timeout: 10),app.debugDescription); recents.tap()
        capture("backup-picker-recents",app)
        openSavedNativeFile(String(name),in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","Restored"),object: app.staticTexts["library-status"])
        XCTAssertEqual(XCTWaiter.wait(for: [restored],timeout: 15),.completed,app.debugDescription)
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
        capture("backup-restored-night",app)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        app.buttons["Recon"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
        app.buttons["Base"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].waitForExistence(timeout: 5))
        capture("backup-reopened-base",app)
    }
    private func capture(_ name: String,_ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
