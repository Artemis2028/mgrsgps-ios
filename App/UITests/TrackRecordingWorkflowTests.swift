import XCTest

/// Requires a moving simulator location route (CI configures it before tests).
/// This exercises real Core Location delivery, not an injected app location feed.
final class TrackRecordingWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-startTab", "map"]
        app.launch()
    }
    private func waitFor(_ predicate: NSPredicate, on element: XCUIElement, timeout: Double = 20) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, app.debugDescription)
    }
    private func begin() {
        let record = app.buttons["record-track"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        waitFor(NSPredicate(format: "label == %@", "Record track"), on: record)
        record.tap()
        let banner = app.buttons["recording-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        // simctl can spend up to 20 seconds in a location delivery under the
        // hosted workload. Still require a real accepted point before recovery.
        waitFor(NSPredicate(format: "label MATCHES %@", ".*Recording · [1-9][0-9]* points.*"), on: banner, timeout: 45)
        XCTAssertTrue(banner.isHittable, app.debugDescription + XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)
    }
    private func pointCount() -> Int {
        let count = app.staticTexts["recording-point-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5), app.debugDescription)
        return Int(count.label.split(separator: " ").first ?? "") ?? 0
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func backgroundReceipt(_ token: String,phase: String) throws -> [String:Any] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("recording-background-\(token)-\(phase).json")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in FileManager.default.fileExists(atPath: file.path) },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 15),.completed,"Host observer must confirm the actual journal while the app stays backgrounded")
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String:Any])
        XCTAssertEqual(value["status"] as? String,"ok","Background journal receipt: \(value)")
        try? FileManager.default.removeItem(at: file)
        return value
    }

    func testLiveRecordingReceivesBackgroundLocationsThenSavesToLibraryAndMap() throws {
        begin()
        app.buttons["recording-banner"].tap()
        let before = pointCount()
        XCTAssertGreaterThan(before, 0)
        app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home)
        let token = UUID().uuidString
        print("RECORDING_BACKGROUND_CHECK_BEGIN \(token)")
        _ = try backgroundReceipt(token,phase: "begin")
        // The host reads the real journal before we may reactivate the app.
        Thread.sleep(forTimeInterval: 8)
        print("RECORDING_BACKGROUND_CHECK_END \(token)")
        let background = try backgroundReceipt(token,phase: "end")
        XCTAssertEqual(background["sameSession"] as? Bool,true)
        XCTAssertGreaterThan(try XCTUnwrap(background["after"] as? Int),try XCTUnwrap(background["before"] as? Int),"Accepted points must reach disk while the app is still backgrounded")
        app.activate()
        // activate() can return before the foreground transition's hit-testing
        // regions are ready, even though the existing banner is in the AX tree.
        waitFor(NSPredicate(format: "hittable == true"), on: app.buttons["recording-banner"], timeout: 5)
        app.buttons["recording-banner"].tap()
        let after = pointCount()
        XCTAssertGreaterThan(after, before, "No accepted Core Location fixes while app was backgrounded")
        capture("live-recording-after-background")
        let name = app.textFields["recording-name"]
        name.tap(); name.typeText("Background patrol")
        app.buttons["save-recording"].tap()
        waitFor(NSPredicate(format: "exists == false"), on: app.buttons["save-recording"])
        XCTAssertTrue(app.staticTexts["Track saved in Routes & tracks"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Waypoints"].tap()
        app.buttons["open-field-library"].tap()
        let track = app.buttons["track-Background patrol"]
        XCTAssertTrue(track.waitForExistence(timeout: 5)); track.tap()
        XCTAssertTrue(app.buttons["Export GPX"].waitForExistence(timeout: 5))
        capture("recorded-track-details")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["Done"].tap()
        app.tabBars.buttons["Map"].tap()
        XCTAssertEqual(app.staticTexts["map-field-overlays"].label, "0 routes · 1 tracks")
        app.buttons["Show all visible data"].tap()
        capture("recorded-track-map")
    }

    func testRelaunchRecoversRecordingWithoutResumingLocationLogging() {
        begin()
        app.terminate()
        app.launchArguments += ["-keepUITestData","-uiTestDeferredFieldLoad"]
        app.launch()
        waitFor(NSPredicate(format: "label == %@", "Record track"), on: app.buttons["record-track"])
        let banner = app.buttons["recording-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.contains("Recovered interrupted recording"))
        capture("recovered-recording")
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["open-field-library"].tap()
        let track = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "track-Track ")).firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
    }

    func testDiscardRequiresConfirmationAndCreatesNoSavedTrack() {
        begin()
        app.buttons["recording-banner"].tap()
        app.buttons["discard-recording"].tap()
        app.alerts.buttons["Keep recording"].tap()
        XCTAssertTrue(app.buttons["save-recording"].exists)
        app.buttons["discard-recording"].tap()
        app.alerts.buttons["Discard recording"].tap()
        XCTAssertTrue(app.staticTexts["Recording discarded"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["open-field-library"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "track-Track ")).firstMatch.exists)
    }
}
