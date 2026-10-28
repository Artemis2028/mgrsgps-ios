import XCTest

final class LaneCueWorkflowTests:XCTestCase {
    private func guideSettings(_ app:XCUIApplication) {
        let button=app.buttons["guide-settings"]
        for _ in 0..<5 {if button.isHittable {break};app.swipeUp()}
        XCTAssertTrue(button.isHittable,app.debugDescription);button.tap()
    }
    private func toggle(_ key:String,to value:Bool,in app:XCUIApplication) {
        let element=app.switches[key]
        for _ in 0..<6 {if element.isHittable && element.frame.maxY < app.frame.maxY-50 {break};app.swipeUp()}
        XCTAssertTrue(element.isHittable,app.debugDescription)
        if (element.value as? String == "1") != value {element.coordinate(withNormalizedOffset:.init(dx:0.9,dy:0.5)).tap()}
        let expected=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",value ? "1":"0"),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[expected],timeout:5),.completed,app.debugDescription)
    }
    private func capture(_ name:String) {let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    func testLaneCueSwitchesReminderPersistenceAndNightReadability() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-uiTesting","-startTab","navigate"];app.launch()
        guideSettings(app)
        for key in ["lane-side-cues","lane-backstop-cue","lane-inside-tick","lane-gps-alert"] {toggle(key,to:false,in:app)}
        let reminder=app.buttons["lane-reminder"]
        XCTAssertTrue(reminder.isHittable,app.debugDescription);reminder.tap()
        capture("lane-reminder-choices-day")
        tapNativeMenuItem(app.buttons["lane-reminder-10"])
        XCTAssertTrue(app.navigationBars["Guide settings"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Every 10 min"].exists,app.debugDescription)
        capture("lane-cue-settings-day")
        app.navigationBars.buttons["Done"].tap();app.tabBars.buttons["Map"].tap()
        mapTool(app, "Toggle map night mode").tap()
        app.terminate();app.launchArguments += ["-keepUITestData"];app.launch()
        guideSettings(app)
        for key in ["lane-side-cues","lane-backstop-cue","lane-inside-tick","lane-gps-alert"] {
            let element=app.switches[key]
            for _ in 0..<6 {if element.isHittable && element.frame.maxY < app.frame.maxY-50 {break};app.swipeUp()}
            XCTAssertEqual(element.value as? String,"0",app.debugDescription)
        }
        XCTAssertTrue(app.staticTexts["Every 10 min"].exists,app.debugDescription)
        capture("lane-cue-settings-night-reopened")
        revealSettingsControl(reminder,in: app); tapNativeMenuItem(reminder)
        XCTAssertTrue(app.buttons["lane-reminder-10"].waitForExistence(timeout:5))
        capture("lane-reminder-choices-night")
        tapNativeMenuItem(app.navigationBars.buttons["Cancel"])
        XCTAssertTrue(app.staticTexts["Every 10 min"].exists,app.debugDescription)
    }
}
