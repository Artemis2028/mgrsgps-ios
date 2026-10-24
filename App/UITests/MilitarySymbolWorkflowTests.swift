import XCTest

final class MilitarySymbolWorkflowTests: XCTestCase {
    func testSelectExtendedUnitEditEchelonPersistAndRenderOnMap() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting","-startTab","waypoints"]; app.launch()
        app.buttons["add-waypoint"].tap()
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Airborne element\n")
        let grid = app.textFields["waypoint-mgrs"]
        grid.tap(); grid.typeText("40R BN 3412 0700\n")
        // Dismiss the keyboard before navigating down the form.
        app.swipeUp()
        let choose = app.buttons["choose-military-symbol"]
        for _ in 0..<5 { if choose.isHittable { break }; app.swipeUp() }
        choose.tap()
        app.segmentedControls["symbol-category"].buttons["Units"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("airborne infantry")
        let symbol = app.buttons["symbol-inf_abn"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5)); symbol.tap()
        let echelon = app.buttons["unit-echelon"]
        XCTAssertTrue(echelon.waitForExistence(timeout: 5)); echelon.tap(); app.buttons["Platoon"].tap()
        XCTAssertTrue(echelon.label.contains("Platoon") || (echelon.value as? String) == "Platoon", echelon.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "military-symbol-editor"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.buttons["waypoint-save"].isHittable)
        app.buttons["waypoint-save"].tap()
        app.terminate(); app.launchArguments += ["-keepUITestData"]; app.launch()
        app.buttons["edit-waypoint-Airborne element"].tap()
        XCTAssertTrue(app.staticTexts["Friendly Airborne infantry"].waitForExistence(timeout: 5))
        let savedEchelon = app.buttons["unit-echelon"]
        for _ in 0..<5 { if savedEchelon.exists { break }; app.swipeUp() }
        XCTAssertTrue(savedEchelon.waitForExistence(timeout: 5))
        XCTAssertTrue(savedEchelon.label.contains("Platoon") || (savedEchelon.value as? String) == "Platoon", savedEchelon.debugDescription)
        app.buttons["Cancel"].tap(); app.tabBars.buttons["Map"].tap()
        let fit = app.buttons["Show all visible data"]
        XCTAssertTrue(fit.waitForExistence(timeout: 10)); fit.tap()
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@","map-waypoint-")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        let mapShot = XCTAttachment(screenshot: app.screenshot()); mapShot.name = "military-unit-map"; mapShot.lifetime = .keepAlways; add(mapShot)
        app.buttons["Toggle map night mode"].tap()
        XCTAssertFalse(app.tabBars.buttons["Waypoints"].exists, "The map night toggle must use the opaque red field tab bar")
        XCTAssertTrue(app.buttons["Waypoints"].exists)
        XCTAssertTrue(app.buttons["Add waypoint at map centre"].isHittable)
        XCTAssertTrue(app.buttons["Show all visible data"].isHittable)
        XCTAssertTrue(app.buttons["Map layers"].isHittable)
        XCTAssertLessThan(app.buttons["Add waypoint at map centre"].frame.maxY, app.buttons["Map"].firstMatch.frame.minY, "Map actions must stay above the field tab bar")
        let nightShot = XCTAttachment(screenshot: app.screenshot()); nightShot.name = "military-unit-map-night"; nightShot.lifetime = .keepAlways; add(nightShot)
    }
}
