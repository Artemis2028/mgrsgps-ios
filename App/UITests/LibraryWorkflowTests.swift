import XCTest

final class LibraryWorkflowTests: XCTestCase {
    func testDeferredWaypointStartupRetainsTargetAndReceivesRecordingDeepLinkInDayAndNight() {
        app.terminate()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestTargetSelection","-startTab","waypoints"]
        app.launch()
        XCTAssertTrue(app.buttons["open-field-library"].waitForExistence(timeout: 10))
        for night in [false,true] {
            if night { app.tabBars.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap() }
            app.terminate()
            app.launchArguments = ["-uiTesting","-keepUITestData","-uiTestDeferredFieldLoad","-uiTestSlowWaypointStartup","-startTab","waypoints"]
            app.launch()
            let gate = app.buttons["waypoint-startup-continue"]
            XCTAssertTrue(gate.waitForExistence(timeout: 8),app.debugDescription)
            XCTAssertFalse(app.buttons["Waypoint actions"].exists,"Live library services must not exist before waypoints finish loading")
            print("WAYPOINT_STARTUP_RECORDING_LINK_READY \(night)")
            let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
            let queued = app.staticTexts["waypoint-startup-queued-links"]
            let handoff = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
                open.exists || (queued.exists && queued.label == "Queued links 1")
            },object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [handoff],timeout: 10),.completed,"Wait for the OS confirmation or its remembered approval")
            if open.exists { open.tap() }
            let received = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Queued links 1'"),object: queued)
            XCTAssertEqual(XCTWaiter.wait(for: [received],timeout: 20),.completed,"Host must send gridfix://recording during the held waypoint read")
            capture(night ? "waypoint-startup-loading-night" : "waypoint-startup-loading-day")
            gate.tap()
            XCTAssertTrue(app.navigationBars["Track recording"].waitForExistence(timeout: 15),app.debugDescription)
            XCTAssertTrue(app.buttons["start-recording"].exists,"Opening the deep link must not start recording")
            XCTAssertFalse(app.buttons["save-recording"].exists)
            capture(night ? "waypoint-startup-queued-recorder-night" : "waypoint-startup-queued-recorder-day")
            tapNativeMenuItem(app.navigationBars["Track recording"].buttons["Done"])
            app.buttons["Navigate"].tap()
            XCTAssertTrue(app.staticTexts["Alpha"].waitForExistence(timeout: 8),app.debugDescription)
            app.buttons["Waypoints"].tap(); app.buttons["open-field-library"].tap()
            XCTAssertTrue(app.buttons["route-Recon route"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["track-Recon track"].exists)
            capture(night ? "waypoint-startup-library-retained-night" : "waypoint-startup-library-retained-day")
            tapNativeMenuItem(app.navigationBars.buttons["Done"])
        }
    }

    func testDeferredColdLibraryLoadRetainsTracksRoutesAndReadableDayNightLoading() {
        for night in [false,true] {
            if night {
                app.tabBars.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap()
            }
            app.terminate()
            app.launchArguments = ["-uiTesting","-uiTestLibrary","-keepUITestData","-uiTestDeferredFieldLoad","-uiTestSlowFieldLoad","-startTab","waypoints"]
            app.launch()
            let loading = app.buttons["field-library-load-continue"]
            XCTAssertTrue(loading.waitForExistence(timeout: 5),app.debugDescription)
            XCTAssertFalse(app.buttons["Waypoint actions"].isEnabled)
            capture(night ? "field-startup-loading-night" : "field-startup-loading-day")
            loading.tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: loading)
            XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 20),.completed,app.debugDescription)
            let open = app.buttons["open-field-library"]
            XCTAssertTrue(open.waitForExistence(timeout: 8)); open.tap()
            XCTAssertTrue(app.buttons["route-Recon route"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["track-Recon track"].exists)
            capture(night ? "field-startup-loaded-night" : "field-startup-loaded-day")
            tapNativeMenuItem(app.navigationBars.buttons["Done"])
        }
    }
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
        app.buttons["Selected item actions"].tap(); tapNativeMenuItem(app.buttons["library-delete-selected"])
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        tapNativeMenuItem(confirmation.buttons["Delete"])
        XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].waitForExistence(timeout: 5),app.debugDescription)
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        folder("Recon"); XCTAssertTrue(app.staticTexts["Nothing in Recon yet."].waitForExistence(timeout: 5))
        folder("Base"); XCTAssertTrue(app.buttons["edit-waypoint-Alpha"].exists)
        let checkpoint = app.buttons["library-graphic-Base checkpoint"]; reveal(checkpoint); XCTAssertTrue(checkpoint.exists)
        capture("library-after-batch-delete")
    }
    func testRenameFolderMovesAllRecordTypesThenKeepContentsInBase() {
        folder("Recon"); app.buttons["Folder options"].tap(); tapNativeMenuItem(app.buttons["Rename folder"])
        let name = app.textFields["library-folder-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        replaceTextInput(name,"Patrol")
        XCTAssertEqual(name.value as? String,"Patrol")
        app.buttons["library-folder-save"].tap()
        XCTAssertTrue(app.buttons["Patrol"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("1 waypoints · 1 graphics · 1 tracks"))
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch(); folder("Patrol")
        XCTAssertTrue(app.buttons["edit-waypoint-Bravo"].exists)
        app.buttons["Folder options"].tap(); tapNativeMenuItem(app.buttons["Delete folder"]); tapNativeMenuItem(app.buttons["Keep contents in Base"])
        capture("library-folder-after-keep")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: app.buttons["Patrol"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone],timeout: 5),.completed,app.debugDescription)
        folder("Base"); XCTAssertTrue(app.staticTexts["library-listed-count"].label.contains("3 waypoints · 2 graphics · 1 tracks"))
        capture("library-folder-kept-in-base")
        let clear = app.buttons["library-clear-graphics"]; reveal(clear); clear.tap()
        app.alerts.buttons["Delete"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@","3 waypoints · 0 graphics · 1 tracks"),object: app.staticTexts["library-listed-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [cleared],timeout: 5),.completed,app.debugDescription)
    }
    func testMoveTrackAndViewHiddenTrackWithoutChangingItsVisibilityFlag() {
        folder("Recon")
        let actions = app.buttons["Actions for track Recon track"]; reveal(actions); actions.tap(); app.buttons["Hide on map"].tap()
        app.buttons["folder-visibility-Recon"].tap()
        reveal(actions); actions.tap(); app.buttons["Show on map"].tap()
        XCTAssertTrue(mapTool(app, "map-measure").waitForExistence(timeout: 10))
        let overlays = mapReadout(app, "map-field-overlays")
        XCTAssertTrue(overlays.waitForExistence(timeout: 10)); XCTAssertTrue(overlays.label.contains("1 tracks"))
        capture("library-track-fit-day")
        mapTool(app, "Toggle map night mode").tap()
        capture("library-track-fit-night")
        app.buttons["Waypoints"].tap()
        reveal(actions); actions.tap(); XCTAssertTrue(app.buttons["Make visible on map"].exists)
        app.buttons["Move to folder"].tap()
        let destination = app.buttons["move-track-to-Base"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        capture("library-track-folder-picker")
        // Choosing a folder works across its entire row, outside the text.
        destination.coordinate(withNormalizedOffset: .init(dx: 0.9,dy: 0.5)).tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: app.navigationBars["Move Recon track"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed],timeout: 5),.completed)
        let movedOut = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: app.buttons["library-track-Recon track"])
        XCTAssertEqual(XCTWaiter.wait(for: [movedOut],timeout: 5),.completed)
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
        app.tabBars.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap()
        folder("Recon"); selectAll(); selected(3); capture("library-night-selection")
        app.buttons["library-selection-done"].tap()
        app.buttons["Folder options"].tap()
        XCTAssertTrue(app.buttons["Rename folder"].waitForExistence(timeout: 5)); capture("library-night-folder-options")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.textFields["library-folder-name"].exists)
        XCTAssertTrue(app.buttons["Folder options"].isHittable)
        app.buttons["Folder options"].tap(); tapNativeMenuItem(app.buttons["Rename folder"])
        XCTAssertTrue(app.textFields["library-folder-name"].waitForExistence(timeout: 5)); capture("library-night-folder-form")
        app.buttons["Cancel"].tap()
    }
    func testGraphicChoicesKeepCancellationVisibilityAndRouteCardInDayAndNight() {
        for night in [false,true] {
            if night { app.tabBars.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap() }
            folder("Recon")
            let actions = app.buttons["Actions for graphic Recon route"]
            reveal(actions); actions.tap()
            XCTAssertTrue(app.navigationBars["Recon route"].waitForExistence(timeout: 5))
            capture(night ? "graphic-choices-night" : "graphic-choices-day")
            app.buttons["Cancel"].tap()
            let hidden = app.images["library-graphic-hidden-Recon route"]
            XCTAssertFalse(hidden.exists)
            reveal(actions); actions.tap(); tapNativeMenuItem(app.buttons["Hide on map"])
            XCTAssertTrue(hidden.waitForExistence(timeout: 8))
            reveal(actions); actions.tap(); tapNativeMenuItem(app.buttons["Make visible on map"])
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: hidden)
            XCTAssertEqual(XCTWaiter.wait(for: [visible],timeout: 8),.completed)
            reveal(actions); actions.tap(); tapNativeMenuItem(app.buttons["Route card"])
            XCTAssertTrue(app.buttons["follow-route"].waitForExistence(timeout: 8))
            capture(night ? "graphic-route-card-night" : "graphic-route-card-day")
            app.navigationBars.buttons["Done"].tap()
            reveal(actions); actions.tap(); tapNativeMenuItem(app.buttons["Delete"])
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["library-graphic-Recon route"].exists)
        }
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch(); folder("Recon")
        XCTAssertTrue(app.buttons["library-graphic-Recon route"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.images["library-graphic-hidden-Recon route"].exists)
    }
    func testBacktrackFromMixedLibraryShowsSavedRouteAndLeavesNavigationIdle() {
        folder("Recon")
        let actions = app.buttons["Actions for track Recon track"]; reveal(actions); actions.tap()
        app.buttons["backtrack-track-Recon track"].tap()
        XCTAssertTrue(mapTool(app, "map-measure").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists); XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
        capture("track-backtrack-map")
        app.tabBars.buttons["Waypoints"].tap()
        let route = app.buttons["library-graphic-Back Recon track"]; reveal(route); XCTAssertTrue(route.waitForExistence(timeout: 5))
        let routeActions = app.buttons["Actions for graphic Back Recon track"]; reveal(routeActions)
        tapNativeMenuItem(routeActions,revealing: app.buttons["Route card"])
        tapNativeMenuItem(app.buttons["Route card"],revealing: app.buttons["follow-route"])
        XCTAssertTrue(app.buttons["follow-route"].waitForExistence(timeout: 5)); capture("track-backtrack-route-card")
        app.buttons["Done"].tap()
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch(); folder("Recon")
        reveal(route); XCTAssertTrue(route.exists)
        let original = app.buttons["library-track-Recon track"]; reveal(original); XCTAssertTrue(original.exists)
    }
    func testBacktrackFromTrackDetailsReturnsToMapWithoutStartingGuide() {
        app.buttons["open-field-library"].tap(); app.buttons["track-Recon track"].tap()
        let create = app.buttons["track-create-backtrack"]; XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(mapTool(app, "map-measure").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists)
    }
}
