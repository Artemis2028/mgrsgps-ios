import XCTest

final class PositionQRWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","map"]; app.launch()
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func openWaypointQR() {
        app.buttons["Show all visible data"].tap()
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "map-waypoint-", "Alpha")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10),app.debugDescription); marker.tap()
        let qr = app.buttons["map-waypoint-qr"]; XCTAssertTrue(qr.waitForExistence(timeout: 5))
        // The padding is part of the 44 pt target, even outside the QR glyph.
        qr.coordinate(withNormalizedOffset: .init(dx: 0.1,dy: 0.1)).tap()
        XCTAssertTrue(app.images["position-qr-image"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["position-qr-caption"].label.isEmpty)
    }
    func testCurrentPositionCalloutAndQRFromRealLocation() {
        app.terminate(); app.launchArguments = ["-uiTesting","-startTab","position","-startFace","glance"]; app.launch()
        let qr = app.buttons["position-share-qr"]
        XCTAssertTrue(qr.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: qr)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 20),.completed)
        let callout = app.staticTexts["position-phonetic"]
        XCTAssertTrue(callout.exists); XCTAssertTrue(callout.label.contains(" · "))
        capture("position-phonetic-callout")
        qr.tap(); XCTAssertTrue(app.images["position-qr-image"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["position-qr-caption"].label.isEmpty)
        capture("current-position-qr")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(qr.waitForExistence(timeout: 5))
    }
    func testWaypointQRDayAndNightKeepsMapSelection() {
        openWaypointQR(); capture("waypoint-qr-day")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["map-navigate-waypoint"].waitForExistence(timeout: 5))
        app.buttons["Close waypoint"].tap(); app.buttons["Toggle map night mode"].tap()
        openWaypointQR(); capture("waypoint-qr-night")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["map-navigate-waypoint"].waitForExistence(timeout: 5))
    }
}
