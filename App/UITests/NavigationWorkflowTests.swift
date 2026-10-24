import XCTest

/// A host-side route feeds real GPS updates, including while backgrounded.
final class NavigationWorkflowTests: XCTestCase {
    func testAutomaticRouteFollowingPauseBackgroundCompletionAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-startTab","waypoints"]
        app.launch()
        let actions = app.buttons["Waypoint actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        app.buttons["Paste text"].tap()
        app.buttons["Paste GPX"].tap()
        let text = app.textViews["gpx-import-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap()
        text.typeText("<gpx version=\"1.1\" creator=\"UI\"><rte><name>Navigation patrol</name><rtept lat=\"24.4539\" lon=\"54.3773\"/><rtept lat=\"24.4549\" lon=\"54.3773\"/><rtept lat=\"24.4559\" lon=\"54.3773\"/></rte></gpx>")
        app.buttons["preview-interchange"].tap()
        XCTAssertTrue(app.buttons["confirm-gpx-import"].waitForExistence(timeout: 10))
        app.buttons["confirm-gpx-import"].tap()
        app.buttons["open-field-library"].tap()
        let route = app.buttons["route-Navigation patrol"]
        XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
        app.buttons["follow-route"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 2) { springboard.buttons["Allow"].tap() }
        let progress = app.staticTexts["route-follow-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        let second = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@","Point 2 of 3"),object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [second],timeout: 40),.completed,app.debugDescription)
        for _ in 0..<5 { if app.buttons["pause-route"].isHittable { break }; app.swipeUp() }
        app.buttons["pause-route"].tap()
        XCTAssertTrue(progress.label.contains("paused"))
        let paused = progress.label
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 2); app.activate()
        XCTAssertEqual(progress.label,paused)
        let resume = app.buttons["resume-route"]
        let hit = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"),object: resume)
        XCTAssertEqual(XCTWaiter.wait(for: [hit],timeout: 5),.completed)
        resume.tap(); XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 32)
        app.activate()
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@","Route complete"),object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [complete],timeout: 10),.completed,app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "automatic-route-complete"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        app.tabBars.buttons["Navigate"].tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 5)); XCTAssertEqual(progress.label,"Route complete")
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists)
    }
}
