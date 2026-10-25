import XCTest

/// Host: scripts/movement-test-route.py. Course/speed come from CoreLocation.
final class MovementWorkflowTests: XCTestCase {
    private func signal(_ value: String) { FileHandle.standardOutput.write(Data((value + "\n").utf8)) }
    private func capture(_ name: String,_ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testRealTravelCourseSpeedUnitsNavigationAndStationaryState() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-startTab","position","-startFace","glance"]
        app.launch()
        let course = app.staticTexts["position-heading-readout"], speed = app.staticTexts["position-speed-readout"]
        XCTAssertTrue(course.waitForExistence(timeout: 12))
        let moving = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            course.label.contains("CRS 000° T") && speed.label.contains("5.8 km/h")
        },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [moving],timeout: 25),.completed,app.debugDescription)
        capture("gps-course-speed-metric",app)
        app.buttons["Settings"].tap()
        let imperial = app.buttons["Imperial"]
        for _ in 0..<6 { if imperial.isHittable { break }; app.swipeUp() }
        imperial.tap(); app.buttons["Done"].tap()
        XCTAssertTrue(speed.label.contains("3.6 mph")); XCTAssertTrue(course.label.contains("CRS 000° T"))
        app.buttons["Settings"].tap()
        let nautical = app.buttons["Nautical"]
        for _ in 0..<6 { if nautical.isHittable { break }; app.swipeUp() }
        nautical.tap()
        let night = app.switches["Red-on-black, to keep night vision"]
        for _ in 0..<6 { if night.isHittable { break }; app.swipeDown() }
        night.tap(); app.buttons["Done"].tap()
        XCTAssertTrue(speed.label.contains("3.1 kn")); capture("gps-course-speed-night-nautical",app)
        app.buttons["Navigate"].tap(); app.buttons["Choose navigation target"].tap()
        tapNativeMenuItem(app.buttons["Alpha"].firstMatch)
        let steering = app.descendants(matching: .any).matching(identifier: "display-relative-navigation").firstMatch
        XCTAssertTrue(steering.waitForExistence(timeout: 8)); XCTAssertTrue(steering.label.contains("GPS course"))
        XCTAssertFalse(steering.label.contains("Screen top")); capture("gps-course-navigation",app)
        app.buttons["Position"].tap(); signal("GRIDFIX_MOTION_STATIONARY")
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            course.label.contains("HDG —") && !course.label.contains("CRS")
        },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped],timeout: 20),.completed,app.debugDescription)
        capture("gps-course-stationary",app); signal("GRIDFIX_MOTION_DONE")
    }
}
