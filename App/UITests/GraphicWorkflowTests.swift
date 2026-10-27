import XCTest

final class GraphicWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","map"]; app.launch()
    }
    private func choose(_ type: String) {
        let open = app.buttons["map-graphics"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        app.buttons["choose-graphic-type"].tap()
        let button = app.buttons["draw-graphic-\(type)"]
        for _ in 0..<8 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.buttons["save-graphic"].waitForExistence(timeout: 5))
    }
    private func point(_ dx: CGFloat,_ dy: CGFloat,_ count: Int) {
        app.coordinate(withNormalizedOffset: .init(dx: dx,dy: dy)).tap()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","\(count) points"),object: app.staticTexts["graphic-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation],timeout: 5),.completed)
    }
    private func saveGraphic() {
        let save = app.buttons["save-graphic"]
        save.tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [finished],timeout: 10),.completed,app.debugDescription)
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testDrawRouteInsertKinkDragSaveEditAndPersist() {
        choose("route"); point(0.25,0.40,1); point(0.65,0.40,2); point(0.65,0.53,3)
        let handle = app.buttons["graphic-midpoint-0"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5,dy: 0.5)).press(forDuration: 0.8,thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.42,dy: 0.45)))
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","4 points"),object: app.staticTexts["graphic-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [added],timeout: 5),.completed)
        XCTAssertFalse(app.buttons["Insert kink"].exists)
        for destination in [CGVector(dx:0.47,dy:0.47),CGVector(dx:0.40,dy:0.43)] {
            let coordinate = app.staticTexts["graphic-selected-coordinate"]
            XCTAssertTrue(coordinate.waitForExistence(timeout:5)); let before = coordinate.label
            app.buttons["graphic-point-1"].coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.5)).press(forDuration:0.8,thenDragTo:app.coordinate(withNormalizedOffset:destination))
            let moved = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label != %@",before),object:coordinate)
            XCTAssertEqual(XCTWaiter.wait(for:[moved],timeout:5),.completed,app.debugDescription)
            XCTAssertTrue(app.staticTexts["graphic-point-count"].label.hasPrefix("4 points"))
        }
        capture("map-route-drawing")
        saveGraphic()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 5),app.debugDescription)
        capture("route-navigation-waypoint-offer"); app.buttons["Not now"].tap()
        app.coordinate(withNormalizedOffset: .init(dx: 0.40,dy: 0.43)).tap()
        XCTAssertTrue(app.buttons["save-graphic"].waitForExistence(timeout: 5), "Tapping a saved route opens its map editor")
        app.buttons["Cancel"].tap(); app.buttons["map-graphics"].tap()
        XCTAssertTrue(app.staticTexts["Route · 4 points · Base"].waitForExistence(timeout: 5))
        app.buttons["edit-graphic-Route"].tap()
        XCTAssertTrue(app.staticTexts["graphic-point-count"].label.contains("4 points"))
        app.buttons["graphic-details"].tap()
        let name = app.textFields["graphic-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        let old = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: old.count)+"Patrol route")
        app.buttons["Done"].tap(); saveGraphic()
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        app.buttons["map-graphics"].tap()
        XCTAssertTrue(app.buttons["edit-graphic-Patrol route"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["stop-boundary"].exists)
        capture("map-graphic-library")
    }
    func testRouteCanSnapToExistingWaypointMarker() {
        app.buttons["Add waypoint at map centre"].tap()
        let name = app.textFields["waypoint-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Start point")
        app.buttons["waypoint-save"].tap()
        choose("route")
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@","map-waypoint-")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5)); marker.tap()
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","1 points"),object: app.staticTexts["graphic-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [added],timeout: 5),.completed)
        point(0.65,0.40,2); saveGraphic()
        XCTAssertTrue(app.buttons["Generate waypoints"].waitForExistence(timeout: 5)); app.buttons["Generate waypoints"].tap()
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["open-field-library"].tap()
        XCTAssertTrue(app.buttons["route-Route"].waitForExistence(timeout: 5))
        app.buttons["route-Route"].tap()
        XCTAssertTrue(app.buttons["follow-route"].waitForExistence(timeout: 5))
    }
    func testLongPressOnRouteSegmentCreatesAndDragsBendDirectly() {
        choose("route"); point(0.25,0.40,1); point(0.65,0.40,2)
        // Away from both numbered endpoints and the midpoint + handle.
        app.coordinate(withNormalizedOffset: .init(dx: 0.34,dy: 0.40)).press(forDuration: 0.8,thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.34,dy: 0.49)))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","3 points"),object: app.staticTexts["graphic-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed],timeout: 5),.completed)
        capture("route-direct-line-drag")
        saveGraphic(); app.buttons["Not now"].tap()
        app.buttons["map-graphics"].tap()
        XCTAssertTrue(app.staticTexts["Route · 3 points · Base"].waitForExistence(timeout: 5))
    }
    func testFixedRingAndSectorPlacementAndNightControls() {
        choose("ring"); point(0.40,0.40,1)
        app.coordinate(withNormalizedOffset: .init(dx: 0.65,dy: 0.48)).tap()
        XCTAssertTrue(app.textFields["graphic-name"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap(); XCTAssertTrue(app.buttons["save-graphic"].isEnabled); saveGraphic()
        choose("sector"); point(0.30,0.50,1); point(0.50,0.35,2)
        app.coordinate(withNormalizedOffset: .init(dx: 0.65,dy: 0.55)).tap()
        XCTAssertTrue(app.textFields["graphic-name"].waitForExistence(timeout: 5)); app.buttons["Done"].tap(); saveGraphic()
        app.buttons["Toggle map night mode"].tap()
        XCTAssertTrue(app.buttons["Draw graphics and routes"].isHittable)
        XCTAssertTrue(app.buttons["Add waypoint at map centre"].isHittable)
        capture("range-ring-sector-night")
        app.buttons["map-graphics"].tap()
        XCTAssertTrue(app.staticTexts["Range ring · 2 points · Base"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sector of fire · 3 points · Base"].exists)
    }
    func testDrawTacticalBoundaryDoesNotStartPerimeterMonitoring() {
        choose("boundary"); point(0.25,0.40,1); point(0.65,0.40,2)
        XCTAssertTrue(app.staticTexts["Draw an open tactical boundary line. This graphic does not monitor crossings."].exists)
        saveGraphic()
        XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
        app.buttons["map-graphics"].tap(); XCTAssertTrue(app.staticTexts["Boundary · 2 points · Base"].waitForExistence(timeout: 5))
        capture("tactical-boundary-line")
    }
}
