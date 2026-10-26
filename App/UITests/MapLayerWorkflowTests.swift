import XCTest

final class MapLayerWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestOfflineMap", "-startTab", "map"]
        app.launch()
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func openLayers() {
        let button = app.buttons["map-layers"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        XCTAssertTrue(app.navigationBars["Map layers"].waitForExistence(timeout: 5))
    }
    private func toggle(_ name: String) {
        let control = app.switches[name]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        // A scrolled row may be partly behind the translucent navigation bar;
        // its right-hand switch then overlaps Done despite AX saying hittable.
        for _ in 0..<4 {
            if control.frame.midY < 200 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.3,dy: 0.35)).press(forDuration: 0.05,thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3,dy: 0.65)))
            } else if control.frame.midY > 650 { app.swipeUp() }
            else { break }
        }
        setNativeSwitch(control,to: (control.value as? String) != "1")
    }
    func testOfflineImportedMapGridAndSelectionSurviveRelaunch() {
        let name = app.staticTexts["map-layer-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(name.label.contains("OFFLINE ONLY")); XCTAssertTrue(name.label.contains("Offline training map"))
        capture("offline-mbtiles-map")
        openLayers()
        XCTAssertEqual(app.switches["MGRS grid"].value as? String,"1")
        toggle("MGRS grid")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["MAP CENTRE · GRID OFF"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments += ["-keepUITestData","-uiTestDeferredFieldLoad"]; app.launch()
        XCTAssertTrue(app.staticTexts["map-layer-name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["map-layer-name"].label.contains("Offline training map"))
        XCTAssertTrue(app.staticTexts["MAP CENTRE · GRID OFF"].exists)
        app.buttons["Toggle map night mode"].tap()
        capture("offline-map-night")
    }
    func testLayerSwitchKeepsWaypointOverlayAndNavigation() {
        app.buttons["Add waypoint at map centre"].tap()
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Offline objective")
        app.buttons["waypoint-save"].tap()
        openLayers(); app.buttons["layer-usgs"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["map-layer-name"].label.contains("USGS Topo"))
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-waypoint-")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        marker.tap()
        let navigate = app.buttons["map-navigate-waypoint"]
        XCTAssertTrue(navigate.waitForExistence(timeout: 5)); navigate.tap()
        XCTAssertTrue(app.staticTexts["Offline objective"].waitForExistence(timeout: 5))
    }
    func testOnlyUsgsLayersOfferAreaDownloadsAndShowEstimate() {
        openLayers()
        app.buttons["layer-streets"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["download-map-area"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["download-map-area"].isEnabled)
        toggle("Offline only")
        if !app.buttons["download-map-area"].exists { app.swipeUp() }
        XCTAssertFalse(app.buttons["download-map-area"].isEnabled)
        let usgs = app.buttons["layer-usgs"]
        // Stop at the first reachable layer row. A second downward swipe at
        // the top of a sheet can dismiss it on the smaller CI simulator.
        for _ in 0..<5 {
            if usgs.isHittable && usgs.frame.midY > app.navigationBars.firstMatch.frame.maxY { break }
            app.swipeDown()
        }
        XCTAssertTrue(usgs.isHittable); usgs.tap()
        app.swipeUp()
        let download = app.buttons["download-map-area"]
        XCTAssertTrue(download.isEnabled); download.tap()
        let estimate = app.staticTexts["offline-estimate"]
        if !estimate.isHittable { app.swipeUp() }
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        XCTAssertTrue(estimate.label.contains("tiles"))
        XCTAssertTrue(app.buttons["confirm-map-download"].exists)
        capture("offline-download-plan")
    }
}
