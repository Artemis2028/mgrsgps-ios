import XCTest

final class ProtectedFileWorkflowTests: XCTestCase {
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func run(format: String,night: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","waypoints"]
        app.launch()
        if night { app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap() }
        let actions = app.buttons["Waypoint actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        tapNativeMenuItem(app.buttons["Export"]); tapNativeMenuItem(app.buttons["Export protected file…"])
        let choice = app.buttons[format.lowercased()]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        let password = app.secureTextFields["backup-password"], confirmation = app.secureTextFields["backup-password-confirmation"]
        XCTAssertTrue(password.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["backup-password-submit"].isEnabled)
        password.tap(); password.typeText("correct horse"); confirmation.tap(); confirmation.typeText("correct horse")
        app.buttons["backup-password-keyboard-done"].tap()
        capture(night ? "protected-file-export-password-night" : "protected-file-export-password-day")
        app.buttons["backup-password-submit"].tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 20),app.debugDescription)
        let name = "protected-"+format.lowercased()+"-"+String(UUID().uuidString.prefix(8))
        replaceTextInput(filename,name); saveNativeFile(in: app)
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        app.buttons["Recon"].tap(); app.buttons["library-select-button"].tap(); app.buttons["library-select-all"].tap()
        app.buttons["Selected item actions"].tap(); tapNativeMenuItem(app.buttons["library-delete-selected"])
        let deletion = app.alerts.firstMatch
        XCTAssertTrue(deletion.waitForExistence(timeout: 5)); deletion.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].waitForExistence(timeout: 8))
        app.buttons["All"].tap()
        func openFile() {
            actions.tap(); tapNativeMenuItem(app.buttons["import-field-file"])
            openSavedNativeFile(name,in: app)
            XCTAssertTrue(app.secureTextFields["interchange-password"].waitForExistence(timeout: 12),app.debugDescription)
        }
        func unlock(_ value: String) {
            let input = app.secureTextFields["interchange-password"]
            input.tap(); input.typeText(value)
            if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
            app.buttons["preview-interchange"].tap()
        }
        openFile(); unlock("incorrect")
        let error = app.staticTexts["interchange-message"]
        XCTAssertTrue(error.waitForExistence(timeout: 10)); XCTAssertTrue(error.label.contains("Wrong password"),error.label)
        XCTAssertFalse(app.buttons["confirm-gpx-import"].exists)
        capture(night ? "protected-file-wrong-password-night" : "protected-file-wrong-password-day")
        unlock("correct horse")
        let counts = app.staticTexts["interchange-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 12),app.debugDescription)
        XCTAssertFalse(counts.label.hasPrefix("0 waypoints"))
        capture(night ? "protected-file-preview-night" : "protected-file-preview-day")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["edit-waypoint-Bravo"].exists,"Unlock/preview must not import")
        openFile(); unlock("correct horse")
        XCTAssertTrue(app.buttons["confirm-gpx-import"].waitForExistence(timeout: 10)); app.buttons["confirm-gpx-import"].tap()
        let duplicate = app.alerts["Already here"]
        if duplicate.waitForExistence(timeout: 5) { duplicate.buttons["Import all"].tap() }
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout: 12),app.debugDescription)
        capture(night ? "protected-file-imported-night" : "protected-file-imported-day")
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout: 10))
    }
    func testProtectedGPXNativeFilesRetryCancelImportAndRelaunch() { run(format: "GPX",night: false) }
    func testProtectedKMLNativeFilesRetryCancelImportAndRelaunchAtNight() { run(format: "KML",night: true) }
    func testProtectedTrackDetailsExportsOnlyChosenTrack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","waypoints"]; app.launch()
        let search = app.textFields["library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Recon track\n")
        app.buttons["Actions for track Recon track"].tap(); tapNativeMenuItem(app.buttons["Details"])
        let protect = app.buttons["track-protected-export"]
        XCTAssertTrue(protect.waitForExistence(timeout: 8)); protect.tap()
        let pw = app.secureTextFields["backup-password"], confirm = app.secureTextFields["backup-password-confirmation"]
        XCTAssertTrue(pw.waitForExistence(timeout: 8)); pw.tap(); pw.typeText("correct horse"); confirm.tap(); confirm.typeText("correct horse")
        app.buttons["backup-password-keyboard-done"].tap(); app.buttons["backup-password-submit"].tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 20))
        let name = "protected-track-"+String(UUID().uuidString.prefix(8))
        replaceTextInput(filename,name); saveNativeFile(in: app)
        let done = app.navigationBars["Recon track"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8)); tapNativeMenuItem(done)
        let actions = app.buttons["Waypoint actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); tapNativeMenuItem(actions); tapNativeMenuItem(app.buttons["import-field-file"])
        openSavedNativeFile(name,in: app)
        let input = app.secureTextFields["interchange-password"]
        XCTAssertTrue(input.waitForExistence(timeout: 12)); input.tap(); input.typeText("correct horse")
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        app.buttons["preview-interchange"].tap()
        let counts = app.staticTexts["interchange-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10)); XCTAssertEqual(counts.label,"0 waypoints · 0 graphics/routes · 1 tracks")
        capture("protected-single-track-preview"); app.buttons["Cancel"].tap()
    }
    func testQueuedIncomingBackupAndExportRequireSeparateConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestProtectedIncoming","-startTab","waypoints"]; app.launch()
        let first = app.buttons["Review incoming-backup.mgrsgps"]
        XCTAssertTrue(first.waitForExistence(timeout: 12)); first.tap()
        func unlock() {
            let input = app.secureTextFields["interchange-password"]
            XCTAssertTrue(input.waitForExistence(timeout: 10)); input.tap(); input.typeText("fixture password")
            if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
            app.buttons["preview-interchange"].tap()
        }
        unlock()
        XCTAssertTrue(app.staticTexts["backup-import-counts"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["backup-quiet-boundary-count"].label,"1 quiet boundary · imported monitoring stays off")
        capture("protected-incoming-backup-review")
        app.buttons["confirm-protected-backup"].tap()
        let next = app.buttons["Review incoming-file.mgrsgps"]
        XCTAssertTrue(next.waitForExistence(timeout: 12)); next.tap(); unlock()
        XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 10))
        capture("protected-queued-file-review")
        app.buttons["confirm-gpx-import"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Protected queued point"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["edit-waypoint-Protected backup point"].exists)
        let report = app.staticTexts["incoming-import-status"]
        XCTAssertTrue(report.label.contains("Restored")); XCTAssertTrue(report.label.contains("Imported"))
        XCTAssertFalse(app.buttons["Review incoming-file.mgrsgps"].exists)
        XCTAssertTrue(report.label.contains("1 quiet boundary"))
        verifyIncomingQuietArea(app)
        capture("protected-incoming-results-retained")
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        XCTAssertTrue(app.buttons["edit-waypoint-Protected queued point"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["edit-waypoint-Protected backup point"].exists)
        verifyIncomingQuietArea(app)
    }
    private func verifyIncomingQuietArea(_ app: XCUIApplication) {
        app.buttons["Map"].tap()
        let open = app.buttons["map-boundaries"]
        XCTAssertTrue(open.waitForExistence(timeout: 8)); open.tap()
        let saved = app.buttons["monitor-boundary-Incoming quiet area"]
        if !saved.isHittable { app.swipeUp() }
        XCTAssertTrue(saved.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["stop-boundary"].exists)
        XCTAssertTrue(app.staticTexts["4 points · closed perimeter"].exists)
        capture("incoming-quiet-boundary-inactive")
        app.navigationBars["Boundaries"].buttons["Done"].tap(); app.buttons["Waypoints"].tap()
    }
}
