import XCTest

/// Run with scripts/fix-freshness-test.py, separately from continuous route feeds.
final class PositionFixWorkflowTests: XCTestCase {
    private func signal(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
    func testRealFixAgesIntoStaleWithoutNewSamplesAndRecovers() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-startTab","position","-startFace","glance"]
        app.launch()
        let qr = app.buttons["position-share-qr"], quality = app.staticTexts["position-fix-quality"]
        XCTAssertTrue(qr.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in qr.isEnabled && quality.label == "EXCELLENT" },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 25),.completed)
        let grid = app.staticTexts["position-phonetic"].label
        XCTAssertFalse(grid.isEmpty)
        signal("GRIDFIX_FRESHNESS_READY")
        let navigationExpired = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"),object: qr)
        XCTAssertEqual(XCTWaiter.wait(for: [navigationExpired],timeout: 18),.completed)
        let stale = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@","STALE"),object: quality)
        XCTAssertEqual(XCTWaiter.wait(for: [stale],timeout: 28),.completed)
        XCTAssertTrue(app.staticTexts["position-fix-age"].label.contains("wait for a fresh fix"))
        XCTAssertEqual(app.staticTexts["position-phonetic"].label,grid,"Retained grid must be labeled old, not silently replaced")
        XCTAssertFalse(qr.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "position-real-stale-fix"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Settings"].tap()
        let night = app.switches["Red-on-black, to keep night vision"]
        XCTAssertTrue(night.waitForExistence(timeout: 5)); night.tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(quality.label,"STALE")
        let nightShot = XCTAttachment(screenshot: app.screenshot()); nightShot.name = "position-real-stale-night"; nightShot.lifetime = .keepAlways; add(nightShot)
        let details = app.scrollViews["position-details"]
        for _ in 0..<3 { if app.staticTexts["DTG"].isHittable { break }; details.swipeUp() }
        XCTAssertTrue(app.staticTexts["DTG"].isHittable,"Night bar must not trap the last readouts below the screen")
        signal("GRIDFIX_FRESHNESS_RESUME")
        let recovered = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in qr.isEnabled && quality.label == "EXCELLENT" },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [recovered],timeout: 20),.completed)
        XCTAssertFalse(app.staticTexts["position-fix-age"].label.contains("wait for a fresh fix"))
        app.buttons["Navigate"].tap()
        app.buttons["Choose navigation target"].tap()
        tapNativeMenuItem(app.buttons["Alpha"].firstMatch)
        // No magnetometer is simulated: never synthesize a north-pointing arrow.
        XCTAssertTrue(app.staticTexts["display-heading-unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["display-relative-navigation"].exists)
        signal("GRIDFIX_FRESHNESS_DONE")
    }
}
