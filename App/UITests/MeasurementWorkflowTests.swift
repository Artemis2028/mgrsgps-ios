import XCTest

final class MeasurementWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","map"]; app.launch()
    }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }
    private func choose(_ id: String) {
        let menu = mapTool(app, "map-measure"); XCTAssertTrue(menu.waitForExistence(timeout: 10)); tapNativeMenuItem(menu)
        tapNativeMenuItem(app.buttons[id])
        let ready = id == "measure-area" ? app.buttons["measurement-done"] : app.staticTexts["ruler-distance"]
        XCTAssertTrue(ready.waitForExistence(timeout: 8),app.debugDescription)
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func points(_ count: Int) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","\(count) points"),object: app.staticTexts["graphic-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 5),.completed)
    }
    private func tap(_ x: CGFloat,_ y: CGFloat) { app.coordinate(withNormalizedOffset: .init(dx: x,dy: y)).tap() }
    func testRulerTapPanResetAndNightModeStaySeparateFromMonitoring() {
        choose("measure-distance")
        let distance = app.staticTexts["ruler-distance"]; XCTAssertTrue(distance.waitForExistence(timeout: 5))
        XCTAssertEqual(distance.label,"0 m")
        tap(0.25,0.42)
        let away = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@","0 m"),object: distance)
        XCTAssertEqual(XCTWaiter.wait(for: [away],timeout: 5),.completed)
        let before = distance.label
        app.coordinate(withNormalizedOffset: .init(dx: 0.50,dy: 0.48)).press(forDuration: 0.1,thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.35,dy: 0.48)))
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@",before),object: distance)
        XCTAssertEqual(XCTWaiter.wait(for: [moved],timeout: 5),.completed)
        XCTAssertTrue(app.staticTexts["ruler-bearings"].label.contains("BACK")); capture("map-ruler-day")
        mapTool(app, "Toggle map night mode").tap(); closeMapOptions(app); capture("map-ruler-night")
        app.buttons["ruler-reset"].tap()
        XCTAssertEqual(distance.label,"0 m")
        app.buttons["ruler-done"].tap(); XCTAssertFalse(distance.exists)
        XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
        mapTool(app, "map-graphics").tap(); XCTAssertTrue(app.staticTexts["No graphics saved"].waitForExistence(timeout: 5))
    }
    func testMeasureEditUndoAndSaveAsAreaGraphic() {
        choose("measure-area"); tap(0.25,0.39); points(1); tap(0.65,0.39); points(2)
        XCTAssertFalse(app.buttons["measurement-results"].isEnabled)
        tap(0.50,0.54); points(3)
        XCTAssertTrue(app.staticTexts["measurement-area"].exists)
        app.buttons["measurement-undo"].tap(); points(2); tap(0.50,0.54); points(3)
        let handle = app.buttons["graphic-midpoint-0"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5,dy: 0.5)).press(forDuration: 0.8,thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.42,dy: 0.44)))
        points(4); capture("map-area-editing")
        app.buttons["measurement-results"].tap()
        XCTAssertTrue(app.buttons["measurement-save-area"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["measurement-result-area"].label,"0 m²")
        capture("map-area-results")
        app.buttons["Keep measuring"].tap(); points(4)
        app.buttons["measurement-results"].tap(); app.buttons["measurement-save-area"].tap()
        let name = app.textFields["graphic-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: (name.value as? String ?? "").count)+"Training area")
        app.buttons["Done"].tap(); app.buttons["save-graphic"].tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: app.buttons["save-graphic"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved],timeout: 10),.completed,app.debugDescription)
        XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        mapTool(app, "map-graphics").tap()
        XCTAssertTrue(app.buttons["edit-graphic-Training area"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Area (sketch) · 4 points · Base"].exists)
    }
    func testDoneDiscardsTemporaryAreaWithoutSavingGraphic() {
        choose("measure-area"); tap(0.25,0.40); points(1); tap(0.65,0.40); points(2); tap(0.50,0.54); points(3)
        app.buttons["measurement-done"].tap()
        mapTool(app, "map-graphics").tap(); XCTAssertTrue(app.staticTexts["No graphics saved"].waitForExistence(timeout: 5))
    }
    func testLandscapeKeepsRulerAndAreaActionsReachable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        choose("measure-distance"); tap(0.40,0.35)
        let distance = app.staticTexts["ruler-distance"]
        let away = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@","0 m"),object: distance)
        XCTAssertEqual(XCTWaiter.wait(for: [away],timeout: 5),.completed)
        XCTAssertTrue(app.buttons["ruler-reset"].isHittable); XCTAssertTrue(app.buttons["ruler-done"].isHittable)
        capture("map-ruler-landscape"); app.buttons["ruler-done"].tap()
        let map = app.otherElements.matching(NSPredicate(format:"label == %@ AND value BEGINSWITH %@","Map","Zoom ")).firstMatch
        XCTAssertTrue(map.exists,app.debugDescription)
        // MapLibre adds annotation counts to this value as corners appear.
        // Compare the complete zoom token, including any fractional level.
        func zoomReadout() -> String { String((map.value as? String ?? "").prefix { $0 != "x" }) }
        let zoomBefore = zoomReadout()
        choose("measure-area"); tap(0.25,0.36); tap(0.58,0.36); tap(0.40,0.50)
        capture("map-area-landscape-before-results")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: app.buttons["measurement-results"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 5),.completed,app.debugDescription)
        XCTAssertEqual(zoomReadout(),zoomBefore,"Rapid drawing taps must not zoom the map")
        XCTAssertTrue(app.buttons["measurement-results"].isHittable)
        capture("map-area-landscape"); app.buttons["measurement-done"].tap()
        app.coordinate(withNormalizedOffset:.init(dx:0.70,dy:0.50)).doubleTap()
        let zoomed = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in zoomReadout() != zoomBefore },object:map)
        XCTAssertEqual(XCTWaiter.wait(for:[zoomed],timeout:8),.completed,"Double-tap zoom must return after drawing ends")
    }
}
