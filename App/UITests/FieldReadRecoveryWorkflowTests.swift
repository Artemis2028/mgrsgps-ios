import XCTest

final class FieldReadRecoveryWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func gone(_ element: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:element)],timeout:15),.completed)
    }
    private func run(night: Bool,inModal: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestFieldReadRecovery","-uiTestDeferredFieldLoad","-uiTestBoundaryMap","-startTab","waypoints"]
        if night { app.launchArguments.append("-uiTestFieldReadRecoveryNight") }
        app.launch()
        let primaryError = app.staticTexts["field-data-read-error"]
        XCTAssertTrue(primaryError.waitForExistence(timeout:20),app.debugDescription)
        XCTAssertFalse(app.staticTexts["No waypoints yet"].exists,"Unreadable saved data is not an empty library")
        if inModal {
            tapNativeMenuItem(app.buttons["open-field-library"],revealing:app.buttons["field-library-retry"])
        }
        let prefix = inModal ? "field-library" : "field-data"
        let warning = app.staticTexts[prefix + "-read-error"]
        let retry = app.buttons[prefix + "-retry"]
        XCTAssertTrue(warning.waitForExistence(timeout:10)); XCTAssertTrue(retry.isHittable)
        capture(night ? "field-read-failure-night" : "field-read-failure-day")
        tapNativeMenuItem(retry)
        XCTAssertTrue(warning.waitForExistence(timeout:15)); XCTAssertTrue(retry.waitForExistence(timeout:15))
        XCTAssertFalse(app.buttons["route-Recovered CAFÉ route"].exists)
        tapNativeMenuItem(app.buttons[prefix + "-test-repair"])
        let repaired = app.staticTexts[prefix + "-test-repair-status"]
        XCTAssertTrue(repaired.waitForExistence(timeout:5)); XCTAssertEqual(repaired.label,"Synthetic source repaired")
        XCTAssertTrue(warning.exists,"Repairing source alone must not publish a library")
        tapNativeMenuItem(retry); gone(warning)
        if !inModal {
            XCTAssertTrue(app.buttons["library-graphic-Recovered CAFÉ route"].waitForExistence(timeout:15))
            tapNativeMenuItem(app.buttons["open-field-library"],revealing:app.buttons["route-Recovered CAFÉ route"])
        }
        let route = app.buttons["route-Recovered CAFÉ route"],track = app.buttons["track-Recovered patrol"]
        XCTAssertTrue(route.waitForExistence(timeout:15)); XCTAssertTrue(track.waitForExistence(timeout:10))
        capture(night ? "field-read-recovered-night" : "field-read-recovered-day")
        tapNativeMenuItem(track)
        XCTAssertTrue(app.staticTexts["2 points"].waitForExistence(timeout:10),"The original point log must remain readable")
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        XCTAssertTrue(app.buttons["open-field-library"].waitForExistence(timeout:20))
        XCTAssertFalse(primaryError.exists)
        tapNativeMenuItem(app.buttons["open-field-library"],revealing:route)
        XCTAssertTrue(route.waitForExistence(timeout:10)); XCTAssertTrue(track.waitForExistence(timeout:10))
    }
    func testEmptyLibraryFailureAndExplicitRetryRecoverRoutesAndTrackInDay() { run(night:false,inModal:false) }
    func testModalFailureAndExplicitRetryRecoverRoutesAndTrackAtNight() { run(night:true,inModal:true) }
}
