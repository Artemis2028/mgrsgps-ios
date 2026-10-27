import XCTest

final class SettingsBackupWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<28 {
            let surface = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app.scrollViews.firstMatch
            let top = max(app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? 60,surface.frame.minY)+8
            let bottom = min(app.windows.firstMatch.frame.maxY-35,surface.frame.maxY)
            if element.exists,element.isHittable,element.frame.minY >= top,element.frame.maxY <= bottom { return }
            if element.exists && element.frame.midY < top { surface.swipeDown() }
            else { surface.swipeUp() }

        }
        XCTFail("Backup control must remain reachable: " + app.debugDescription)
    }
    private func open(_ app: XCUIApplication,night: Bool = false) {
        tapNativeMenuItem(app.buttons["Position"]); tapNativeMenuItem(app.buttons["Settings"])
        if night { setNativeSwitch(app.switches["Red-on-black, to keep night vision"],to:true) }
        let entry = app.buttons["settings-backup"]; reveal(entry,in:app); tapNativeMenuItem(entry)
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout:10))
    }
    private func close(_ app: XCUIApplication) {
        tapNativeMenuItem(app.navigationBars["Backup & restore"].buttons["Done"])
        tapNativeMenuItem(app.navigationBars["Settings"].buttons["Done"])
    }
    private func password(_ value: String,in app: XCUIApplication,export: Bool = false) {
        let field = app.secureTextFields["backup-password"]
        XCTAssertTrue(field.waitForExistence(timeout:10)); field.tap(); field.typeText(value)
        if export {
            let confirmation = app.secureTextFields["backup-password-confirmation"]
            confirmation.tap(); confirmation.typeText(value)
        }
        tapNativeMenuItem(app.buttons["backup-password-keyboard-done"])
        tapNativeMenuItem(app.buttons["backup-password-submit"])
    }
    private func run(protected: Bool) {
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","position"]; app.launch()
        open(app,night:protected)
        tapNativeMenuItem(app.buttons[protected ? "settings-backup-protect" : "settings-backup-export"])
        if protected { password("fixture password",in:app,export:true) }
        let filename = app.textFields["export-filename"]
        XCTAssertTrue(filename.waitForExistence(timeout:20),app.debugDescription)
        let name = "settings-backup-"+String(UUID().uuidString.prefix(8))
        replaceTextInput(filename,name); saveNativeFile(in:app)
        let status = app.staticTexts["settings-backup-status"]
        XCTAssertTrue(status.waitForExistence(timeout:10)); XCTAssertEqual(status.label,"Backup saved")
        capture(protected ? "settings-protected-backup-saved-night" : "settings-backup-saved-day")
        close(app)
        tapNativeMenuItem(app.buttons["Waypoints"]); tapNativeMenuItem(app.buttons["Recon"])
        tapNativeMenuItem(app.buttons["library-select-button"]); tapNativeMenuItem(app.buttons["library-select-all"])
        XCTAssertEqual(app.staticTexts["library-selected-count"].label,"3 selected")
        tapNativeMenuItem(app.buttons["Selected item actions"]); tapNativeMenuItem(app.buttons["library-delete-selected"])
        let confirm = app.alerts.firstMatch; XCTAssertTrue(confirm.waitForExistence(timeout:5)); tapNativeMenuItem(confirm.buttons["Delete"])
        XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].waitForExistence(timeout:10))
        open(app)
        func restore(_ value: String? = nil) {
            tapNativeMenuItem(app.buttons["settings-backup-restore"]); openSavedNativeFile(name,in:app)
            if let value { password(value,in:app) }
        }
        if protected {
            restore("wrong password")
            let failed = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in status.exists && status.label.contains("Import failed") },object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[failed],timeout:15),.completed)
            capture("settings-protected-backup-wrong-password-night")
        }
        restore(protected ? "fixture password" : nil)
        let restored = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in status.exists && status.label.hasPrefix("Restored") },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[restored],timeout:20),.completed,app.debugDescription)
        capture(protected ? "settings-backup-restored-night" : "settings-backup-restored-day")
        close(app); tapNativeMenuItem(app.buttons["Waypoints"]); tapNativeMenuItem(app.buttons["Recon"])
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
        app.terminate(); app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-keepUITestData","-startTab","waypoints"]; app.launch()
        tapNativeMenuItem(app.buttons["Recon"])
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
    }
    func testSettingsBackupNativeFilesRoundTripRestoresSavedRecordsInDay() { run(protected:false) }
    func testSettingsProtectedBackupRejectsWrongPasswordAndRestoresAtNight() { run(protected:true) }
    func testLargestNightSettingsBackupActionsAndProtectedCancelRemainReachable() {
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestLibrary","-startTab","position","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        open(app,night:true)
        let protect = app.buttons["settings-backup-protect"]
        reveal(protect,in:app); capture("settings-backup-largest-night-actions"); tapNativeMenuItem(protect)
        XCTAssertTrue(app.secureTextFields["backup-password"].waitForExistence(timeout:10))
        tapNativeMenuItem(app.navigationBars.buttons["Cancel"])
        reveal(protect,in:app); XCTAssertTrue(protect.isEnabled)
        let restore = app.buttons["settings-backup-restore"]; reveal(restore,in:app); XCTAssertTrue(restore.isEnabled)
        capture("settings-backup-largest-night-cancelled")
    }
}
