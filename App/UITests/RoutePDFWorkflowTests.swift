import XCTest

final class RoutePDFWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","waypoints"]; app.launch()
    }
    private func openRoute() {
        let open = app.buttons["open-field-library"]; XCTAssertTrue(open.waitForExistence(timeout: 8)); open.tap()
        let route = app.buttons["route-Recon route"]; XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
    }
    private func preview() {
        let export = app.buttons["prepare-strip-map-pdf"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: export)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 10),.completed)
        export.tap(); XCTAssertTrue(app.navigationBars["Strip map PDF"].waitForExistence(timeout: 12),app.debugDescription)
    }
    private func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
    func testRouteCardPDFPreviewNativeSaveAndOriginalRoutePersists() {
        openRoute(); preview(); capture("strip-map-pdf-preview")
        let share = app.buttons["share-strip-map-pdf"]; XCTAssertTrue(share.exists)
        share.tap()
        let activity = app.otherElements["ActivityListView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10),app.debugDescription)
        capture("strip-map-system-share")
        // ActivityListView describes the action rows, not the outer popover.
        // Tapping above that subview can still land inside the popover.
        app.coordinate(withNormalizedOffset: .init(dx: 0.5,dy: 0.9)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: activity)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed],timeout: 8),.completed)
        XCTAssertTrue(app.buttons["export-strip-map-pdf"].waitForExistence(timeout: 5))
        app.buttons["export-strip-map-pdf"].tap()
        let name = app.textFields["DOCPicker.filenameTextField"]; XCTAssertTrue(name.waitForExistence(timeout: 10),app.debugDescription)
        let filename = "gridfix-pdf-ui-"+UUID().uuidString.prefix(8)
        replaceTextInput(name,String(filename))
        XCTAssertEqual(name.value as? String,String(filename))
        saveNativeFile(in: app)
        XCTAssertTrue(app.navigationBars["Strip map PDF"].waitForExistence(timeout: 10)); capture("strip-map-pdf-after-save")
        app.navigationBars["Strip map PDF"].buttons["Done"].tap()
        let total = app.staticTexts["route-card-total"]
        for _ in 0..<5 { if total.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(total.waitForExistence(timeout: 5)); XCTAssertTrue(total.label.contains("paces")); capture("route-card-total-and-notes")
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        openRoute(); XCTAssertTrue(app.buttons["prepare-strip-map-pdf"].waitForExistence(timeout: 8))
    }
    func testNightRouteCardKeepsControlsReadableAndSharesText() {
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        openRoute()
        XCTAssertTrue(app.buttons["share-route-card"].waitForExistence(timeout: 10))
        capture("route-card-night")
        preview(); XCTAssertTrue(app.buttons["share-strip-map-pdf"].exists); XCTAssertTrue(app.buttons["export-strip-map-pdf"].exists)
        capture("strip-map-preview-night-controls")
        app.navigationBars["Strip map PDF"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["share-route-card"].waitForExistence(timeout: 5))
    }
}
