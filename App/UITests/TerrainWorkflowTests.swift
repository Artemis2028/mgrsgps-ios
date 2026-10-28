import XCTest

final class TerrainWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    private func launch(missing: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting",missing ? "-uiTestTerrainNoData" : "-uiTestTerrain","-startTab","map"]; app.launch()
        let open = mapTool(app, "map-terrain"); XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        XCTAssertTrue(app.navigationBars["Terrain visibility"].waitForExistence(timeout: 5))
    }
    private func pick(_ prefix: String,_ name: String) {
        let source = app.buttons["terrain-\(prefix)-source"]
        reveal(source)
        let sourceReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"),object: source)
        XCTAssertEqual(XCTWaiter.wait(for: [sourceReady],timeout: 5),.completed)
        tapNativeMenuItem(source)
        let option = app.buttons["terrain-\(prefix)-source-waypoint"]
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        let waypoint = app.buttons["terrain-\(prefix)-waypoint"]
        XCTAssertTrue(waypoint.waitForExistence(timeout: 5)); reveal(waypoint); tapNativeMenuItem(waypoint)
        let choice = app.buttons["terrain-\(prefix)-choice-\(name)"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        XCTAssertTrue(waypoint.label.contains(name),"The requested terrain endpoint must be selected before analysis.")
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            // Canvas has no tappable activation point on some runtimes. Its
            // visible frame, rather than button hittability, controls scrolling.
            if element.exists && !element.frame.isEmpty && element.frame.midY > 150 && element.frame.midY < 720 && (element.elementType != .button || element.isHittable) { return }
            if element.exists && element.frame.midY < 150 { app.swipeDown() } else { app.swipeUp() }
        }
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testOfflineLineOfSightProfileAndViewshedUseRealEncodedTerrain() {
        launch(); pick("observer","West observer"); pick("target","East target")
        let check = app.buttons["terrain-check"]; reveal(check); XCTAssertTrue(check.isEnabled,"Valid selected endpoints must enable analysis"); check.tap()
        let status = app.staticTexts["terrain-sight-status"]
        // Older Form runtimes don't materialize result rows below the viewport
        // until they are scrolled into view, even after analysis has completed.
        reveal(status); XCTAssertTrue(status.waitForExistence(timeout: 15)); XCTAssertEqual(status.label,"MASKED")
        let chart = app.otherElements["terrain-profile-chart"]; reveal(chart)
        capture("terrain-line-of-sight")
        let route = app.buttons["terrain-profile-Terrain patrol"]; reveal(route); route.tap()
        let missing = app.staticTexts["terrain-missing-count"]
        reveal(missing); XCTAssertTrue(missing.waitForExistence(timeout: 15))
        XCTAssertTrue(missing.label.hasPrefix("0 missing"))
        capture("terrain-route-profile")
        // Reopen the sheet to return to its initial scroll position and clear results.
        app.navigationBars.buttons["Done"].tap(); mapTool(app, "map-terrain").tap()
        pick("observer","West observer")
        let shade = app.buttons["terrain-shade"]; reveal(shade); shade.tap()
        let legend = app.buttons["viewshed-legend"]
        XCTAssertTrue(legend.waitForExistence(timeout: 45),app.debugDescription)
        capture("terrain-viewshed-day")
        mapTool(app, "Toggle map night mode").tap()
        XCTAssertTrue(legend.waitForExistence(timeout: 5)); capture("terrain-viewshed-night")
        legend.tap(); XCTAssertFalse(app.buttons["viewshed-legend"].exists)
    }
    func testRouteCardOpensElevationProfile() {
        launch(); app.navigationBars.buttons["Done"].tap()
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["open-field-library"].tap()
        app.buttons["route-Terrain patrol"].tap()
        let profile = app.buttons["route-terrain-profile"]; reveal(profile); profile.tap()
        let summary = app.staticTexts["terrain-route-profile-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15)); reveal(summary)
        XCTAssertTrue(summary.label.contains("climb 80")); capture("terrain-route-card-profile")
    }
    func testMissingOfflineElevationShowsUnavailableAndNeverInventsShade() {
        launch(missing: true); pick("observer","West observer"); pick("target","East target")
        let check = app.buttons["terrain-check"]; reveal(check); XCTAssertTrue(check.isEnabled,"Valid selected endpoints must enable analysis"); check.tap()
        let error = app.staticTexts["terrain-error"]; reveal(error); XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("No usable elevation")); XCTAssertFalse(app.staticTexts["terrain-sight-status"].exists)
        capture("terrain-missing-data")
        app.navigationBars.buttons["Done"].tap(); XCTAssertFalse(app.buttons["viewshed-legend"].exists)
        app.tabBars.buttons["Waypoints"].tap(); app.buttons["open-field-library"].tap()
        app.buttons["route-Terrain patrol"].tap()
        let profile = app.buttons["route-terrain-profile"]; reveal(profile); profile.tap()
        let unavailable = app.staticTexts["terrain-profile-unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 15)); reveal(unavailable)
        XCTAssertFalse(app.staticTexts["terrain-route-profile-summary"].exists)
        capture("terrain-route-profile-unavailable")
    }
}
