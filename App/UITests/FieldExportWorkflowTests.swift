import XCTest

final class FieldExportWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(_ fixture: String) {
        app.launchArguments = ["-uiTesting",fixture,"-uiTestBoundaryMap","-startTab","waypoints"]; app.launch()
        XCTAssertTrue(app.buttons["Waypoint actions"].waitForExistence(timeout: 10))
    }
    private func exportLibraryGPX() {
        app.buttons["Waypoint actions"].tap(); tapNativeMenuItem(app.buttons["Export"]); tapNativeMenuItem(app.buttons["Export GPX"])
    }
    @discardableResult
    private func saveAndReview(_ stem: String,fromDetails: Bool = false,startingInIcons: Bool = false) -> String {
        let filename = app.textFields["export-filename"]
        XCTAssertTrue(filename.waitForExistence(timeout: 30),app.debugDescription)
        let name = stem + String(UUID().uuidString.prefix(8))
        replaceTextInput(filename,name); XCTAssertEqual(filename.value as? String,name)
        if app.buttons["export-filename-keyboard-done"].exists { app.buttons["export-filename-keyboard-done"].tap() }
        capture(fromDetails ? "export-filename-night" : "export-filename")
        saveNativeFile(in: app)
        if fromDetails {
            let done = app.navigationBars["Recon track"].buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10)); tapNativeMenuItem(done)
        }
        XCTAssertTrue(app.buttons["Waypoint actions"].waitForExistence(timeout: 10))
        app.buttons["Waypoint actions"].tap(); tapNativeMenuItem(app.buttons["import-field-file"])
        openSavedNativeFile(name,in: app,startingInIcons:startingInIcons)
        XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 15),app.debugDescription)
        return name
    }
    private func counts(_ expected: String) {
        XCTAssertEqual(app.staticTexts["interchange-counts"].label.replacingOccurrences(of: ",",with: ""),expected)
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testLongImportedFilenameWrapsWithoutLosingItsExtension() {
        launch("-uiTestLibrary"); exportLibraryGPX()
        let name = saveAndReview(String(repeating: "VeryLongPatrolFilename", count: 4))
        let filename = app.staticTexts["interchange-filename"]
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        XCTAssertEqual(filename.label, name + ".gpx")
        XCTAssertGreaterThan(filename.frame.height, 40, "The full filename should wrap")
        let viewport = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(filename.frame.minX, viewport.minX)
        XCTAssertLessThanOrEqual(filename.frame.maxX, viewport.maxX)
        counts("3 waypoints · 1 graphics/routes · 1 tracks")
        capture("import-full-long-filename")
        app.buttons["Cancel"].tap()
    }
    func testLargeLibraryGPXExportsThroughFilesAndReopensAllRecords() {
        launch("-uiTestLargeLibrary")
        XCTAssertTrue(app.buttons["edit-waypoint-Point 4999"].waitForExistence(timeout: 10))
        exportLibraryGPX(); saveAndReview("large-field-export-")
        counts("5000 waypoints · 1000 graphics/routes · 0 tracks")
        capture("large-gpx-export-file-preview"); app.buttons["Cancel"].tap()
    }
    func testLargeLibraryGPXReopensAfterNativeIconToListTransition() {
        launch("-uiTestLargeLibrary")
        XCTAssertTrue(app.buttons["edit-waypoint-Point 4999"].waitForExistence(timeout:10))
        exportLibraryGPX(); saveAndReview("icons-field-export-",startingInIcons:true)
        counts("5000 waypoints · 1000 graphics/routes · 0 tracks")
        capture("large-gpx-icon-transition-preview"); app.buttons["Cancel"].tap()
    }
    func testNativeExportCancellationAllowsAnotherCompleteExport() {
        launch("-uiTestLibrary"); exportLibraryGPX()
        let filename = app.textFields["export-filename"]
        XCTAssertTrue(filename.waitForExistence(timeout: 30),app.debugDescription)
        replaceTextInput(filename,"/")
        XCTAssertFalse(app.buttons["export-choose-location"].isEnabled)
        app.buttons["export-filename-cancel"].tap()
        XCTAssertTrue(app.buttons["Waypoint actions"].waitForExistence(timeout:10))
        exportLibraryGPX()
        XCTAssertTrue(filename.waitForExistence(timeout:30),app.debugDescription)
        chooseNativeExportLocation(in: app)
        let picker = app.otherElements["Browse View (Picker)"]
        // Dismiss the actual Files sheet by its top grabber, without saving.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: .init(dx: 0.5,dy: 0.075)).press(forDuration: 0.1,thenDragTo: window.coordinate(withNormalizedOffset: .init(dx: 0.5,dy: 0.88)))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed],timeout: 10),.completed)
        XCTAssertTrue(app.buttons["Waypoint actions"].waitForExistence(timeout: 10))
        exportLibraryGPX(); saveAndReview("cancel-retry-export-")
        counts("3 waypoints · 1 graphics/routes · 1 tracks")
        capture("field-export-after-native-cancel"); app.buttons["Cancel"].tap()
    }
    func testTrackDetailAndLibraryMenuExportOnlyTheChosenTrackInNightMode() {
        launch("-uiTestLibrary")
        app.tabBars.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap()
        // Reopen the persisted library through the production worker path so
        // both exports exercise a saved source, not only fixture-owned bytes.
        app.terminate(); app.launchArguments += ["-keepUITestData","-uiTestDeferredFieldLoad"]; app.launch()
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            self.app.buttons["Waypoint actions"].isEnabled && !self.app.staticTexts["field-library-loading"].exists
        },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:15),.completed,app.debugDescription)
        let search = app.textFields["library-search"]; XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Recon track\n")
        let actions = app.buttons["Actions for track Recon track"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap(); tapNativeMenuItem(app.buttons["Details"])
        let export = app.buttons["Export GPX"]
        XCTAssertTrue(export.waitForExistence(timeout: 10)); export.tap()
        saveAndReview("detail-track-export-",fromDetails: true)
        counts("0 waypoints · 0 graphics/routes · 1 tracks")
        capture("track-detail-export-preview-night"); app.buttons["Cancel"].tap()
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap(); tapNativeMenuItem(app.buttons["Export GPX"])
        saveAndReview("menu-track-export-")
        counts("0 waypoints · 0 graphics/routes · 1 tracks")
        capture("track-menu-export-preview-night"); app.buttons["Cancel"].tap()
    }
}
