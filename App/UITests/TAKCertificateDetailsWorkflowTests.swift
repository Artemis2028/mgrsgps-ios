import XCTest

final class TAKCertificateDetailsWorkflowTests: XCTestCase {
    private func run(night: Bool,expired: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestTAKCertificateDetails","-startTab","map"]
        if night { app.launchArguments.append("-uiTestTAKEnrollmentNight") }
        if expired { app.launchArguments.append("-uiTestTAKCertificateExpired") }
        app.launch()
        let server = mapStatusButton(app, "map-tak")
        XCTAssertTrue(server.waitForExistence(timeout: 12)); server.tap()
        let details = app.buttons["tak-certificate-details"]
        reveal(details,in: app); details.tap()
        let expiry = app.staticTexts["tak-client-certificate-expiry"]
        reveal(expiry,in: app)
        XCTAssertTrue(expiry.label.contains("UTC"))
        let status = app.staticTexts["tak-client-certificate-status"]
        XCTAssertTrue(status.label.contains(expired ? "Expired" : "30 days"))
        capture(night ? "tak-client-certificate-night" : "tak-client-certificate-day",app)
        let beforeRenewal = app.staticTexts["tak-status"].label
        XCTAssertEqual(beforeRenewal,"Synthetic certificate preview · no connection")
        let renew = app.buttons["tak-renew-certificate"]
        reveal(renew,in: app); renew.tap()
        let host = app.textFields["tak-enroll-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5)); XCTAssertEqual(host.value as? String,"127.0.0.1")
        XCTAssertFalse(host.isEnabled)
        XCTAssertFalse(app.textFields["tak-enroll-port"].isEnabled)
        XCTAssertFalse(app.textFields["tak-enroll-stream-port"].isEnabled)
        XCTAssertFalse(app.secureTextFields["tak-enroll-link"].exists)
        XCTAssertEqual(app.textFields["tak-enroll-port"].value as? String,"8446")
        XCTAssertEqual(app.textFields["tak-enroll-stream-port"].value as? String,"8089")
        XCTAssertFalse(app.secureTextFields["tak-enroll-password"].exists)
        capture(night ? "tak-renewal-prefill-night" : "tak-renewal-prefill-day",app)
        app.buttons["tak-enroll-cancel"].tap()
        XCTAssertTrue(app.buttons["tak-renew-certificate"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tak-status"].label,beforeRenewal)
        XCTAssertEqual(app.switches["tak-share-position"].value as? String,"0")
    }
    func testExpiringClientCertificateAndCancelledRenewalInDay() { run(night: false,expired: false) }
    func testExpiredClientCertificateAndCancelledRenewalAtNight() { run(night: true,expired: true) }
    private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.frame.maxY+12, bottom = app.frame.maxY-60
            if element.exists {
                let frame = element.frame
                if element.isHittable,frame.minY >= top,frame.maxY <= bottom { return }
                if frame.minY < top { app.scrollViews.firstMatch.swipeDown(); continue }
            }
            // A continuous scroll gesture avoids a press beginning on Connect.
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTFail("Certificate control did not become visible: \(element.identifier)")
    }
    private func capture(_ name: String,_ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
