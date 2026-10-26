import XCTest

final class LibraryMutationFailureWorkflowTests: XCTestCase {
    private func verifyRetry(night: Bool) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestLibraryWriteFailure","-startTab","waypoints"]
        if night { app.launchArguments += ["-uiTestLibraryWriteFailureNight"] }
        app.launch()
        XCTAssertTrue(app.buttons["Recon"].waitForExistence(timeout: 10)); app.buttons["Recon"].tap()
        app.buttons["Folder options"].tap(); tapNativeMenuItem(app.buttons["Rename folder"])
        let name = app.textFields["library-folder-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); replaceTextInput(name,"Patrol")
        app.buttons["library-folder-save"].tap()
        let error = app.staticTexts["library-folder-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10)); XCTAssertTrue(error.label.contains("Graphics and tracks moved"))
        XCTAssertEqual(name.value as? String,"Patrol")
        let failed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        failed.name = night ? "folder-retry-night" : "folder-retry-day"; failed.lifetime = .keepAlways; add(failed)
        tapNativeMenuItem(app.buttons["library-folder-repair"])
        app.buttons["library-folder-save"].tap()
        XCTAssertTrue(app.buttons["Patrol"].waitForExistence(timeout: 10))
        let listed = app.staticTexts["library-listed-count"]
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@","1 waypoints · 1 graphics · 1 tracks"),object: listed)
        XCTAssertEqual(XCTWaiter.wait(for: [complete],timeout: 5),.completed)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        XCTAssertTrue(app.buttons["Patrol"].waitForExistence(timeout: 10)); app.buttons["Patrol"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "library-graphic-Recon route").count,1)
        let saved = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        saved.name = night ? "folder-retried-night" : "folder-retried-day"; saved.lifetime = .keepAlways; add(saved)
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    func testDayPartialRenameKeepsDraftAndRetrySurvivesRelaunch() { verifyRetry(night: false) }
    func testNightPartialRenameKeepsDraftAndRetrySurvivesRelaunch() { verifyRetry(night: true) }
}
