import XCTest

final class WaypointWorkflowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-startTab", "waypoints"]
        app.launch()
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            if alert.buttons["Allow While Using App"].exists {
                alert.buttons["Allow While Using App"].tap()
                return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testCoordinateEntryMapNavigationAndFolderVisibility() {
        addWaypoint(name: "Objective", grid: "40R BN 3412 0700")
        addWaypoint(name: "Rally point", grid: "40R BN 3450 0720")
        capture("waypoints-glass")
        app.tabBars.buttons["Map"].tap()
        app.buttons["Show all visible data"].tap()
        let waypoint = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "map-waypoint-", "Objective")).firstMatch
        XCTAssertTrue(waypoint.waitForExistence(timeout: 15), app.debugDescription)
        capture("map-waypoint-overlays")
        waypoint.tap()
        XCTAssertTrue(app.buttons["map-navigate-waypoint"].waitForExistence(timeout: 5))
        capture("map-selected-waypoint")
        app.buttons["map-navigate-waypoint"].tap()
        XCTAssertTrue(app.staticTexts["Objective"].waitForExistence(timeout: 5))
        capture("navigate-glass")
        app.tabBars.buttons["Waypoints"].tap()
        app.buttons["folder-visibility-Base"].tap()
        app.tabBars.buttons["Map"].tap()
        XCTAssertFalse(app.buttons["Show all visible data"].isEnabled)
        capture("map-folder-hidden")
        app.tabBars.buttons["Waypoints"].tap()
        app.buttons["folder-visibility-Base"].tap()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["Show all visible data"].isEnabled)
    }

    func testBlankInvalidAndDecimalCoordinatesThenEditAndRelaunch() {
        app.buttons["add-waypoint"].tap()
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replace(name,with: "Southern point")
        XCTAssertFalse(app.buttons["waypoint-save"].isEnabled)
        dismissFieldKeyboard()
        selectNativeSegment(app.segmentedControls.buttons["Lat / Lon"])
        let latitude = app.textFields["waypoint-latitude"]
        XCTAssertTrue(latitude.waitForExistence(timeout: 5))
        replace(latitude,with: "-91")
        let longitude = app.textFields["waypoint-longitude"]
        replace(longitude,with: "151.2093")
        XCTAssertFalse(app.buttons["waypoint-save"].isEnabled)
        replace(latitude, with: "-33.8688")
        XCTAssertTrue(app.buttons["waypoint-save"].isEnabled)
        capture("coordinate-entry-decimal")
        app.buttons["waypoint-save"].tap()
        let edit = app.buttons["edit-waypoint-Southern point"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        tapNativeMenuItem(app.segmentedControls.buttons["Lat / Lon"])
        XCTAssertEqual(app.textFields["waypoint-latitude"].value as? String, "-33.8688")
        replace(app.textFields["waypoint-latitude"], with: "-34.0")
        app.buttons["waypoint-save"].tap()
        app.terminate()
        app.launchArguments += ["-keepUITestData"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-waypoint-Southern point"].waitForExistence(timeout: 5))
        app.buttons["edit-waypoint-Southern point"].tap()
        tapNativeMenuItem(app.segmentedControls.buttons["Lat / Lon"])
        XCTAssertEqual(app.textFields["waypoint-latitude"].value as? String, "-34.0")
    }

    func testMapCentreCanCreateWaypoint() {
        app.tabBars.buttons["Map"].tap()
        app.buttons["Add waypoint at map centre"].tap()
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Map centre")
        XCTAssertTrue(app.buttons["waypoint-save"].isEnabled)
        capture("coordinate-entry-map-centre")
        app.buttons["waypoint-save"].tap()
        XCTAssertTrue(app.buttons["map-navigate-waypoint"].waitForExistence(timeout: 5))
    }

    func testNightModeKeepsSettingsAndWaypointEntryUsable() {
        app.tabBars.buttons["Position"].tap()
        app.buttons["Settings"].tap()
        let night = app.switches["Red-on-black, to keep night vision"]
        XCTAssertTrue(night.waitForExistence(timeout: 5))
        setNativeSwitch(night,to: true)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@","1"),object: night)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled],timeout: 5),.completed,night.debugDescription)
        XCTAssertTrue(app.buttons["Done"].exists, "Changing night mode must preserve the settings sheet")
        app.buttons["Done"].tap()
        XCTAssertFalse(app.tabBars.buttons["Waypoints"].exists, "Night mode uses only the opaque field bar")
        app.buttons["Waypoints"].tap()
        addWaypoint(name: "Night point", grid: "40R BN 3412 0700")
        capture("waypoints-night")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            let frame = self.app.windows.firstMatch.frame
            return frame.width > frame.height
        },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated],timeout: 8),.completed,app.debugDescription)
        // A real interaction waits for rotation/layout to settle before the
        // screenshot; existence alone can succeed during the transition.
        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Night point"].waitForExistence(timeout: 5))
        capture("waypoints-landscape")
        // Older iOS can expose invalid activation points after rotation even
        // for visible controls. Exercise the actual frames and verify results.
        tapNativeMenuItem(app.buttons["edit-waypoint-Night point"])
        XCTAssertTrue(app.textFields["waypoint-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["waypoint-name"].value as? String,"Night point")
        tapNativeMenuItem(app.buttons["Cancel"])
        tapNativeMenuItem(app.buttons["add-waypoint"])
        XCTAssertTrue(app.textFields["waypoint-name"].waitForExistence(timeout: 5))
        tapNativeMenuItem(app.buttons["Cancel"])
        tapNativeMenuItem(app.buttons["open-field-library"])
        XCTAssertTrue(app.buttons["create-route"].waitForExistence(timeout: 5))
        tapNativeMenuItem(app.buttons["Done"])
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Position"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(night.waitForExistence(timeout: 5))
        setNativeSwitch(night,to: false)
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@","0"),object: night)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled],timeout: 5),.completed,night.debugDescription)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Waypoints"].waitForExistence(timeout: 5))
    }

    func testGpxRoutesAndTracksImportMapAndPersistence() {
        let xml = """
        <gpx xmlns="http://www.topografix.com/GPX/1/1"><rte><name>Patrol</name><rtept lat="24.4539" lon="54.3773"/><rtept lat="24.4549" lon="54.3783"/></rte><trk><name>Recorded walk</name><trkseg><trkpt lat="24.4539" lon="54.3773"/><trkpt lat="24.4545" lon="54.3790"/></trkseg></trk></gpx>
        """
        app.buttons["Waypoint actions"].tap()
        tapNativeMenuItem(app.buttons["Paste text"])
        tapNativeMenuItem(app.buttons["Paste GPX"])
        let text = app.textViews["gpx-import-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap(); text.typeText(xml)
        app.buttons["preview-interchange"].tap()
        XCTAssertTrue(app.buttons["confirm-gpx-import"].waitForExistence(timeout: 10))
        app.buttons["confirm-gpx-import"].tap()
        app.buttons["open-field-library"].tap()
        XCTAssertTrue(app.buttons["track-Recorded walk"].waitForExistence(timeout: 5))
        app.buttons["route-Patrol"].tap()
        XCTAssertTrue(app.buttons["generate-route-waypoints"].waitForExistence(timeout: 5))
        capture("route-card")
        app.buttons["generate-route-waypoints"].tap()
        app.buttons["Navigate to vertex 2"].tap()
        XCTAssertTrue(app.staticTexts["Patrol WP 2"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Map"].tap()
        app.buttons["Show all visible data"].tap()
        XCTAssertTrue(app.staticTexts["map-field-overlays"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["map-field-overlays"].label, "1 routes · 1 tracks")
        capture("routes-tracks-map")
        app.terminate()
        app.launchArguments += ["-keepUITestData"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-waypoint-Patrol WP 2"].waitForExistence(timeout: 5))
        app.buttons["open-field-library"].tap()
        app.buttons["track-Recorded walk"].tap()
        let visibility = app.switches["Visible on map"]
        XCTAssertEqual(visibility.value as? String, "1")
        visibility.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@","0"),object: visibility)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden],timeout: 5),.completed,visibility.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.tabBars.buttons["Map"].tap()
        let updated = NSPredicate(format: "label == %@", "1 routes · 0 tracks")
        expectation(for: updated, evaluatedWith: app.staticTexts["map-field-overlays"])
        waitForExpectations(timeout: 5)
    }

    func testRouteCreationAndRepeatedWaypointGeneration() {
        addWaypoint(name: "Start", grid: "40R BN 3412 0700")
        addWaypoint(name: "Finish", grid: "40R BN 3450 0720")
        app.buttons["open-field-library"].tap()
        app.buttons["create-route"].tap()
        let name = app.textFields["route-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Training\n")
        XCTAssertFalse(app.buttons["save-route"].isEnabled)
        tapNativeMenuItem(app.buttons["append-route-waypoint"],revealing: app.buttons["route-append-choice-Start"])
        tapNativeMenuItem(app.buttons["route-append-choice-Start"],revealing: app.staticTexts.matching(identifier: "route-vertex-0").firstMatch)
        XCTAssertTrue(app.staticTexts.matching(identifier: "route-vertex-0").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-route"].isEnabled)
        tapNativeMenuItem(app.buttons["append-route-waypoint"],revealing: app.buttons["route-append-choice-Finish"])
        tapNativeMenuItem(app.buttons["route-append-choice-Finish"],revealing: app.staticTexts.matching(identifier: "route-vertex-1").firstMatch)
        XCTAssertTrue(app.staticTexts.matching(identifier: "route-vertex-1").firstMatch.waitForExistence(timeout: 5))
        let save = app.buttons["save-route"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"),object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 5),.completed)
        save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [saved],timeout: 10),.completed,app.debugDescription)
        XCTAssertTrue(app.buttons["route-Training"].waitForExistence(timeout: 5))
        app.buttons["route-Training"].tap()
        app.buttons["generate-route-waypoints"].tap()
        app.buttons["generate-route-waypoints"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Training WP 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "edit-waypoint-Training WP 2").count, 1)
        capture("route-generated-waypoints")
    }

    private func addWaypoint(name: String, grid: String) {
        app.buttons["add-waypoint"].tap()
        let nameField = app.textFields["waypoint-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        replace(nameField,with: name)
        let gridField = app.textFields["waypoint-mgrs"]
        replace(gridField,with: grid)
        XCTAssertTrue(app.buttons["waypoint-save"].isEnabled)
        capture("coordinate-entry-mgrs")
        app.buttons["waypoint-save"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-\(name)"].waitForExistence(timeout: 5))
    }

    private func replace(_ field: XCUIElement, with text: String) {
        replaceTextInput(field,text)
        XCTAssertEqual(field.value as? String, text)
        dismissFieldKeyboard()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
