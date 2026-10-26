import XCTest

final class LiveActivityWorkflowTests:XCTestCase {
    private func settings(_ app:XCUIApplication) {
        app.tabBars.buttons["Position"].tap();tapNativeMenuItem(app.buttons["Settings"])
        let toggle=app.switches["settings-live-activities"]
        revealSettingsControl(toggle,in: app)
        XCTAssertTrue(toggle.isHittable,app.debugDescription)
    }
    private func count(_ n:Int,_ app:XCUIApplication) {
        let status=app.staticTexts["live-activity-status"]
        revealSettingsControl(status,in: app)
        let expected=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","\(n) active"),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[expected],timeout:15),.completed,app.debugDescription)
    }
    private func enabled(_ value:Bool,_ app:XCUIApplication) {
        let toggle=app.switches["settings-live-activities"]
        revealSettingsControl(toggle,in: app)
        setNativeSwitch(toggle,to: value)
        let expected=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",value ? "1" : "0"),object:toggle)
        XCTAssertEqual(XCTWaiter.wait(for:[expected],timeout:5),.completed,app.debugDescription)
    }
    private func capture(_ name:String) { let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    func testOptionalRecordingActivitySurvivesBackgroundAndOptOutThenEndsWithSession() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-uiTesting","-uiTestLibrary","-startTab","map"];app.launch()
        settings(app);XCTAssertEqual(app.switches["settings-live-activities"].value as? String,"0");count(0,app)
        capture("live-activities-off-default");tapNativeMenuItem(app.navigationBars.buttons["Done"])
        app.tabBars.buttons["Map"].tap()
        let record=app.buttons["record-track"]
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Record track"),object:record)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed);record.tap()
        let banner=app.buttons["recording-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout:8))
        let recording=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label MATCHES %@",".*Recording · [1-9][0-9]* points.*"),object:banner)
        XCTAssertEqual(XCTWaiter.wait(for:[recording],timeout:20),.completed,app.debugDescription)
        settings(app);count(0,app);enabled(true,app);count(1,app);capture("live-activity-recording-enabled")
        tapNativeMenuItem(app.navigationBars.buttons["Done"]);XCUIDevice.shared.press(.home)
        let home=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        XCTAssertTrue(home.icons.firstMatch.waitForExistence(timeout:5))
        Thread.sleep(forTimeInterval:1)
        capture("live-activity-recording-island")
        app.activate();settings(app);count(1,app);enabled(false,app);count(0,app)
        XCTAssertTrue(app.buttons["recording-banner"].exists,"Turning off Live Activities must not stop recording")
        enabled(true,app);count(1,app);tapNativeMenuItem(app.navigationBars.buttons["Done"])
        app.tabBars.buttons["Map"].tap();app.buttons["record-track"].tap()
        let discard=app.buttons["discard-recording"];XCTAssertTrue(discard.waitForExistence(timeout:5));discard.tap()
        let alert=app.alerts.firstMatch;XCTAssertTrue(alert.waitForExistence(timeout:5));alert.buttons["Discard recording"].tap()
        tapNativeMenuItem(app.navigationBars.buttons["Done"]);settings(app);count(0,app);capture("live-activity-recording-ended")
    }
    func testNavigationActivityStartsPausesResumesAndOptOutKeepsRouteRunning() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-uiTesting","-uiTestLibrary","-startTab","waypoints"];app.launch()
        settings(app);enabled(true,app);count(0,app);tapNativeMenuItem(app.navigationBars.buttons["Done"])
        app.tabBars.buttons["Waypoints"].tap();app.buttons["open-field-library"].tap()
        let route=app.buttons["route-Recon route"];XCTAssertTrue(route.waitForExistence(timeout:5));route.tap()
        app.buttons["follow-route"].tap()
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout:2) { springboard.buttons["Allow"].tap() }
        let progress=app.staticTexts["route-follow-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout:10))
        settings(app);count(1,app);capture("live-activity-navigation-enabled")
        enabled(false,app);count(0,app);tapNativeMenuItem(app.navigationBars.buttons["Done"])
        app.tabBars.buttons["Navigate"].tap()
        for _ in 0..<6 { if app.buttons["pause-route"].isHittable { break };app.swipeUp() }
        XCTAssertTrue(app.buttons["pause-route"].isHittable,"Opting out must leave route following running")
        settings(app);enabled(true,app);count(1,app);tapNativeMenuItem(app.navigationBars.buttons["Done"])
        app.tabBars.buttons["Navigate"].tap()
        for _ in 0..<6 { if app.buttons["pause-route"].isHittable { break };app.swipeUp() }
        app.buttons["pause-route"].tap();settings(app);count(0,app)
        tapNativeMenuItem(app.navigationBars.buttons["Done"]);app.tabBars.buttons["Navigate"].tap()
        for _ in 0..<6 { if app.buttons["resume-route"].isHittable { break };app.swipeUp() }
        app.buttons["resume-route"].tap();settings(app);count(1,app)
        capture("live-activity-navigation-resumed")
    }

}
