import XCTest

final class BackupWorkflowTests: XCTestCase {
    func testNativeBackupExportDeleteRestoreAndRelaunchInNightMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","waypoints"]
        app.launch()
        app.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap()
        drawQuietBoundary(app)
        app.buttons["Waypoints"].tap()
        let actions = app.buttons["Waypoint actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        tapNativeMenuItem(app.buttons["Export"])
        tapNativeMenuItem(app.buttons["Export backup"])
        let filename = app.textFields["export-filename"]
        XCTAssertTrue(filename.waitForExistence(timeout: 15),app.debugDescription)
        let name = "gridfix-backup-ui-"+UUID().uuidString.prefix(8)
        replaceTextInput(filename,String(name)); saveNativeFile(in: app)
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        deleteQuietBoundary(app)
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
        XCTAssertTrue(app.staticTexts["library-status"].label.contains("1 quiet boundary"))
        verifyQuietBoundary(app)
        capture("backup-restored-night",app)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        verifyQuietBoundary(app)
        app.buttons["Recon"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
        app.buttons["Base"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].waitForExistence(timeout: 5))
        capture("backup-reopened-base",app)
    }
    func testProtectedBackupNativeFilesPasswordFailureAndRestoreInNightMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","waypoints"]
        app.launch()
        app.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap()
        drawQuietBoundary(app)
        app.buttons["Waypoints"].tap()
        let actions = app.buttons["Waypoint actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        tapNativeMenuItem(app.buttons["Export"]); tapNativeMenuItem(app.buttons["Export protected backup"])
        let submit = app.buttons["backup-password-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 8)); XCTAssertFalse(submit.isEnabled)
        capture("protected-backup-password-empty-night",app)
        let password = app.secureTextFields["backup-password"], confirmation = app.secureTextFields["backup-password-confirmation"]
        password.tap(); password.typeText("correct horse")
        confirmation.tap(); confirmation.typeText("does not match")
        XCTAssertFalse(submit.isEnabled)
        confirmation.tap(); confirmation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: 14)); confirmation.typeText("correct horse")
        app.buttons["backup-password-keyboard-done"].tap()
        XCTAssertTrue(submit.isEnabled,app.debugDescription)
        capture("protected-backup-password-night",app); submit.tap()
        let filename = app.textFields["export-filename"]
        XCTAssertTrue(filename.waitForExistence(timeout: 20),app.debugDescription)
        capture("protected-backup-native-save",app)
        let name = "gridfix-protected-ui-"+UUID().uuidString.prefix(8)
        // Change the basename as in the ordinary export. Files retains the
        // declared extension; restore also identifies protection by bytes.
        replaceTextInput(filename,String(name)); saveNativeFile(in: app)
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        deleteQuietBoundary(app)
        app.buttons["Recon"].tap(); app.buttons["library-select-button"].tap(); app.buttons["library-select-all"].tap()
        XCTAssertEqual(app.staticTexts["library-selected-count"].label,"3 selected")
        app.buttons["Selected item actions"].tap(); tapNativeMenuItem(app.buttons["library-delete-selected"])
        let deletion = app.alerts.firstMatch
        XCTAssertTrue(deletion.waitForExistence(timeout: 5)); tapNativeMenuItem(deletion.buttons["Delete"])
        XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].waitForExistence(timeout: 5))
        func importFile(_ value: String) {
            actions.tap(); tapNativeMenuItem(app.buttons["Import backup"])
            openSavedNativeFile(String(name),in: app)
            let input = app.secureTextFields["backup-password"]
            XCTAssertTrue(input.waitForExistence(timeout: 15),app.debugDescription)
            input.tap(); input.typeText(value); app.buttons["backup-password-keyboard-done"].tap()
            app.buttons["backup-password-submit"].tap()
        }
        importFile("wrong password")
        let status = app.staticTexts["library-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@","Nothing was restored"),object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [failed],timeout: 15),.completed,app.debugDescription)
        XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].exists)
        capture("protected-backup-wrong-password-night",app)
        importFile("correct horse")
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","Restored"),object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [restored],timeout: 15),.completed,app.debugDescription)
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
        XCTAssertTrue(status.label.contains("1 quiet boundary"))
        verifyQuietBoundary(app)
        capture("protected-backup-restored-night",app)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        verifyQuietBoundary(app)
        app.buttons["Recon"].tap(); XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
    }
    private func drawQuietBoundary(_ app: XCUIApplication) {
        let open = mapTool(app, "map-boundaries")
        XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        app.buttons["draw-boundary"].tap()
        XCTAssertTrue(app.buttons["save-boundary"].waitForExistence(timeout: 5))
        for (i,p) in [CGVector(dx: 0.20,dy: 0.36),CGVector(dx: 0.55,dy: 0.36),CGVector(dx: 0.55,dy: 0.52),CGVector(dx: 0.20,dy: 0.52)].enumerated() {
            app.coordinate(withNormalizedOffset: p).tap()
            let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","\(i+1) points"),object: app.staticTexts["boundary-point-count"])
            XCTAssertEqual(XCTWaiter.wait(for: [added],timeout: 5),.completed)
        }
        app.buttons["save-boundary"].tap()
        // Saving returns to the map with its options rail collapsed.
        XCTAssertTrue(app.buttons["map-options"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-boundary"].exists)
    }
    private func deleteQuietBoundary(_ app: XCUIApplication) {
        openBoundaryList(app)
        let delete = app.buttons["Delete boundary Boundary"]
        if !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let alert = app.alerts["Delete boundary?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No boundaries saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap(); app.buttons["Waypoints"].tap()
    }
    private func verifyQuietBoundary(_ app: XCUIApplication) {
        openBoundaryList(app)
        let geometry = app.staticTexts["4 points · closed perimeter"]
        if !geometry.isHittable { app.swipeUp() }
        XCTAssertTrue(geometry.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["stop-boundary"].exists)
        capture("backup-quiet-boundary-restored-inactive",app)
        app.buttons["Done"].tap(); app.buttons["Waypoints"].tap()
    }
    private func openBoundaryList(_ app: XCUIApplication) {
        // Acknowledge the map destination before opening its options rail.
        tapNativeMenuItem(app.buttons["Map"],revealing:app.buttons["map-options"])
        let open = mapTool(app, "map-boundaries")
        XCTAssertTrue(open.waitForExistence(timeout:10),app.debugDescription)
        tapNativeMenuItem(open)
    }
    private func capture(_ name: String,_ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
