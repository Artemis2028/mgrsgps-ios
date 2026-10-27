import XCTest

final class NavigationLaneWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestLanes","-uiTestBoundaryMap","-startTab","map"]; app.launch()
    }
    private func openLibrary() {
        let button = app.buttons["map-lanes"]; XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        XCTAssertTrue(app.buttons["create-nav-lane"].waitForExistence(timeout: 8))
    }
    private func role(_ title: String) { app.segmentedControls["lane-line-role"].buttons[title].tap() }
    private func link(_ id: String) {
        app.buttons["lane-use-line"].tap()
        let button = app.buttons["lane-link-"+id]; XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.buttons["Draw a replacement line"].waitForExistence(timeout: 5))
    }
    private func reviewAndSave(_ name: String,wholeRoute: Bool = false) {
        app.buttons["review-nav-lane"].tap()
        let field = app.textFields["nav-lane-name"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); replaceTextInput(field,name)
        if wholeRoute {
            let scope = app.segmentedControls.buttons["Whole route"]
            for _ in 0..<4 { if scope.isHittable { break }; app.swipeUp() }
            scope.tap()
        }
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@","lane-target-")).firstMatch
        for _ in 0..<4 { if target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap()
        let save = app.buttons["save-nav-lane"]; XCTAssertTrue(save.isEnabled,app.debugDescription); save.tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [finished],timeout: 10),.completed,app.debugDescription)
        XCTAssertFalse(app.buttons["review-nav-lane"].exists)
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testNativeBackupRestoresHiddenRouteLaneAndFeedsRouteCardPDF() {
        openLibrary(); app.buttons["create-nav-lane"].tap()
        link("lane-left"); role("Right"); link("lane-right"); role("Backstop"); link("lane-backstop")
        reviewAndSave("Route corridor",wholeRoute: true)
        app.buttons["Toggle map night mode"].tap()
        openLibrary(); app.switches["Visible on map"].coordinate(withNormalizedOffset: .init(dx: 0.9,dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Hidden on map · guidance still enabled"].waitForExistence(timeout: 5))
        app.navigationBars["Navigation lanes"].buttons["Done"].tap(); app.buttons["Waypoints"].tap()
        let filename = app.textFields["export-filename"]
        app.buttons["Waypoint actions"].tap(); tapNativeMenuItem(app.buttons["Export"]); tapNativeMenuItem(app.buttons["Export backup"],revealing: filename)
        XCTAssertTrue(filename.waitForExistence(timeout: 15),app.debugDescription)
        let name = "lane-backup-ui-"+String(UUID().uuidString.prefix(8))
        replaceTextInput(filename,name); saveNativeFile(in: app)
        let section = app.buttons["library-nav-lanes"]; XCTAssertTrue(section.waitForExistence(timeout: 10)); section.tap()
        app.buttons["Delete lane"].tap(); let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); tapNativeMenuItem(confirmation.buttons["Delete lane"])
        XCTAssertFalse(app.staticTexts["Route corridor"].waitForExistence(timeout: 2))
        app.navigationBars["Navigation lanes"].buttons["Done"].tap()
        app.buttons["Waypoint actions"].tap(); tapNativeMenuItem(app.buttons["Import backup"])
        openSavedNativeFile(name,in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","Restored"),object: app.staticTexts["library-status"])
        XCTAssertEqual(XCTWaiter.wait(for: [restored],timeout: 15),.completed,app.debugDescription)
        XCTAssertTrue(app.staticTexts["library-status"].label.contains("1 navigation lane")); capture("lane-backup-restored-night")
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch(); app.buttons["Waypoints"].tap()
        XCTAssertTrue(section.waitForExistence(timeout: 10)); section.tap()
        XCTAssertTrue(app.staticTexts["Whole route: Lane patrol"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hidden on map · guidance still enabled"].exists)
        app.navigationBars["Navigation lanes"].buttons["Done"].tap()
        app.buttons["open-field-library"].tap(); app.buttons["route-Lane patrol"].tap()
        let limits = app.staticTexts["route-card-limits-1"]
        for _ in 0..<6 { if limits.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(limits.waitForExistence(timeout: 10),app.debugDescription)
        XCTAssertEqual(limits.label,"L: Creek bank · R: Right road · BS: Power line"); capture("lane-route-card-limits-night")
        let export = app.buttons["prepare-strip-map-pdf"]
        for _ in 0..<6 { if export.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(export.isEnabled); export.tap()
        XCTAssertTrue(app.navigationBars["Strip map PDF"].waitForExistence(timeout: 15),app.debugDescription)
        capture("lane-strip-map-pdf-preview")
    }
    func testLinkedLaneSaveHideEditRelaunchAndDeleteRetainsGraphics() {
        openLibrary(); app.buttons["create-nav-lane"].tap()
        link("lane-left"); role("Right"); link("lane-right"); role("Backstop"); link("lane-backstop")
        reviewAndSave("Creek corridor")
        app.buttons["Toggle map night mode"].tap(); capture("nav-lane-linked-night-map")
        openLibrary(); XCTAssertTrue(app.buttons["Edit lane"].waitForExistence(timeout: 5))
        let visibility = app.switches["Visible on map"]
        visibility.coordinate(withNormalizedOffset: .init(dx: 0.9,dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Hidden on map · guidance still enabled"].waitForExistence(timeout: 5)); capture("nav-lane-hidden-library-night")
        app.buttons["Edit lane"].tap(); XCTAssertTrue(app.buttons["review-nav-lane"].waitForExistence(timeout: 8))
        reviewAndSave("Renamed corridor")
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        let section = app.buttons["library-nav-lanes"]
        tapNativeMenuItem(app.buttons["Waypoints"],revealing: section)
        XCTAssertTrue(section.waitForExistence(timeout: 8)); section.tap()
        XCTAssertTrue(app.staticTexts["Renamed corridor"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Hidden on map · guidance still enabled"].exists)
        app.buttons["Edit lane"].tap()
        XCTAssertTrue(app.buttons["review-nav-lane"].waitForExistence(timeout: 10),"Waypoints must open the lane's map editor")
        reviewAndSave("Final corridor")
        app.buttons["Waypoints"].tap(); section.tap()
        XCTAssertTrue(app.staticTexts["Final corridor"].waitForExistence(timeout: 8))
        app.buttons["Delete lane"].tap()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); tapNativeMenuItem(confirmation.buttons["Delete lane"])
        XCTAssertFalse(app.staticTexts["Final corridor"].waitForExistence(timeout: 2))
        app.navigationBars["Navigation lanes"].buttons["Done"].tap()
        app.buttons["Map"].tap(); app.buttons["map-graphics"].tap()
        XCTAssertTrue(app.buttons["edit-graphic-Creek bank"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["edit-graphic-Right road"].exists)
    }
    func testDrawLaneLineInsertAndDragBendThenSave() {
        openLibrary(); app.buttons["create-nav-lane"].tap()
        app.coordinate(withNormalizedOffset: .init(dx: 0.25,dy: 0.50)).tap()
        app.coordinate(withNormalizedOffset: .init(dx: 0.25,dy: 0.35)).tap()
        let count = app.staticTexts["lane-point-count"]
        let two = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","2 points"),object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [two],timeout: 5),.completed,app.debugDescription)
        let midpoint = app.buttons["graphic-midpoint-0"]; XCTAssertTrue(midpoint.waitForExistence(timeout: 5))
        midpoint.coordinate(withNormalizedOffset: .init(dx: 0.5,dy: 0.5)).press(forDuration: 0.8,thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.22,dy: 0.43)))
        let three = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","3 points"),object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [three],timeout: 5),.completed)
        XCTAssertFalse(app.buttons["Add kink"].exists); capture("nav-lane-drawn-bend")
        role("Right"); link("lane-right"); role("Backstop"); link("lane-backstop")
        reviewAndSave("Drawn corridor"); capture("nav-lane-drawn-saved-map")
        XCTAssertFalse(app.buttons["stop-boundary"].exists)
        openLibrary(); app.buttons["Edit lane"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","3 points"),object: app.staticTexts["lane-point-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [restored],timeout: 8),.completed)
    }
    func testObjectiveOnBackstopShowsErrorAndCanBeCorrectedInDayAndNight() {
        app.terminate();app.launchArguments += ["-uiTestLaneInvalidObjective"];app.launch()
        openLibrary();app.buttons["create-nav-lane"].tap()
        link("lane-left");role("Right");link("lane-right");role("Backstop");link("lane-backstop")
        app.buttons["review-nav-lane"].tap()
        let bad=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label BEGINSWITH %@","lane-target-","Checkpoint on backstop")).firstMatch
        for _ in 0..<5 {if bad.isHittable {break};app.swipeUp()}
        bad.tap()
        let error=app.staticTexts["The point is on the backstop; the backstop goes past the point"]
        XCTAssertTrue(error.waitForExistence(timeout:5));XCTAssertFalse(app.buttons["save-nav-lane"].isEnabled)
        capture("lane-objective-backstop-error-day")
        app.buttons["Back to map"].tap();app.buttons["Toggle map night mode"].tap();app.buttons["review-nav-lane"].tap()
        XCTAssertTrue(error.waitForExistence(timeout:5));XCTAssertFalse(app.buttons["save-nav-lane"].isEnabled)
        capture("lane-objective-backstop-error-night")
        let valid=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label BEGINSWITH %@","lane-target-","Lane OBJ")).firstMatch
        for _ in 0..<5 {if valid.isHittable {break};app.swipeDown()}
        valid.tap();XCTAssertTrue(app.buttons["save-nav-lane"].isEnabled);app.buttons["save-nav-lane"].tap()
        XCTAssertFalse(app.buttons["save-nav-lane"].waitForExistence(timeout:2))
    }

}
