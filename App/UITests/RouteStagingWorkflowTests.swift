import XCTest

final class RouteStagingWorkflowTests: XCTestCase {
    private func launch(night: Bool) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestLibraryWriteFailure","-startTab","waypoints"]
        if night { app.launchArguments += ["-uiTestLibraryWriteFailureNight"] }
        app.launch()
        XCTAssertTrue(app.buttons["open-field-library"].waitForExistence(timeout: 10)); app.buttons["open-field-library"].tap()
        XCTAssertTrue(app.buttons["route-Recon route"].waitForExistence(timeout: 5)); app.buttons["route-Recon route"].tap()
        return app
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<7 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    func testGenerateFailureRetryAndRepeatedGenerationPersistWithoutDuplicates() {
        let app = launch(night: false)
        app.buttons["generate-route-waypoints"].tap()
        XCTAssertTrue(app.staticTexts["route-mutation-error"].waitForExistence(timeout: 10)); capture("route-generation-error-day")
        let repair = app.buttons["route-repair-test-storage"]; reveal(repair,in: app); tapNativeMenuItem(repair)
        let generate = app.buttons["generate-route-waypoints"]
        for _ in 0..<2 {
            for _ in 0..<4 { if generate.isHittable { break }; app.swipeDown() }
            tapNativeMenuItem(generate)
            XCTAssertTrue(app.staticTexts["Route waypoints updated"].waitForExistence(timeout: 10))
        }
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        let search = app.textFields["library-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("RT1WP\n")
        let count = app.staticTexts["library-listed-count"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@","2 waypoints · 0 graphics · 0 tracks"),object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 10),.completed)
        capture("route-generation-persisted-day")
    }
    func testNightFollowFailureStaysOnRouteAndRetryStartsNavigation() {
        let app = launch(night: true)
        app.buttons["follow-route"].tap()
        XCTAssertTrue(app.staticTexts["route-follow-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["follow-route"].exists); XCTAssertFalse(app.buttons["navigation-session-banner"].exists)
        capture("route-follow-error-night")
        let repair = app.buttons["route-repair-test-storage"]; reveal(repair,in: app); tapNativeMenuItem(repair)
        let follow = app.buttons["follow-route"]
        for _ in 0..<4 { if follow.isHittable { break }; app.swipeDown() }
        tapNativeMenuItem(follow)
        XCTAssertTrue(app.staticTexts["route-follow-progress"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["pause-route"].exists); capture("route-follow-retried-night")
        app.terminate()
    }
}
