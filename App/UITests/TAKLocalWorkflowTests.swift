import XCTest

final class TAKLocalWorkflowTests: XCTestCase {
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reach(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    func testLocalAndroidTeammateAndExplicitCertificateApproval() throws {
        // Opt-in only: this test needs a credential ZIP staged outside the repo.
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestTAKLocal", "-startTab", "map"]
        app.launch()
        let open = app.buttons["map-tak"]
        XCTAssertTrue(open.waitForExistence(timeout: 20)); open.tap()
        let load = app.buttons["tak-local-validation"]
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        guard app.staticTexts["tak-local-fixture-ready"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Local TAK UI validation requires a package explicitly staged in this simulator app")
        }
        load.tap()
        let connect = app.buttons["tak-connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15)); reach(connect, app: app, up: false); connect.tap()
        let review = app.staticTexts["Server name does not match"]
        XCTAssertTrue(review.waitForExistence(timeout: 25), app.debugDescription)
        let trust = app.buttons["tak-trust-certificate"]
        reach(trust, app: app); capture("tak-native-certificate-review"); trust.tap()
        let status = app.staticTexts["tak-status"]
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Connected"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 25), .completed, app.debugDescription)
        let share = app.switches["tak-share-position"]
        reach(share, app: app, up: false)
        XCTAssertEqual(share.value as? String, "0", "Position sharing must start off")
        share.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap()
        let android = app.staticTexts["MGRS-ADA5"]
        XCTAssertTrue(android.waitForExistence(timeout: 35), app.debugDescription)
        reach(android, app: app); capture("tak-android-contact-on-ios")
        let uid = app.staticTexts["tak-device-uid"]
        reach(uid, app: app); print("TAK local validation uid: \(uid.label)")
        let show = app.buttons["Show on map"].firstMatch
        reach(show, app: app, up: false); show.tap()
        XCTAssertTrue(app.buttons["map-tak"].waitForExistence(timeout: 8))
        capture("tak-android-contact-native-map")
        // Leave the real native session running briefly for the Android peer's
        // independently observed capture. No simulated server or fake UI result.
        let hold = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
        _ = XCTWaiter.wait(for: [hold], timeout: 60)
    }
}
