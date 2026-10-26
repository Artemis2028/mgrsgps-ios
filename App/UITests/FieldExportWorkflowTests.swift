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
    private func saveAndReview(_ stem: String,fromDetails: Bool = false) {
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 15),app.debugDescription)
        let name = stem + String(UUID().uuidString.prefix(8))
        replaceTextInput(filename,name); XCTAssertEqual(filename.value as? String,name)
        saveNativeFile(in: app)
        if fromDetails {
            let done = app.navigationBars["Recon track"].buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10)); tapNativeMenuItem(done)
        }
        XCTAssertTrue(app.buttons["Waypoint actions"].waitForExistence(timeout: 10))
        app.buttons["Waypoint actions"].tap(); tapNativeMenuItem(app.buttons["import-field-file"])
        openSavedNativeFile(name,in: app)
        XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 15),app.debugDescription)
    }
    private func counts(_ expected: String) {
        XCTAssertEqual(app.staticTexts["interchange-counts"].label.replacingOccurrences(of: ",",with: ""),expected)
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testLargeLibraryGPXExportsThroughFilesAndReopensAllRecords() {
        launch("-uiTestLargeLibrary")
        XCTAssertTrue(app.buttons["edit-waypoint-Point 4999"].waitForExistence(timeout: 10))
        exportLibraryGPX(); saveAndReview("large-field-export-")
        counts("5000 waypoints · 1000 graphics/routes · 0 tracks")
        capture("large-gpx-export-file-preview"); app.buttons["Cancel"].tap()
    }
    func testNativeExportCancellationAllowsAnotherCompleteExport() {
        launch("-uiTestLibrary"); exportLibraryGPX()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 15),app.debugDescription)
        // Dismiss the actual Files sheet by its top grabber, without saving.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: .init(dx: 0.5,dy: 0.075)).press(forDuration: 0.1,thenDragTo: window.coordinate(withNormalizedOffset: .init(dx: 0.5,dy: 0.88)))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: filename)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed],timeout: 10),.completed)
        XCTAssertTrue(app.buttons["Waypoint actions"].waitForExistence(timeout: 10))
        exportLibraryGPX(); saveAndReview("cancel-retry-export-")
        counts("3 waypoints · 1 graphics/routes · 1 tracks")
        capture("field-export-after-native-cancel"); app.buttons["Cancel"].tap()
    }
    func testTrackDetailAndLibraryMenuExportOnlyTheChosenTrackInNightMode() {
        launch("-uiTestLibrary")
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
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
