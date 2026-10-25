import XCTest

final class InterchangeWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","waypoints"]; app.launch()
    }
    private func paste(_ format: String,_ text: String) {
        app.buttons["Waypoint actions"].tap(); app.buttons["Paste text"].tap(); app.buttons["Paste " + format].tap()
        let input = app.textViews["gpx-import-text"]; XCTAssertTrue(input.waitForExistence(timeout: 10),app.debugDescription)
        input.tap(); input.typeText(text)
        app.buttons["preview-interchange"].tap()
    }
    private func confirm() {
        let button = app.buttons["confirm-gpx-import"]; XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testCSVPreviewCancelConfirmRetryAndPersistence() {
        let csv = "name,lat,lon,folder\nCSV Alpha,24.4539,54.3773,Recon\nBad,95,0,Recon\n"
        paste("CSV",csv)
        XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["interchange-counts"].label,"1 waypoints · 0 graphics/routes · 0 tracks")
        capture("csv-import-preview")
        app.buttons["Cancel"].tap(); XCTAssertFalse(app.buttons["edit-waypoint-CSV Alpha"].exists)
        paste("CSV",csv); confirm()
        XCTAssertTrue(app.buttons["edit-waypoint-CSV Alpha"].waitForExistence(timeout: 5))
        paste("CSV",csv); confirm()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@","Nothing new to import")).firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertEqual(app.buttons.matching(identifier: "edit-waypoint-CSV Alpha").count,1)
    }
    func testGeoJSONPreviewRoutesAndAreasReachMapAndExportActions() {
        let json = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"name\":\"JSON marker\"},\"geometry\":{\"type\":\"Point\",\"coordinates\":[54.3773,24.4539]}},{\"type\":\"Feature\",\"properties\":{\"name\":\"JSON route\"},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[54.3773,24.4539],[54.378,24.455]]}},{\"type\":\"Feature\",\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[54.377,24.453],[54.378,24.453],[54.378,24.454],[54.377,24.453]]]}}]}"
        paste("GeoJSON",json); confirm()
        XCTAssertTrue(app.buttons["edit-waypoint-JSON marker"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Map"].tap(); app.buttons["Show all visible data"].tap()
        XCTAssertTrue(app.staticTexts["map-field-overlays"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["map-field-overlays"].label,"1 routes · 0 tracks")
        capture("geojson-map-import")
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["Waypoint actions"].tap()
        app.buttons["Export"].tap()
        XCTAssertTrue(app.buttons["Export CSV"].exists); XCTAssertTrue(app.buttons["Export GeoJSON"].exists)
        app.buttons["Export GeoJSON"].tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 10),app.debugDescription)
        capture("geojson-export-files")
        let name = "gridfix-ui-" + UUID().uuidString.prefix(8)
        filename.tap(); filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: 7) + name)
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["Waypoint actions"].waitForExistence(timeout: 10))
        app.buttons["Waypoint actions"].tap(); app.buttons["import-field-file"].tap()
        let file = app.cells.containing(NSPredicate(format: "label CONTAINS %@",String(name))).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15),app.debugDescription); file.tap()
        XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 15),app.debugDescription)
        XCTAssertEqual(app.staticTexts["interchange-counts"].label,"1 waypoints · 2 graphics/routes · 0 tracks")
        capture("geojson-file-import-preview"); app.buttons["Cancel"].tap()
    }
    func testMalformedInputAndNightPreviewRemainReadable() {
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        paste("GeoJSON","{broken")
        XCTAssertTrue(app.staticTexts["interchange-message"].waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["confirm-gpx-import"].exists)
        app.buttons["Cancel"].tap()
        paste("CSV","name,lat,lon\nNight point,24,54\n")
        XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 10))
        capture("interchange-preview-night"); confirm()
        XCTAssertTrue(app.buttons["edit-waypoint-Night point"].waitForExistence(timeout: 5))
    }
}
