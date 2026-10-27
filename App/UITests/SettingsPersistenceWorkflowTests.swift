import XCTest

final class SettingsPersistenceWorkflowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testRealSettingsObstructionShowsFailureAndRetrySurvivesRelaunchInDayAndNight() {
        for night in [false,true] {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting","-uiTestSettingsWriteFailure","-startTab","position"]
            app.launch(); app.buttons["Settings"].tap()
            let toggle = app.switches[night ? "Red-on-black, to keep night vision" : "Keep screen on"]
            XCTAssertTrue(toggle.waitForExistence(timeout:5)); setNativeSwitch(toggle,to:night)
            let failure = app.staticTexts["settings-save-sheet"]
            XCTAssertTrue(failure.waitForExistence(timeout:5)); XCTAssertTrue(failure.label.contains("could not be saved"))
            capture(night ? "settings-write-failure-sheet-night" : "settings-write-failure-sheet-day")
            app.navigationBars.buttons["Done"].tap()
            let banner = app.staticTexts["settings-save-root"]
            XCTAssertTrue(banner.waitForExistence(timeout:5),app.debugDescription)
            capture(night ? "settings-write-failure-root-night" : "settings-write-failure-root-day")
            app.buttons["settings-save-root-retry"].tap()
            XCTAssertTrue(banner.waitForExistence(timeout:5),"Retry must keep the file obstruction, not clear the error optimistically")
            app.buttons["settings-save-root-test-repair"].tap()
            let saved = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:banner)
            XCTAssertEqual(XCTWaiter.wait(for:[saved],timeout:10),.completed)
            app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
            XCTAssertFalse(app.staticTexts["settings-save-root"].exists)
            app.buttons["Settings"].tap()
            let restored = app.switches[night ? "Red-on-black, to keep night vision" : "Keep screen on"]
            XCTAssertTrue(restored.waitForExistence(timeout:5)); XCTAssertEqual(restored.value as? String,night ? "1" : "0")
            capture(night ? "settings-write-retry-restored-night" : "settings-write-retry-restored-day")
            app.terminate()
        }
    }
}
