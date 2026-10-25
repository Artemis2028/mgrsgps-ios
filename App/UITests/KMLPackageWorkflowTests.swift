import XCTest

final class KMLPackageWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    private let mixed = "<kml><Folder><name>Mission</name><Placemark><name>Mission marker</name><Point><coordinates>54.3773,24.4539</coordinates></Point></Placemark><Placemark><name>Mission route</name><LineString><coordinates>54.3773,24.4539 54.378,24.455</coordinates></LineString></Placemark><Placemark><name>Mission area</name><Polygon><outerBoundaryIs><LinearRing><coordinates>54.377,24.453 54.378,24.453 54.378,24.454 54.377,24.453</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark></Folder></kml>"
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","waypoints"]; app.launch()
    }
    private func paste(_ xml: String) {
        app.buttons["Waypoint actions"].tap(); tapNativeMenuItem(app.buttons["Paste text"]); tapNativeMenuItem(app.buttons["Paste KML"])
        let input = app.textViews["gpx-import-text"]; XCTAssertTrue(input.waitForExistence(timeout: 8)); input.tap(); input.typeText(xml)
        app.buttons["preview-interchange"].tap()
    }
    private func confirmMixed() {
        XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 10)); XCTAssertEqual(app.staticTexts["interchange-counts"].label,"1 waypoints · 2 graphics/routes · 0 tracks")
        capture("kml-import-preview"); app.buttons["confirm-gpx-import"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Mission marker"].waitForExistence(timeout: 5))
    }
    private func exportAndReopen(_ format: String,_ base: String) {
        app.buttons["Waypoint actions"].tap(); tapNativeMenuItem(app.buttons["Export"]); tapNativeMenuItem(app.buttons["Export " + format])
        let filename = app.textFields["DOCPicker.filenameTextField"]; XCTAssertTrue(filename.waitForExistence(timeout: 10),app.debugDescription)
        let name = "gridfix-package-ui-" + UUID().uuidString.prefix(8)
        filename.tap(); filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: base.count)+name)
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["Waypoint actions"].waitForExistence(timeout: 10))
        app.buttons["Waypoint actions"].tap(); app.buttons["import-field-file"].tap()
        let file = app.cells.containing(NSPredicate(format: "label CONTAINS %@",String(name))).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15),app.debugDescription); file.tap()
        XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 15),app.debugDescription)
    }
    private func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
    func testKMLImportMapPersistenceAndATAKFilesPackagePreview() {
        paste(mixed); confirmMixed()
        app.tabBars.buttons["Map"].tap(); app.buttons["Show all visible data"].tap()
        XCTAssertTrue(app.staticTexts["map-field-overlays"].waitForExistence(timeout: 8)); XCTAssertEqual(app.staticTexts["map-field-overlays"].label,"1 routes · 0 tracks")
        capture("kml-route-area-map"); app.tabBars.buttons["Waypoints"].tap()
        exportAndReopen("ATAK package","gridfix-datapackage")
        XCTAssertEqual(app.staticTexts["interchange-counts"].label,"1 waypoints · 1 graphics/routes · 0 tracks")
        capture("atak-file-preview"); app.buttons["Cancel"].tap()
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.buttons["edit-waypoint-Mission marker"].waitForExistence(timeout: 8))
        app.buttons["open-field-library"].tap(); XCTAssertTrue(app.buttons["route-Mission route"].waitForExistence(timeout: 5))
    }
    func testKMZNativeFilesRoundTripPreservesGeographicCounts() {
        paste(mixed); confirmMixed()
        exportAndReopen("KMZ","gridfix")
        XCTAssertEqual(app.staticTexts["interchange-counts"].label,"1 waypoints · 2 graphics/routes · 0 tracks")
        XCTAssertTrue(app.staticTexts["KMZ preview"].exists)
        capture("kmz-file-preview"); app.buttons["Cancel"].tap()
    }
    func testKMLHoleRejectsAllRecordsAndNightPreviewIsReadable() {
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        let hole = "<kml><Placemark><name>Must stay unsaved</name><Point><coordinates>54,24</coordinates></Point></Placemark><Placemark><Polygon><innerBoundaryIs><LinearRing><coordinates>54,24 55,24 55,25</coordinates></LinearRing></innerBoundaryIs></Polygon></Placemark></kml>"
        paste(hole)
        let message = app.staticTexts["interchange-message"]; XCTAssertTrue(message.waitForExistence(timeout: 8)); XCTAssertTrue(message.label.contains("holes"))
        XCTAssertFalse(app.buttons["confirm-gpx-import"].exists); capture("kml-hole-rejected-night"); app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["edit-waypoint-Must stay unsaved"].exists)
        paste(mixed); XCTAssertTrue(app.staticTexts["interchange-counts"].waitForExistence(timeout: 8)); capture("kml-preview-night")
        app.buttons["confirm-gpx-import"].tap(); XCTAssertTrue(app.buttons["edit-waypoint-Mission marker"].waitForExistence(timeout: 5))
    }
}
