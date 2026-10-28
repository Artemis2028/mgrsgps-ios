import XCTest

final class MapLayerWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestOfflineMap", "-startTab", "map"]
        app.launch()
    }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }
    func testCompactMapGridDisclosureAndAnimatedOptionsInPortraitAndLandscape() {
        let grid = app.buttons["map-centre-summary"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["map-layer-name"].exists)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.scrollViews["map-options-rail"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        let summary = app.buttons["map-centre-summary"]
        summary.tap()
        XCTAssertTrue(app.staticTexts["map-layer-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map-centre-latlon"].exists)
        XCTAssertTrue(app.staticTexts["map-centre-utm"].label.hasPrefix("UTM "))
        summary.tap()
        XCTAssertFalse(app.staticTexts["map-layer-name"].exists)
        let options = app.buttons["map-options"]
        options.tap()
        XCTAssertTrue(app.scrollViews["map-options-rail"].waitForExistence(timeout: 5))
        capture("map-options-expanded-portrait")
        closeMapOptions(app)
        capture("map-options-collapsed-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        mapTool(app, "map-layers").tap()
        XCTAssertTrue(app.navigationBars["Map layers"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertFalse(app.scrollViews["map-options-rail"].exists)
        mapTool(app, "Toggle map night mode").tap()
        capture("map-options-night-landscape")
        closeMapOptions(app)
        XCTAssertTrue(grid.exists)
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func holdSavedGeometry() {
        app.terminate()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-uiTestHoldMapGeometry","-startTab","map"]
        app.launch()
        XCTAssertTrue(mapReadout(app, "map-field-loading").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Show all visible data"].isEnabled)
    }
    private func finishSavedGeometry() {
        app.buttons["finish-map-geometry"].tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@","1 routes · 1 tracks"),object: mapReadout(app, "map-field-overlays"))
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 10),.completed,app.debugDescription)
        XCTAssertFalse(mapReadout(app, "map-field-loading").exists)
    }
    func testShowAllWaitsForSavedGeometryInsteadOfFittingAnEmptySnapshot() {
        holdSavedGeometry()
        let centre = app.buttons["map-centre-summary"],before = centre.label
        app.buttons["Show all visible data"].tap()
        capture("map-data-loading-with-fit-pending")
        finishSavedGeometry()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@",before),object: centre)
        XCTAssertEqual(XCTWaiter.wait(for: [moved],timeout: 10),.completed,app.debugDescription)
        capture("map-data-ready-and-fit-complete")
    }
    func testNewGoToSupersedesFitRequestedWhileSavedGeometryWasLoading() {
        holdSavedGeometry(); app.buttons["Show all visible data"].tap()
        mapTool(app, "map-goto").tap()
        let field = app.textFields["map-goto-grid"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); replaceTextInput(field,"40R BN 4000 1000")
        app.buttons["map-goto-keyboard-done"].tap(); app.buttons["map-goto-show"].tap()
        let centre = app.buttons["map-centre-summary"]
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@","4000"),object: centre)
        XCTAssertEqual(XCTWaiter.wait(for: [moved],timeout: 10),.completed)
        let chosen = centre.label
        finishSavedGeometry()
        let overridden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@",chosen),object: centre)
        XCTAssertEqual(XCTWaiter.wait(for: [overridden],timeout: 2),.timedOut,"An old fit must not override the newer Go to request")
        capture("map-new-camera-intent-retained-after-load")
    }
    func testManualPanCancelsFitRequestedWhileSavedGeometryWasLoading() {
        holdSavedGeometry(); app.buttons["Show all visible data"].tap()
        let centre = app.buttons["map-centre-summary"],before = centre.label
        app.coordinate(withNormalizedOffset: .init(dx: 0.65,dy: 0.55)).press(forDuration: 0.1,thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.3,dy: 0.55)),withVelocity: .slow,thenHoldForDuration: 0.3)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@",before),object: centre)
        XCTAssertEqual(XCTWaiter.wait(for: [moved],timeout: 10),.completed)
        let chosen = centre.label
        finishSavedGeometry()
        let overridden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@",chosen),object: centre)
        XCTAssertEqual(XCTWaiter.wait(for: [overridden],timeout: 2),.timedOut,"A pending fit must not undo a manual pan")
        capture("map-pan-retained-after-load")
    }
    private func openLayers() {
        let button = mapTool(app, "map-layers")
        XCTAssertTrue(button.waitForExistence(timeout: 10)); tapNativeMenuItem(button,revealing:app.navigationBars["Map layers"])
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
        let name = mapReadout(app, "map-layer-name")
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(name.label.contains("OFFLINE ONLY")); XCTAssertTrue(name.label.contains("Offline training map"))
        capture("offline-mbtiles-map")
        openLayers()
        XCTAssertEqual(app.switches["MGRS grid"].value as? String,"1")
        toggle("MGRS grid")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["MAP CENTRE · GRID OFF"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments += ["-keepUITestData","-uiTestDeferredFieldLoad"]; app.launch()
        XCTAssertTrue(mapReadout(app, "map-layer-name").waitForExistence(timeout: 10))
        XCTAssertTrue(mapReadout(app, "map-layer-name").label.contains("Offline training map"))
        XCTAssertTrue(app.staticTexts["MAP CENTRE · GRID OFF"].exists)
        mapTool(app, "Toggle map night mode").tap()
        capture("offline-map-night")
        // Restore the native day bar after using the separate night controls.
        mapTool(app, "Toggle map night mode").tap()
        let map = app.tabBars.buttons["Map"]
        XCTAssertTrue(map.waitForExistence(timeout:5)); XCTAssertTrue(map.isSelected)
        capture("offline-map-day-restored")
        app.tabBars.buttons["Position"].tap()
        XCTAssertTrue(app.staticTexts["position-title"].waitForExistence(timeout:5))
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.staticTexts["MAP CENTRE · GRID OFF"].waitForExistence(timeout:5))
        capture("offline-map-native-tab-return")
    }
    func testLayerSwitchKeepsWaypointOverlayAndNavigation() {
        mapTool(app, "Add waypoint at map centre").tap()
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Offline objective")
        app.buttons["waypoint-save"].tap()
        openLayers(); app.buttons["layer-usgs"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(mapReadout(app, "map-layer-name").label.contains("USGS Topo"))
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
