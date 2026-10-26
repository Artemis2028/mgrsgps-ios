import XCTest

final class NavigationTargetWorkflowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func launch(_ tab: String,night: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestLibraryWriteFailure","-uiTestTargetSelection","-startTab",tab]
        if night { app.launchArguments += ["-uiTestLibraryWriteFailureNight"] }
        app.launch(); return app
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testMapSelectionFailureKeepsCardAndShowsReadableError() {
        let app = launch("map")
        XCTAssertTrue(app.buttons["Show all visible data"].waitForExistence(timeout: 10)); app.buttons["Show all visible data"].tap()
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@","map-waypoint-","Selection target")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10)); tapNativeMenuItem(marker)
        let navigate = app.buttons["map-navigate-waypoint"]
        XCTAssertTrue(navigate.waitForExistence(timeout: 5)); navigate.tap()
        XCTAssertTrue(app.staticTexts["map-target-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(navigate.exists); capture("map-navigation-target-save-error-day")
    }
    func testNightPickerAndClearFailuresKeepCurrentTargetVisible() {
        let app = launch("navigate",night: true)
        let picker = app.buttons["Choose navigation target"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        tapNativeMenuItem(app.buttons["Charlie"])
        XCTAssertTrue(app.staticTexts["navigation-target-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Alpha"].exists); capture("navigation-target-save-error-night")
        let stop = app.buttons["stop-navigation"]
        for _ in 0..<6 { if stop.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(stop.isHittable,app.debugDescription); stop.tap()
        XCTAssertTrue(app.staticTexts["navigation-target-error"].waitForExistence(timeout: 10))
        for _ in 0..<6 { if picker.isHittable { break }; app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(app.staticTexts["Alpha"].exists); capture("navigation-target-clear-error-night")
    }
}
