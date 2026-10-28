import XCTest

final class FieldFixWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-uiTesting","-uiTestTerrainNoData","-uiTestBoundaryMap","-startTab","map"]; app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
    }
    private func open(_ mode: String) {
        let menu = mapTool(app, "map-measure"); XCTAssertTrue(menu.waitForExistence(timeout: 10)); tapNativeMenuItem(menu,revealing:app.navigationBars["Map tools"])
        tapNativeMenuItem(app.buttons["field-"+mode.lowercased()])
        capture("field-"+mode.lowercased()+"-opened")
        XCTAssertTrue(app.navigationBars[mode].waitForExistence(timeout: 8),app.debugDescription)
        choose(1,"West observer"); choose(2,"East target")
    }
    private func choose(_ index: Int,_ name: String) {
        let picker = app.buttons["field-fix-point-\(index)"]; reveal(picker); tapNativeMenuItem(picker)
        let choice = app.buttons["field-fix-choice-\(index)-\(name)"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@",name),object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [selected],timeout: 5),.completed,app.debugDescription)
    }
    private func angle(_ index: Int,_ text: String) {
        let field = app.textFields["field-fix-azimuth-\(index)"]; reveal(field)
        replaceTextInput(field,text)
        XCTAssertEqual(field.value as? String,text)
        let done = app.buttons["Done"]; XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(done.frame.intersects(field.frame),"Keyboard Done covers the azimuth input")
        if index == 1 { capture("field-fix-azimuth-keyboard") }
        done.tap()
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testIntersectionShowResectionSaveAndRelaunchWithoutStartingNavigation() {
        let before = app.buttons["map-centre-summary"].label
        open("Intersection"); angle(1,"45"); angle(2,"315")
        let grid = app.staticTexts["field-fix-grid"]; reveal(grid); XCTAssertTrue(grid.waitForExistence(timeout: 8)); XCTAssertTrue(grid.label.hasPrefix("40R BN"))
        let expected = grid.label
        XCTAssertTrue(app.staticTexts["field-fix-ranges"].label.contains("1.08 km")); capture("field-intersection-result")
        let show = app.buttons["field-fix-show"]; reveal(show); show.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@",before),object: app.buttons["map-centre-summary"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed],timeout: 8),.completed)
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists); XCTAssertFalse(app.buttons["boundary-monitor-banner"].exists)
        open("Resection"); angle(1,"225"); angle(2,"135")
        reveal(grid); XCTAssertTrue(grid.waitForExistence(timeout: 8)); XCTAssertEqual(grid.label,expected); capture("field-resection-result")
        let name = app.textFields["field-fix-name"]; reveal(name); name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: (name.value as? String ?? "").count)+"Resection check")
        app.buttons["Done"].tap(); let save = app.buttons["field-fix-save"]; reveal(save); save.tap()
        XCTAssertTrue(mapTool(app, "map-measure").waitForExistence(timeout: 8))
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        app.tabBars.buttons["Waypoints"].tap()
        XCTAssertTrue(app.buttons["edit-waypoint-Resection check"].waitForExistence(timeout: 8)); capture("field-fix-saved-waypoint")
    }
    func testInvalidAzimuthAndPoorCutStayExplicitInNightMode() {
        mapTool(app, "Toggle map night mode").tap(); open("Resection")
        angle(1,"-1"); angle(2,"135")
        let message = app.staticTexts["field-fix-message"]; reveal(message)
        XCTAssertTrue(message.label.contains("0 to 360")); XCTAssertFalse(app.buttons["field-fix-save"].isEnabled)
        // Return to the first input after inspecting the lower validation row.
        let firstInput = app.textFields["field-fix-azimuth-1"]
        for _ in 0..<6 { if firstInput.isHittable { break }; app.tables.firstMatch.swipeDown() }
        XCTAssertTrue(firstInput.isHittable,app.debugDescription)
        angle(1,"260"); angle(2,"100")
        let warning = app.staticTexts["field-fix-poor-cut"]; reveal(warning)
        XCTAssertTrue(warning.waitForExistence(timeout: 8)); capture("field-fix-night-poor-cut")
        app.navigationBars["Resection"].buttons["Close"].tap()
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists)
    }
    func testPointSearchAndCancelPreservesReference() {
        mapTool(app, "Toggle map night mode").tap()
        open("Resection")
        let point = app.buttons["field-fix-point-1"]
        let original = point.label
        tapNativeMenuItem(point)
        let search = app.searchFields["Search points"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Unknown reference XYZ")
        XCTAssertTrue(app.staticTexts["No matching points"].waitForExistence(timeout: 5))
        capture("field-point-search-empty")
        let cancel = app.buttons["field-fix-point-1-cancel"]
        if !cancel.exists {
            // iOS 26's expanded search replaces the normal navigation items.
            let closeSearch = app.buttons["close"].firstMatch
            XCTAssertTrue(closeSearch.waitForExistence(timeout: 5)); closeSearch.tap()
        }
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in cancel.exists || point.isHittable },object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [restored],timeout: 5),.completed)
        if cancel.exists { cancel.tap() }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"),object: point)
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 5),.completed)
        XCTAssertEqual(point.label,original)
        tapNativeMenuItem(point)
        XCTAssertTrue(app.buttons["field-fix-choice-1-East target"].waitForExistence(timeout: 5))
        app.buttons["field-fix-point-1-cancel"].tap()
        XCTAssertEqual(point.label,original)
        XCTAssertFalse(app.buttons["navigation-session-banner"].exists)
    }

}
