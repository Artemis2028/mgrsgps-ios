import XCTest

final class MapPreferencesWorkflowTests: XCTestCase {
    func testFailedMapSaveStaysVisibleAndRetryRestoresChoicesInDayAndNight() {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        for night in [false,true] {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-uiTestMapPreferenceFailure","-startTab","map"]
            app.launch()
            XCTAssertTrue(app.buttons["map-layers"].waitForExistence(timeout: 10))
            if night { app.buttons["Toggle map night mode"].tap() }
            app.buttons["map-layers"].tap()
            let grid = app.switches["MGRS grid"]
            XCTAssertTrue(grid.waitForExistence(timeout:5)); setNativeSwitch(grid,to:false)
            let retry = app.buttons["map-preferences-retry"]
            XCTAssertTrue(retry.waitForExistence(timeout:5),app.debugDescription)
            let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            shot.name = night ? "map-save-failure-night" : "map-save-failure-day"
            shot.lifetime = .keepAlways; add(shot)
            app.navigationBars.buttons["Done"].tap()
            let rootRetry = app.buttons["map-preferences-root-retry"]
            XCTAssertTrue(rootRetry.waitForExistence(timeout:5),app.debugDescription)
            rootRetry.tap(); XCTAssertTrue(rootRetry.waitForExistence(timeout:5),app.debugDescription)
            app.buttons["map-preferences-root-test-repair"].tap()
            let saved = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:rootRetry)
            XCTAssertEqual(XCTWaiter.wait(for:[saved],timeout:10),.completed)
            app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
            XCTAssertTrue(app.buttons["map-layers"].waitForExistence(timeout:10)); app.buttons["map-layers"].tap()
            XCTAssertTrue(grid.waitForExistence(timeout:5)); XCTAssertEqual(grid.value as? String,"0")
            XCTAssertEqual(app.switches["Offline only"].value as? String,"1")
            app.terminate()
        }
    }
}
