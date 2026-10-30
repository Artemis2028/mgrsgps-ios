import XCTest

final class ImportReviewWorkflowTests:XCTestCase {
    private let csv="name,lat,lon\nAlpha,24.453904,54.377304\nNew marker,24.4542,54.378\n"
    private func launch()->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["-uiTesting","-uiTestLibrary","-startTab","waypoints"];app.launch();return app
    }
    private func preview(_ app:XCUIApplication) {
        app.buttons["Waypoint actions"].tap();tapNativeMenuItem(app.buttons["Paste text"]);tapNativeMenuItem(app.buttons["Paste CSV"])
        let input=app.textViews["gpx-import-text"];XCTAssertTrue(input.waitForExistence(timeout:5));input.tap();input.typeText(csv)
        app.buttons["preview-interchange"].tap()
        let confirm=app.buttons["confirm-gpx-import"];XCTAssertTrue(confirm.waitForExistence(timeout:10));confirm.tap()
        XCTAssertTrue(app.alerts["Already here"].waitForExistence(timeout:10),app.debugDescription)
    }
    private func capture(_ name:String) {let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func testCancelThenImportAllPreservesOriginalAndRetryIDs() {
        continueAfterFailure=false;let app=launch();preview(app);capture("duplicate-review-day")
        app.alerts["Already here"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["confirm-gpx-import"].exists);XCTAssertFalse(app.buttons["edit-waypoint-New marker"].exists)
        app.buttons["confirm-gpx-import"].tap();XCTAssertTrue(app.alerts["Already here"].waitForExistence(timeout:10))
        tapNativeMenuItem(app.alerts["Already here"].buttons["Import all"],revealing: app.buttons["edit-waypoint-New marker"])
        XCTAssertTrue(app.buttons["edit-waypoint-New marker"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons.matching(identifier:"edit-waypoint-Alpha").count,2)
        preview(app);tapNativeMenuItem(app.alerts["Already here"].buttons["Import all"],revealing: app.buttons["edit-waypoint-New marker"])
        XCTAssertTrue(app.buttons["edit-waypoint-New marker"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons.matching(identifier:"edit-waypoint-Alpha").count,2)
        XCTAssertEqual(app.buttons.matching(identifier:"edit-waypoint-New marker").count,1)
    }
    func testSkipMatchesKeepsNewRecordAndNightPromptReadable() {
        continueAfterFailure=false;let app=launch()
        app.tabBars.buttons["Map"].tap();mapTool(app, "Toggle map night mode").tap();app.buttons["Waypoints"].tap()
        preview(app);capture("duplicate-review-night")
        app.alerts["Already here"].buttons["Skip 1"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-New marker"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons.matching(identifier:"edit-waypoint-Alpha").count,1)
        app.terminate();app.launchArguments += ["-keepUITestData"];app.launch()
        XCTAssertEqual(app.buttons.matching(identifier:"edit-waypoint-Alpha").count,1)
        XCTAssertTrue(app.buttons["edit-waypoint-New marker"].exists)
    }
}
