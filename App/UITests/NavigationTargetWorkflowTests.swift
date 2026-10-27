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
    func testTargetChoiceCancelSaveAndRelaunchInDayAndNight() {
        for night in [false,true] {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestTargetSelection","-startTab",night ? "position" : "navigate"]
            app.launch()
            if night {
                app.buttons["Settings"].tap()
                let toggle = app.switches["Red-on-black, to keep night vision"]
                XCTAssertTrue(toggle.waitForExistence(timeout:5)); setNativeSwitch(toggle,to:true)
                app.buttons["Done"].tap(); app.buttons["Navigate"].tap()
            }
            let target = app.staticTexts["navigation-target-name"]
            XCTAssertTrue(target.waitForExistence(timeout:10)); XCTAssertEqual(target.label,"Alpha")
            let picker = app.buttons["Choose navigation target"]
            picker.tap()
            let sheet = app.navigationBars["Navigation target"]
            XCTAssertTrue(sheet.waitForExistence(timeout:5))
            XCTAssertTrue(app.buttons["Charlie"].exists)
            sheet.buttons["Cancel"].tap()
            let cancelled = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:sheet)
            XCTAssertEqual(XCTWaiter.wait(for:[cancelled],timeout:5),.completed)
            XCTAssertEqual(target.label,"Alpha","Cancel must keep the saved target")
            picker.tap(); tapNativeMenuItem(app.buttons["Charlie"])
            let chosen = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Charlie"),object:target)
            XCTAssertEqual(XCTWaiter.wait(for:[chosen],timeout:10),.completed,app.debugDescription)
            XCTAssertFalse(sheet.exists)
            capture(night ? "navigation-target-choice-night" : "navigation-target-choice-day")
            app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
            if night { app.buttons["Navigate"].tap() }
            XCTAssertTrue(target.waitForExistence(timeout:10)); XCTAssertEqual(target.label,"Charlie")
            app.terminate()
        }
    }
    func testMilitaryTargetAppearsInChooserAndNavigationInNightMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestWatch","-uiTestWatchMap","-startTab","position"]
        app.launch(); app.buttons["Settings"].tap()
        let night = app.switches["Red-on-black, to keep night vision"]
        XCTAssertTrue(night.waitForExistence(timeout:5)); setNativeSwitch(night,to:true)
        app.buttons["Done"].tap(); app.buttons["Navigate"].tap()
        app.buttons["Choose navigation target"].tap()
        let point = app.buttons["SYNTHETIC INF"]
        XCTAssertTrue(point.waitForExistence(timeout:5))
        XCTAssertTrue((point.value as? String ?? "").lowercased().contains("friendly"))
        XCTAssertTrue((point.value as? String ?? "").lowercased().contains("infantry"))
        capture("navigation-target-symbol-chooser-night")
        tapNativeMenuItem(point)
        let selected = app.staticTexts["navigation-target-name"]
        let changed = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","SYNTHETIC INF"),object:selected)
        XCTAssertEqual(XCTWaiter.wait(for:[changed],timeout:10),.completed)
        XCTAssertFalse(app.navigationBars["Navigation target"].exists)
        XCTAssertTrue(app.images["navigation-target-symbol"].exists)
        XCTAssertEqual(app.staticTexts["navigation-target-grid"].label,"40R BN 34228 07099",
                       "Display the grouped written grid, as Android does, rather than its machine form")
        capture("navigation-target-symbol-header-night")
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
        tapNativeMenuItem(app.buttons["Charlie"],revealing: app.staticTexts["navigation-target-error"])
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
