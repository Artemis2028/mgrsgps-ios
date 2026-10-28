import XCTest

final class MapToolWorkflowTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","map"]; app.launch()
        XCTAssertTrue(mapTool(app, "map-button-settings").waitForExistence(timeout: 10)); return app
    }
    private func settings(_ app: XCUIApplication) { mapTool(app, "map-button-settings").tap(); XCTAssertTrue(app.switches["map-tool-shown-layers"].waitForExistence(timeout: 5)) }
    private func set(_ key: String,shown: Bool,in app: XCUIApplication) {
        let value = app.switches["map-tool-shown-"+key]
        for _ in 0..<4 { if value.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(value.isHittable,app.debugDescription)
        setNativeSwitch(value,to: shown)
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@",shown ? "1" : "0"),object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [applied],timeout: 5),.completed,app.debugDescription)
    }
    private func done(_ app: XCUIApplication) {
        tapNativeMenuItem(app.navigationBars.buttons["Done"])
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: app.switches["map-tool-shown-layers"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed],timeout: 5),.completed,app.debugDescription)
    }
    private func capture(_ name: String,_ app: XCUIApplication) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testHiddenToolsPersistResetAndGoToMovesOnlyTheMapInDayAndNight() {
        let app = launch()
        capture("map-tools-all-day",app)
        settings(app)
        for key in ["layers","locate","ruler","draw","goto","tools","record"] { set(key,shown: false,in: app) }
        capture("map-tools-hidden-settings-day",app); done(app)
        for id in ["map-layers","map-ruler","map-graphics","map-lanes","map-boundaries","map-goto","map-measure","map-terrain","record-track","Locate"] { XCTAssertFalse(app.buttons[id].exists,id) }
        XCTAssertTrue(app.buttons["Show all visible data"].exists)
        mapTool(app, "Toggle map night mode").tap(); capture("map-tools-hidden-night",app)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(mapTool(app, "map-button-settings").waitForExistence(timeout: 10)); XCTAssertFalse(mapTool(app, "map-goto").exists)
        settings(app)
        let reset = app.buttons["map-tools-reset"]
        for _ in 0..<4 { if reset.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(reset.isHittable); reset.tap(); capture("map-tools-reset-settings-night",app); done(app)
        mapTool(app, "map-goto").tap()
        let show = app.buttons["map-goto-show"]
        XCTAssertTrue(show.waitForExistence(timeout: 5)); XCTAssertFalse(show.isEnabled)
        let field = app.textFields["map-goto-grid"]; replaceTextInput(field,"40R BN 4000 1000")
        app.buttons["map-goto-keyboard-done"].tap(); XCTAssertTrue(show.isEnabled)
        capture("map-go-to-grid-night",app); show.tap()
        let centre = app.buttons["map-centre-summary"]
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@","4000"),object: centre)
        XCTAssertEqual(XCTWaiter.wait(for: [moved],timeout: 10),.completed,app.debugDescription)
        XCTAssertFalse(app.buttons["stop-boundary"].exists); XCTAssertFalse(app.buttons["recording-banner"].exists)
        capture("map-go-to-result-night",app)
        let before = centre.label
        mapTool(app, "map-goto").tap(); selectNativeSegment(app.segmentedControls["map-goto-format"].buttons["Lat / Lon"])
        let latitude = app.textFields["map-goto-latitude"], longitude = app.textFields["map-goto-longitude"]
        replaceTextInput(latitude,"86"); replaceTextInput(longitude,"54.4")
        app.buttons["map-goto-keyboard-done"].tap(); XCTAssertFalse(show.isEnabled)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@","Map coverage ends")).firstMatch.exists)
        replaceTextInput(latitude,"24.5"); app.buttons["map-goto-keyboard-done"].tap(); XCTAssertTrue(show.isEnabled)
        capture("map-go-to-decimal-night",app); show.tap()
        let decimalMoved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@",before),object: centre)
        XCTAssertEqual(XCTWaiter.wait(for: [decimalMoved],timeout: 10),.completed,app.debugDescription)
    }
    func testHiddenActiveRulerAndDrawingRetainFinishControls() {
        let app = launch(); mapTool(app, "map-ruler").tap()
        XCTAssertTrue(app.buttons["ruler-done"].waitForExistence(timeout: 5))
        settings(app); set("ruler",shown: false,in: app); done(app)
        XCTAssertTrue(mapTool(app, "map-ruler").exists); closeMapOptions(app); app.buttons["ruler-done"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: mapTool(app, "map-ruler"))
        XCTAssertEqual(XCTWaiter.wait(for: [closed],timeout: 5),.completed,app.debugDescription)
        mapTool(app, "map-graphics").tap(); app.buttons["choose-graphic-type"].tap()
        let type = app.buttons["draw-graphic-route"]
        for _ in 0..<8 { if type.isHittable { break }; app.swipeUp() }
        type.tap(); XCTAssertTrue(app.buttons["save-graphic"].waitForExistence(timeout: 5))
        settings(app); set("draw",shown: false,in: app); done(app)
        XCTAssertTrue(mapTool(app, "map-graphics").exists); closeMapOptions(app); XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("map-hidden-active-drawing",app); app.buttons["Cancel"].tap()
        XCTAssertFalse(mapTool(app, "map-graphics").exists); XCTAssertFalse(mapTool(app, "map-lanes").exists)
    }
    func testHidingRecordDuringLiveRecordingKeepsStopReachable() {
        let app = launch(), record = app.buttons["record-track"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@","Record track"),object: record)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 10),.completed,app.debugDescription)
        record.tap(); XCTAssertTrue(app.buttons["recording-banner"].waitForExistence(timeout: 8),app.debugDescription)
        settings(app); set("record",shown: false,in: app); done(app)
        XCTAssertTrue(record.isHittable); capture("map-hidden-active-recording",app); record.tap()
        let discard = app.buttons["discard-recording"]
        XCTAssertTrue(discard.waitForExistence(timeout: 8)); discard.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Discard recording"].tap()
        // Hiding the now-idle Record tool removes its sheet owner. Older
        // runtimes dismiss that sheet immediately; others retain Done.
        let panel = app.navigationBars["Track recording"]
        if panel.waitForExistence(timeout: 2) { tapNativeMenuItem(panel.buttons["Done"]) }
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: record)
        XCTAssertEqual(XCTWaiter.wait(for: [finished],timeout: 10),.completed,app.debugDescription)
        XCTAssertFalse(app.buttons["recording-banner"].exists)
        XCTAssertTrue(mapTool(app, "map-button-settings").isHittable)
    }

}
