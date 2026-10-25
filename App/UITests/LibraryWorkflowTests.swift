import XCTest

final class LibraryWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestBoundaryMap","-startTab","waypoints"]; app.launch()
        XCTAssertTrue(app.buttons["library-select-button"].waitForExistence(timeout: 10))
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func reveal(_ element: XCUIElement) {
        let list = app.scrollViews["library-list"]
        for _ in 0..<8 {
            if element.exists && !element.frame.isEmpty && element.frame.minY > 295 && element.frame.maxY < app.frame.maxY-100 { return }
            if element.exists && element.frame.midY < 295 { list.swipeDown() } else { list.swipeUp() }
        }
    }
    private func folder(_ name: String) { let chip = app.buttons[name]; XCTAssertTrue(chip.waitForExistence(timeout: 5)); chip.tap() }
    private func selectAll() { app.buttons["library-select-button"].tap(); app.buttons["library-select-all"].tap() }
    private func selected(_ count: Int) { XCTAssertEqual(app.staticTexts["library-selected-count"].label,"\(count) selected") }
    func testMixedSelectionSwapsIndividualVisibilityAndCancelKeepsSelection() {
        folder("Recon"); selectAll(); selected(3); capture("library-mixed-selection")
        app.buttons["Selected item actions"].tap(); tapNativeMenuItem(app.buttons["library-swap-visibility"])
        XCTAssertTrue(app.staticTexts["library-status"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["library-status"].label.contains("3 items"))
        let routeHidden = app.images["library-graphic-hidden-Recon route"], trackHidden = app.images["library-track-hidden-Recon track"]
        reveal(routeHidden); XCTAssertTrue(routeHidden.exists); reveal(trackHidden); XCTAssertTrue(trackHidden.exists)
        selectAll(); selected(3)
        app.buttons["Selected item actions"].tap(); tapNativeMenuItem(app.buttons["library-delete-selected"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["Cancel"].tap(); selected(3)
        app.buttons["library-selection-done"].tap(); capture("library-mixed-visibility")
    }
    func testDeleteMixedFolderSelectionPersistsAndLeavesOtherFolderUntouched() {
        folder("Recon"); selectAll(); selected(3)
        app.buttons["Selected item actions"].tap(); tapNativeMenuItem(app.buttons["library-delete-selected"]); app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        folder("Recon"); XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].waitForExistence(timeout: 5))
        folder("Base"); XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].exists)
        let checkpoint = app.buttons["library-graphic-Base checkpoint"]; reveal(checkpoint); XCTAssertTrue(checkpoint.exists)
        capture("library-after-batch-delete")
    }
    func testRenameFolderMovesAllRecordTypesThenKeepContentsInBase() {
        folder("Recon"); app.buttons["Folder options"].tap(); tapNativeMenuItem(app.buttons["Rename folder"])
        let name = app.textFields["library-folder-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        name.typeKey("a",modifierFlags: .command); name.typeText("Patrol")
        XCTAssertEqual(name.value as? String,"Patrol")
        app.buttons["library-folder-save"].tap()
        XCTAssertTrue(app.buttons["Patrol"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch(); folder("Patrol")
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].exists)
        app.buttons["Folder options"].tap(); tapNativeMenuItem(app.buttons["Delete folder"]); app.buttons["Keep contents in Base"].tap()
        capture("library-folder-after-keep")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: app.buttons["Patrol"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone],timeout: 5),.completed,app.debugDescription)
        folder("Base"); XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("3 waypoints · 2 graphics · 1 tracks"))
        capture("library-folder-kept-in-base")
        let clear = app.buttons["library-clear-graphics"]; reveal(clear); clear.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("3 waypoints · 0 graphics · 1 tracks"))
    }
    func testMoveTrackAndViewHiddenTrackWithoutChangingItsVisibilityFlag() {
        folder("Recon")
        let actions = app.buttons["Actions for track Recon track"]; reveal(actions); actions.tap(); app.buttons["Hide on map"].tap()
        app.buttons["folder-visibility-Recon"].tap()
        reveal(actions); actions.tap(); app.buttons["Show on map"].tap()
        XCTAssertTrue(app.buttons["map-measure"].waitForExistence(timeout: 10))
        let overlays = app.staticTexts["map-field-overlays"]
        XCTAssertTrue(overlays.waitForExistence(timeout: 10)); XCTAssertTrue(overlays.label.contains("1 tracks"))
        app.tabBars.buttons["Waypoints"].tap()
        reveal(actions); actions.tap(); XCTAssertTrue(app.buttons["Make visible on map"].exists)
        app.buttons["Move to folder"].tap(); app.buttons["move-track-to-Base"].tap()
        XCTAssertFalse(app.buttons["library-track-Recon track"].exists)
        folder("Base"); let moved = app.buttons["library-track-Recon track"]; reveal(moved); XCTAssertTrue(moved.exists)
        capture("library-track-moved")
    }
    func testSelectAllAfterFilterChangeReplacesOffscreenSelectionAndEmptyFolderSurvives() {
        app.buttons["library-select-button"].tap()
        let alpha = app.buttons["Select waypoint Alpha"]; reveal(alpha); alpha.tap(); selected(1)
        folder("Recon"); app.buttons["library-select-all"].tap(); selected(3)
        app.buttons["library-selection-done"].tap()
        app.buttons["library-new-folder"].tap(); let name = app.textFields["library-folder-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Empty overlay")
        app.buttons["library-folder-save"].tap()
        XCTAssertTrue(app.staticTexts["Nothing in Empty overlay yet."].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        let chip = app.buttons["Empty overlay"]
        // A horizontally scrolling folder strip retains empty folders too.
        if !chip.isHittable { app.scrollViews.firstMatch.swipeLeft() }
        XCTAssertTrue(chip.waitForExistence(timeout: 5)); chip.tap()
        capture("library-empty-folder")
    }
    func testNightModeKeepsMixedSelectionAndFolderFormsReadable() {
        app.tabBars.buttons["Map"].tap(); app.buttons["Toggle map night mode"].tap(); app.buttons["Waypoints"].tap()
        folder("Recon"); selectAll(); selected(3); capture("library-night-selection")
        app.buttons["library-selection-done"].tap()
        app.buttons["Folder options"].tap(); tapNativeMenuItem(app.buttons["Rename folder"])
        XCTAssertTrue(app.textFields["library-folder-name"].waitForExistence(timeout: 5)); capture("library-night-folder-form")
        app.buttons["Cancel"].tap()
    }
    func testBacktrackFromMixedLibraryShowsSavedRouteAndLeavesNavigationIdle() {
        folder("Recon")
        let actions = app.buttons["Actions for track Recon track"]; reveal(actions); actions.tap()
        app.buttons["backtrack-track-Recon track"].tap()
        XCTAssertTrue(app.buttons["map-measure"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists); XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
        capture("track-backtrack-map")
        app.tabBars.buttons["Waypoints"].tap()
        let route = app.buttons["library-graphic-Back Recon track"]; reveal(route); XCTAssertTrue(route.waitForExistence(timeout: 5))
        let routeActions = app.buttons["Actions for graphic Back Recon track"]; reveal(routeActions); routeActions.tap(); app.buttons["Route card"].tap()
        XCTAssertTrue(app.buttons["follow-route"].waitForExistence(timeout: 5)); capture("track-backtrack-route-card")
        app.buttons["Done"].tap()
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch(); folder("Recon")
        reveal(route); XCTAssertTrue(route.exists)
        let original = app.buttons["library-track-Recon track"]; reveal(original); XCTAssertTrue(original.exists)
    }
    func testBacktrackFromTrackDetailsReturnsToMapWithoutStartingGuide() {
        app.buttons["open-field-library"].tap(); app.buttons["track-Recon track"].tap()
        let create = app.buttons["track-create-backtrack"]; XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.buttons["map-measure"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists)
    }
}
