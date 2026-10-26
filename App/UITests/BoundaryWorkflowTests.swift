import XCTest

final class BoundaryWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","map"]
        app.launch()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func draw() {
        let open = app.buttons["map-boundaries"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        app.buttons["draw-boundary"].tap()
        XCTAssertTrue(app.buttons["save-boundary"].waitForExistence(timeout: 5))
        for (index,point) in [CGVector(dx: 0.22,dy: 0.38),CGVector(dx: 0.78,dy: 0.38),CGVector(dx: 0.78,dy: 0.55),CGVector(dx: 0.22,dy: 0.55)].enumerated() {
            app.coordinate(withNormalizedOffset: point).tap()
            let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","\(index+1) points"),object: app.staticTexts["boundary-point-count"])
            XCTAssertEqual(XCTWaiter.wait(for: [added],timeout: 5),.completed)
        }
        XCTAssertTrue(app.staticTexts["boundary-point-count"].label.contains("4 points"),app.debugDescription)
    }
    private func save() {
        app.buttons["save-boundary"].tap()
        XCTAssertTrue(app.buttons["map-boundaries"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["boundary-draw-error"].exists,app.debugDescription)
    }
    func testDrawStraightSidesInsertKinkMoveVertexSaveAndRelaunch() {
        draw()
        let vertex = app.buttons["boundary-point-0"]
        XCTAssertTrue(vertex.waitForExistence(timeout: 5)); vertex.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@","point 1 selected"),object: app.staticTexts["boundary-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected],timeout: 5),.completed)
        // Drag the segment handle to create a new point directly on the map.
        let handle = app.buttons["boundary-midpoint-0"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.5)).press(forDuration: 0.8,thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.50,dy: 0.44)),withVelocity: .slow,thenHoldForDuration: 0.3)
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","5 points"),object: app.staticTexts["boundary-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [added],timeout: 5),.completed)
        XCTAssertFalse(app.buttons["Insert kink"].exists)
        let before = app.staticTexts["boundary-selected-coordinate"].label
        let kink = app.buttons["boundary-point-1"]
        kink.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.5)).press(forDuration: 0.8,thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.56,dy: 0.48)),withVelocity: .slow,thenHoldForDuration: 0.3)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@",before),object: app.staticTexts["boundary-selected-coordinate"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed],timeout: 5),.completed,app.debugDescription)
        capture("boundary-drawing-kink")
        save()
        app.buttons["map-boundaries"].tap()
        XCTAssertTrue(app.staticTexts["5 points · closed perimeter"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        app.buttons["map-boundaries"].tap()
        XCTAssertTrue(app.staticTexts["5 points · closed perimeter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["stop-boundary"].exists)
        capture("boundary-library")
    }
    func testCrossingWithRealBackgroundLocationAndInterruptedRestartNotice() {
        draw(); save(); app.buttons["map-boundaries"].tap()
        app.buttons["monitor-boundary-Boundary"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.buttons["stop-boundary"].waitForExistence(timeout: 10),app.debugDescription)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["boundary-monitor-banner"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 32) // Cover inside confirmation and an exit in the host route.
        app.activate()
        let open = app.buttons["map-boundaries"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"),object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 5),.completed)
        open.tap()
        let count = app.staticTexts["boundary-crossings"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(Int(count.label.split(separator: " ").first ?? "0") ?? 0,0,app.debugDescription)
        capture("boundary-background-crossing")
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
        app.buttons["map-boundaries"].tap()
        XCTAssertTrue(app.staticTexts["boundary-status"].label.contains("interrupted"))
        XCTAssertFalse(app.buttons["stop-boundary"].exists)
        XCTAssertTrue(app.buttons["monitor-boundary-Boundary"].exists)
    }
    func testLongPressOnBoundarySideAddsBendWithoutMonitoring() {
        draw()
        app.coordinate(withNormalizedOffset: .init(dx: 0.35,dy: 0.38)).press(forDuration: 0.8,thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.35,dy: 0.46)))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","5 points"),object: app.staticTexts["boundary-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed],timeout: 5),.completed)
        capture("boundary-direct-line-drag"); save()
        XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
    }
}
