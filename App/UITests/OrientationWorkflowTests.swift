import XCTest

final class OrientationWorkflowTests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY
            if element.isHittable && element.frame.minY > top+8 && element.frame.maxY < app.frame.maxY-35 { return }
            // In landscape the app-level swipe can start in the navigation
            // bar. Send the gesture to the presented List's scroll surface.
            let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
            let surface = scroll.exists ? scroll : app
            if element.exists && element.frame.midY < top+8 { surface.swipeDown() } else { surface.swipeUp() }
        }
    }
    private func choose(_ value: Int,in app: XCUIApplication) {
        let button = app.buttons["orientation-option-\(value)"].firstMatch
        reveal(button,in: app); tapNativeMenuItem(button)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testPinnedOrientationsSurviveRelaunchAndAutoFollowsDevice() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting","-startTab","position","-startFace","glance"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch(); app.buttons["Settings"].tap()
        let picker = app.segmentedControls["screen-orientation"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8)); picker.buttons["Landscape"].tap()
        let sideways = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in app.frame.width > app.frame.height },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [sideways],timeout: 10),.completed)
        let actual = app.staticTexts["orientation-window"]; reveal(actual,in: app)
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@","Current window: Landscape"),object: actual)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape],timeout: 8),.completed)
        capture("orientation-landscape",app)
        XCUIDevice.shared.orientation = .landscapeLeft
        reveal(picker,in: app); picker.buttons["Flipped"].tap()
        let flipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@","Current window: Flipped"),object: actual)
        XCTAssertEqual(XCTWaiter.wait(for: [flipped],timeout: 10),.completed); capture("orientation-flipped",app)
        XCUIDevice.shared.orientation = .portrait
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        let pinned = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in app.frame.width > app.frame.height },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [pinned],timeout: 10),.completed)
        XCUIDevice.shared.orientation = .landscapeRight
        app.buttons["Settings"].tap(); reveal(actual,in: app)
        XCTAssertEqual(actual.label,"Current window: Flipped")
        reveal(picker,in: app); tapNativeMenuItem(picker.buttons["Portrait"])
        XCTAssertTrue(picker.buttons["Portrait"].isSelected)
        let upright = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in app.frame.height > app.frame.width },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [upright],timeout: 10),.completed)
        XCUIDevice.shared.orientation = .portrait
        picker.buttons["Auto"].tap(); app.navigationBars.buttons["Done"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let auto = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in app.frame.width > app.frame.height },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [auto],timeout: 10),.completed); capture("orientation-auto",app)
        XCUIDevice.shared.orientation = .portrait
    }
    func testQuickOrientationControlsAreAvailableAcrossMainScreens() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","navigate"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch(); app.buttons["screen-orientation-menu"].tap()
        // This test checks every shortcut in a stable portrait gesture space.
        // The separate pinned-orientation test checks both landscape requests,
        // actual scene geometry, relaunch persistence and Auto rotation.
        choose(1,in: app)
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["map-measure"].waitForExistence(timeout: 8)); capture("orientation-map-shortcut",app)
        app.buttons["map-measure"].tap()
        let rotation = app.buttons["field-orientation"]; reveal(rotation,in: app); tapNativeMenuItem(rotation)
        choose(1,in: app)
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["Waypoint actions"].tap()
        tapNativeMenuItem(app.buttons["library-orientation-shortcut"].firstMatch); choose(1,in: app)
        let upright = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in app.frame.height > app.frame.width },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [upright],timeout: 10),.completed)
        XCUIDevice.shared.orientation = .portrait
        app.tabBars.buttons["Position"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.segmentedControls["screen-orientation"].buttons["Portrait"].isSelected)
        app.navigationBars.buttons["Done"].tap()
        app.buttons["Settings"].press(forDuration: 1)
        tapNativeMenuItem(app.buttons["position-orientation-shortcut"].firstMatch); choose(0,in: app)
        capture("orientation-position-shortcut",app)
    }

}
