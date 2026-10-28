import XCTest

final class OfflineDownloadLifetimeWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0..<8 {
            if element.exists, element.isHittable {
                let frame = element.frame
                if frame.minY >= app.navigationBars.firstMatch.frame.maxY + 10, frame.maxY < app.frame.maxY - 65 { return }
                if frame.midY < app.navigationBars.firstMatch.frame.maxY + 10 { app.swipeDown(); continue }
            }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTFail("Offline control did not enter the visible list: \(element.debugDescription)")
    }
    private func tab(_ name: String, app: XCUIApplication, night: Bool) {
        let button = night ? app.buttons[name] : app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 8)); tapNativeMenuItem(button)
    }
    private func openLayers(_ app: XCUIApplication) {
        let button = mapTool(app, "map-layers")
        XCTAssertTrue(button.waitForExistence(timeout: 15)); tapNativeMenuItem(button,revealing:app.navigationBars["Map layers"])
        XCTAssertTrue(app.navigationBars["Map layers"].waitForExistence(timeout: 5))
    }
    private func run(night: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestOfflineDownloadLifetime", "-startTab", "map"]
        if night { app.launchArguments.append("-uiTestOfflineDownloadNight") }
        app.launch(); openLayers(app)
        let download = app.buttons["download-map-area"]
        reveal(download, app: app); XCTAssertTrue(download.isEnabled); tapNativeMenuItem(download)
        let estimate = app.staticTexts["offline-estimate"]
        reveal(estimate, app: app); XCTAssertTrue(estimate.exists)
        let confirm = app.buttons["confirm-map-download"]
        reveal(confirm, app: app); tapNativeMenuItem(confirm)
        let pause = app.buttons["pause-map-download"]
        reveal(pause, app: app); XCTAssertTrue(pause.exists, app.debugDescription)
        // No tile can complete until the gate is released on another tab.
        // This is the actual production download; only its network is synthetic.
        tapNativeMenuItem(app.navigationBars.buttons["Done"])
        tab("Position", app: app, night: night)
        let release = app.buttons["offline-lifetime-release"]
        XCTAssertTrue(release.waitForExistence(timeout: 8))
        XCTAssertFalse(mapTool(app, "map-layers").isHittable)
        let status = app.staticTexts["offline-lifetime-status"]
        XCTAssertEqual(status.label, "Download active")
        capture(night ? "offline-download-away-active-night" : "offline-download-away-active-day")
        tapNativeMenuItem(release)
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Offline area saved"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 15), .completed)
        capture(night ? "offline-download-away-completed-night" : "offline-download-away-completed-day")
        tab("Map", app: app, night: night); openLayers(app)
        var saved = app.staticTexts["saved-map-status-Lifetime training area"]
        reveal(saved, app: app); XCTAssertTrue(saved.exists)
        XCTAssertTrue(saved.label.hasPrefix("Ready")); XCTAssertFalse(app.buttons["pause-map-download"].exists)
        capture(night ? "offline-download-ready-night" : "offline-download-ready-day")
        let rename = app.buttons["rename-map-Lifetime training area"]
        reveal(rename, app: app); tapNativeMenuItem(rename)
        let name = app.textFields["offline-area-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); replaceTextInput(name, "Updated field area")
        capture(night ? "offline-area-rename-night" : "offline-area-rename-day")
        tapNativeMenuItem(app.buttons["offline-area-rename-save"])
        saved = app.staticTexts["saved-map-status-Updated field area"]
        reveal(saved, app: app); XCTAssertTrue(saved.label.hasPrefix("Ready"))
        let details = app.staticTexts["saved-map-details-Updated field area"]
        XCTAssertTrue(details.exists); XCTAssertTrue(details.label.contains("tiles stored")); XCTAssertTrue(details.label.contains("on device"))
        tapNativeMenuItem(app.navigationBars.buttons["Done"])
        tab("Position", app: app, night: night)
        tapNativeMenuItem(app.buttons["offline-lifetime-hold"])
        tab("Map", app: app, night: night); openLayers(app)
        let update = app.buttons["update-map-Updated field area"]
        reveal(update, app: app); XCTAssertEqual(update.label, "Update"); tapNativeMenuItem(update)
        reveal(saved, app: app); XCTAssertTrue(saved.label.hasPrefix("Updating"))
        capture(night ? "offline-area-updating-night" : "offline-area-updating-day")
        tapNativeMenuItem(app.navigationBars.buttons["Done"])
        tab("Position", app: app, night: night)
        XCTAssertEqual(status.label, "Download active")
        tapNativeMenuItem(app.buttons["offline-lifetime-release"])
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Offline area saved"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed)
        tab("Map", app: app, night: night); openLayers(app)
        reveal(saved, app: app); XCTAssertTrue(saved.label.hasPrefix("Ready"))
        capture(night ? "offline-area-updated-night" : "offline-area-updated-day")
        let offline = app.switches["Offline only"]
        reveal(offline, app: app, up: false); tapNativeSwitch(offline)
        XCTAssertEqual(offline.value as? String, "1")
        tapNativeMenuItem(app.navigationBars.buttons["Done"])
        app.terminate(); app.launchArguments.append("-keepUITestData"); app.launch()
        let layer = mapReadout(app, "map-layer-name")
        XCTAssertTrue(layer.waitForExistence(timeout: 15)); XCTAssertTrue(layer.label.contains("OFFLINE ONLY"))
        openLayers(app); reveal(saved, app: app); XCTAssertTrue(saved.exists)
        XCTAssertTrue(saved.label.hasPrefix("Ready"))
        XCTAssertFalse(app.buttons["pause-map-download"].exists)
        capture(night ? "offline-download-relaunched-night" : "offline-download-relaunched-day")
    }
    func testDownloadFinishesAwayFromMapAndReopensOfflineInDay() { run(night: false) }
    func testDownloadFinishesAwayFromMapAndReopensOfflineAtNight() { run(night: true) }
}
