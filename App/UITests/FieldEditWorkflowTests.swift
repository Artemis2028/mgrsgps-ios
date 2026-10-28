import XCTest

final class FieldEditWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","map"]; app.launch()
        XCTAssertTrue(mapTool(app, "Toggle map night mode").waitForExistence(timeout: 10)); mapTool(app, "Toggle map night mode").tap()
    }
    private func value(_ toggle: XCUIElement,_ value: String) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@",value),object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation],timeout: 10),.completed,app.debugDescription)
    }
    private func gone(_ element: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: element)],timeout: 10),.completed,app.debugDescription)
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable,app.debugDescription)
    }
    private func library() {
        app.buttons["Waypoints"].tap()
        let open = app.buttons["open-field-library"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func relaunch() { app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch() }

    func testRouteEditVisibilityDeleteAndRelaunchInNightMode() {
        library(); app.buttons["route-Recon route"].tap(); app.buttons["Edit route"].tap()
        let name = app.textFields["route-name"]; XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); replaceTextInput(name,"Night patrol"); XCTAssertEqual(name.value as? String,"Night patrol")
        app.buttons["save-route"].tap(); gone(app.buttons["save-route"])
        XCTAssertTrue(app.navigationBars["Night patrol"].waitForExistence(timeout: 10))
        let visibility = app.switches["Visible on map"]
        value(visibility,"1"); visibility.coordinate(withNormalizedOffset: .init(dx: 0.9,dy: 0.5)).tap(); value(visibility,"0")
        capture("field-route-edited-hidden-night")
        relaunch(); library()
        XCTAssertTrue(app.buttons["route-Night patrol"].waitForExistence(timeout: 10)); app.buttons["route-Night patrol"].tap()
        value(app.switches["Visible on map"],"0")
        let delete = app.buttons["Delete route"]; reveal(delete); delete.tap()
        XCTAssertTrue(app.navigationBars["Routes & tracks"].waitForExistence(timeout: 10))
        gone(app.buttons["route-Night patrol"]); capture("field-route-deleted-night")
        relaunch(); library(); XCTAssertFalse(app.buttons["route-Night patrol"].exists)
        XCTAssertTrue(app.buttons["track-Recon track"].exists)
    }

    func testGraphicPanelVisibilityDeleteAndTrackDeletionPersistInNightMode() {
        mapTool(app, "map-graphics").tap()
        let visibility = app.switches["graphic-visible-Recon route"]
        reveal(visibility); value(visibility,"1"); visibility.coordinate(withNormalizedOffset: .init(dx: 0.9,dy: 0.5)).tap(); value(visibility,"0")
        capture("field-graphic-hidden-night")
        let deleteGraphic = app.buttons["Delete graphic Recon route"]; reveal(deleteGraphic); deleteGraphic.tap()
        let alert = app.alerts.firstMatch; XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Delete"].tap()
        gone(visibility); app.navigationBars["Graphics & routes"].buttons["Done"].tap()
        library(); app.buttons["track-Recon track"].tap()
        let trackVisibility = app.switches["Visible on map"]
        value(trackVisibility,"1"); trackVisibility.coordinate(withNormalizedOffset: .init(dx: 0.9,dy: 0.5)).tap(); value(trackVisibility,"0")
        capture("field-track-hidden-night")
        app.buttons["Delete track"].tap(); XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["Routes & tracks"].waitForExistence(timeout: 10))
        gone(app.buttons["track-Recon track"])
        relaunch(); library()
        XCTAssertFalse(app.buttons["track-Recon track"].exists); XCTAssertFalse(app.buttons["route-Recon route"].exists)
        capture("field-graphic-track-deleted-night")
    }
}
