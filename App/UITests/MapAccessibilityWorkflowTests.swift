import XCTest

final class MapAccessibilityWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestBoundaryMap", "-startTab", "map",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func visible(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout:10), app.debugDescription)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(element.frame.height, 0)
        XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX + 1)
        XCTAssertGreaterThanOrEqual(element.frame.minY, window.minY)
        XCTAssertLessThanOrEqual(element.frame.maxY, window.maxY + 1)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func action(_ id: String) {
        let entry = app.buttons["map-accessible-actions"]; visible(entry); entry.tap()
        XCTAssertTrue(app.navigationBars["Map actions"].waitForExistence(timeout:5))
        let button = app.buttons["map-action-" + id]
        for _ in 0..<32 {
            let list = app.collectionViews.firstMatch
            let top = app.navigationBars["Map actions"].frame.maxY + 12
            let bottom = app.windows.firstMatch.frame.maxY - 30
            if button.exists && button.isHittable && button.frame.maxY < bottom && button.frame.minY > top { break }
            let middle = (top + bottom) / 2
            let movement = button.exists ? min(90,max(-90,middle-button.frame.midY)) : -90
            let start = app.coordinate(withNormalizedOffset:.zero).withOffset(.init(dx:list.frame.midX,dy:middle))
            start.press(forDuration:0.1,thenDragTo:start.withOffset(.init(dx:0,dy:movement)),withVelocity:.slow,thenHoldForDuration:0.3)
        }
        visible(button); button.tap()
    }
    private func checkDetails() {
        let summary = app.buttons["map-centre-summary"]; visible(summary)
        XCTAssertTrue((summary.value as? String)?.contains("40R") == true, app.debugDescription)
        summary.tap()
        let grid = app.staticTexts["map-centre-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout:5)); XCTAssertGreaterThan(grid.frame.height,32)
        capture("map-global-largest-details")
        let decimal = app.staticTexts["map-centre-decimal"]
        for _ in 0..<12 {
            if decimal.exists && decimal.isHittable && decimal.frame.maxY < app.windows.firstMatch.frame.maxY - 30 { break }
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.8))
                .press(forDuration:0.1,thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.55)),withVelocity:.slow,thenHoldForDuration:0.3)
        }
        visible(decimal)
        app.navigationBars["Map centre"].buttons["Done"].tap()
        visible(app.buttons["map-accessible-actions"])
    }
    func testLargestTextMapDetailsActionsAndLayersInDayAndNight() {
        app.launch()
        for night in [false, true] {
            if night { action("night") }
            visible(app.buttons["map-centre-summary"])
            visible(app.buttons["map-accessible-actions"])
            capture(night ? "map-global-largest-night" : "map-global-largest-day")
            checkDetails()
            action("layers")
            XCTAssertTrue(app.navigationBars["Map layers"].waitForExistence(timeout:5),app.debugDescription)
            capture(night ? "map-global-largest-layers-night" : "map-global-largest-layers-day")
            app.navigationBars["Map layers"].buttons["Done"].tap()
            visible(app.buttons["map-accessible-actions"])
        }
    }
    func testLargestTextLandscapeRetainsActionsAndScrollableDetails() {
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        visible(app.buttons["map-centre-summary"])
        visible(app.buttons["map-accessible-actions"])
        capture("map-global-largest-landscape")
        checkDetails()
        action("tools")
        XCTAssertTrue(app.navigationBars["Map tools"].waitForExistence(timeout:5),app.debugDescription)
        capture("map-global-largest-field-tools")
        XCUIDevice.shared.orientation = .portrait
        let reference = app.buttons["field-reference"]
        for _ in 0..<16 {
            if reference.exists && reference.isHittable { break }
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.8)).press(forDuration:0.1,
                thenDragTo:list.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.55)),withVelocity:.slow,thenHoldForDuration:0.3)
        }
        XCTAssertTrue(reference.isHittable,app.debugDescription); reference.tap()
        XCTAssertTrue(app.navigationBars["Field reference"].waitForExistence(timeout:5))
        let alfa = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","A, Alfa")).firstMatch
        XCTAssertTrue(alfa.exists); XCTAssertGreaterThan(alfa.frame.height,32)
        capture("reference-from-global-largest-map")
    }
    func testLargestTextLandscapeRulerCanBeClosedAndBoundaryCanBeCancelled() {
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        action("ruler")
        let panel = app.scrollViews["map-accessible-panels"]
        XCTAssertTrue(panel.waitForExistence(timeout:5))
        let done = app.buttons["ruler-done"]
        XCTAssertTrue(done.waitForExistence(timeout:5))
        for _ in 0..<12 {
            if done.isHittable && done.frame.midY < panel.frame.maxY && done.frame.midY > panel.frame.minY { break }
            panel.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.8)).press(forDuration:0.1,
                thenDragTo:panel.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.2)),withVelocity:.slow,thenHoldForDuration:0.3)
        }
        XCTAssertTrue(done.isHittable,app.debugDescription)
        capture("map-global-largest-ruler-landscape")
        done.tap()
        XCTAssertTrue(app.buttons["map-centre-summary"].waitForExistence(timeout:5))
        action("boundaries")
        let draw = app.buttons["draw-boundary"]
        XCTAssertTrue(app.navigationBars["Boundaries"].waitForExistence(timeout:5))
        for _ in 0..<32 {
            let top = app.navigationBars["Boundaries"].frame.maxY + 12
            let bottom = app.frame.maxY - 30
            if draw.exists && draw.isHittable && draw.frame.minY > top && draw.frame.maxY < bottom { break }
            let middle = (top + bottom) / 2
            let movement = draw.exists ? min(90,max(-90,middle-draw.frame.midY)) : -90
            let start = app.coordinate(withNormalizedOffset:.zero).withOffset(.init(dx:app.frame.midX,dy:middle))
            start.press(forDuration:0.1,thenDragTo:start.withOffset(.init(dx:0,dy:movement)),withVelocity:.slow,thenHoldForDuration:0.3)
        }
        visible(draw)
        draw.tap()
        XCTAssertTrue(panel.waitForExistence(timeout:5))
        let cancel = app.buttons["cancel-boundary"]
        for _ in 0..<12 {
            if cancel.exists && cancel.isHittable { break }
            panel.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.8))
                .press(forDuration:0.1,thenDragTo:panel.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)),withVelocity:.slow,thenHoldForDuration:0.3)
        }
        XCTAssertTrue(cancel.isHittable,app.debugDescription)
        capture("map-global-largest-boundary-landscape")
        cancel.tap()
        visible(app.buttons["map-centre-summary"])
        XCUIDevice.shared.orientation = .portrait
    }
    func testLargestTextRecordingKeepsMapAndFinishControlsReachable() {
        app.launch()
        action("record")
        let banner = app.buttons["recording-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout:10),app.debugDescription)
        visible(app.buttons["map-accessible-actions"])
        capture("map-global-largest-live-recording")
        banner.tap()
        let discard = app.buttons["discard-recording"]
        XCTAssertTrue(app.navigationBars["Track recording"].waitForExistence(timeout:5))
        for _ in 0..<20 {
            if discard.exists && discard.isHittable && discard.frame.maxY < app.frame.maxY - 40 { break }
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.8)).press(forDuration:0.1,
                thenDragTo:list.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.55)),withVelocity:.slow,thenHoldForDuration:0.3)
        }
        visible(discard); capture("recording-global-largest-finish-controls")
        discard.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:5))
        app.alerts.firstMatch.buttons["Discard recording"].tap()
        app.navigationBars["Track recording"].buttons["Done"].tap()
        visible(app.buttons["map-accessible-actions"])
    }
}
