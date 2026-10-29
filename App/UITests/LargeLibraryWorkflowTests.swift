import XCTest

final class LargeLibraryWorkflowTests: XCTestCase {
    func testDenseMapAccessibilityKeepsEveryVisibleMarkerAfterCameraAndNightChanges() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestLargeLibrary", "-uiTestBoundaryMap", "-startTab", "map"]
        app.launch()
        let markers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-waypoint-large-point-"))
        func verify() {
            let map = app.otherElements.matching(NSPredicate(format: "label == %@", "Map")).firstMatch
            XCTAssertTrue(map.waitForExistence(timeout: 10))
            let value = map.value as? String ?? ""
            let range = value.range(of: #"[0-9,]+ annotation\(s\)"#, options: .regularExpression)
            XCTAssertNotNil(range, value)
            let count = range.flatMap { value[$0].split(separator: " ").first }.flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
            XCTAssertEqual(markers.count, count, "Every SDK-visible waypoint must remain individually accessible")
            XCTAssertGreaterThan(markers.count, 100)
            XCTAssertTrue(app.buttons["Compass"].exists)
            XCTAssertTrue(app.buttons["About this map"].exists)
        }
        func go(_ grid: String) {
            mapTool(app, "map-goto").tap()
            let input = app.textFields["map-goto-grid"]
            XCTAssertTrue(input.waitForExistence(timeout: 5)); replaceTextInput(input, grid)
            app.buttons["map-goto-keyboard-done"].tap(); app.buttons["map-goto-show"].tap()
            XCTAssertTrue(app.buttons["map-options"].waitForExistence(timeout: 8))
        }
        verify()
        let day = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        day.name = "dense-map-accessible-markers-day"; day.lifetime = .keepAlways; add(day)
        let origin = app.buttons["map-waypoint-large-point-0"]
        XCTAssertTrue(origin.exists)
        func visibility(_ title: String) {
            tapNativeMenuItem(app.buttons["Waypoints"], revealing: app.textFields["library-search"])
            let search = app.textFields["library-search"]
            replaceTextInput(search, "Point 0000"); search.typeText("\n")
            let actions = app.buttons["Actions for Point 0000"]
            XCTAssertTrue(actions.waitForExistence(timeout: 8)); tapNativeMenuItem(actions)
            tapNativeMenuItem(app.buttons[title])
            tapNativeMenuItem(app.buttons["Map"], revealing: app.buttons["map-options"])
        }
        visibility("Hide on map")
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: origin)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        verify()
        visibility("Make visible on map")
        XCTAssertTrue(origin.waitForExistence(timeout: 10))
        verify()
        go("40R BN 90000 90000")
        let empty = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in markers.count == 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [empty], timeout: 10), .completed)
        go("40R BN 34124 07001")
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in markers.count > 100 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
        verify()
        mapTool(app, "Toggle map night mode").tap(); closeMapOptions(app)
        verify()
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "dense-map-accessible-markers-night"; image.lifetime = .keepAlways; add(image)
    }
    func testLargeFolderCourseKeepsSavedCheckpointOrderAndLibraryCount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLargeLibrary","-uiTestBoundaryMap","-startTab","navigate"]
        app.launch()
        let open = app.buttons["open-practice"]
        XCTAssertTrue(open.waitForExistence(timeout:20)); tapNativeMenuItem(open)
        selectNativeSegment(app.segmentedControls.buttons["From folder"])
        tapNativeMenuItem(app.buttons["practice-folder"])
        let folder = app.buttons["Folder 099"]
        for _ in 0..<24 {
            if folder.exists,folder.isHittable,folder.frame.maxY < app.windows.firstMatch.frame.maxY - 35 { break }
            app.collectionViews.allElementsBoundByIndex.last?.swipeUp()
        }
        XCTAssertTrue(folder.waitForExistence(timeout:5)); folder.tap()
        let start = app.buttons["practice-start"]
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:start)],timeout:10),.completed)
        tapNativeMenuItem(start)
        let progress = app.staticTexts["practice-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout:15)); XCTAssertEqual(progress.label,"CP 1 of 50")
        XCTAssertTrue(app.staticTexts["Point 0099"].exists,"The favourite Point 4999 must not reorder course checkpoints")
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); image.name = "large-folder-course-order"; image.lifetime = .keepAlways; add(image)
        let end = app.buttons["practice-end"]
        for _ in 0..<8 { if end.isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        tapNativeMenuItem(end); tapNativeMenuItem(app.buttons["End course"])
        XCTAssertTrue(start.waitForExistence(timeout:15)); tapNativeMenuItem(app.buttons["Close"])
        app.buttons["Waypoints"].tap()
        let count = app.staticTexts["library-listed-count"]
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","5,000 waypoints · 1,000 graphics · 0 tracks"),object:count)],timeout:15),.completed)
    }
    private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<24 {
            let window = app.windows.firstMatch.frame, top = app.windows.firstMatch.frame.minY + 65, bottom = app.windows.firstMatch.frame.maxY - 105
            if element.exists,element.isHittable,element.frame.minY >= top,element.frame.maxY <= bottom { return }
            let middle = (top + bottom) / 2
            let shift = element.exists ? min(150,max(-150,middle-element.frame.midY)) : -150
            let start = app.coordinate(withNormalizedOffset:.zero).withOffset(.init(dx:window.midX,dy:middle))
            start.press(forDuration:0.1,thenDragTo:start.withOffset(.init(dx:0,dy:shift)),withVelocity:.slow,thenHoldForDuration:0.2)
        }
        XCTFail("Library control is not fully visible: " + app.debugDescription)
    }
    private func runLargestCard(night: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLargeLibrary","-uiTestBoundaryMap","-startTab","waypoints",
                               "-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        if night { app.launchArguments.append("-uiTestLargeLibraryNight") }
        app.launch()
        let input = app.textFields["library-search"]
        XCTAssertTrue(input.waitForExistence(timeout:20)); reveal(input,in:app)
        tapNativeMenuItem(input); input.typeText("Point 0000\n")
        let count = app.staticTexts["library-listed-count"]
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","1 waypoints · 0 graphics · 0 tracks"),object:count)],timeout:15),.completed)
        let point = app.buttons["edit-waypoint-Point 0000"]
        reveal(point,in:app)
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); image.name = "largest-waypoint-card"; image.lifetime = .keepAlways; add(image)
        XCTAssertGreaterThan(point.frame.width,app.windows.firstMatch.frame.width * 0.6,"The coordinate summary needs most of the card width, rather than being squeezed between icons and actions")
        let actions = app.buttons["Actions for Point 0000"]
        reveal(actions,in:app)
        XCTAssertGreaterThanOrEqual(actions.frame.width,44); XCTAssertGreaterThanOrEqual(actions.frame.height,44)
        tapNativeMenuItem(actions)
        let edit = app.buttons["edit"]
        XCTAssertTrue(edit.waitForExistence(timeout:8),app.debugDescription); edit.tap()
        let name = app.textFields["waypoint-name"]
        XCTAssertTrue(name.waitForExistence(timeout:8)); XCTAssertEqual(name.value as? String,"Point 0000")
        tapNativeMenuItem(app.buttons["Cancel"])
        let navigate = app.buttons["Navigate to Point 0000"]
        reveal(navigate,in:app); tapNativeMenuItem(navigate)
        let target = app.staticTexts["navigation-target-name"]
        XCTAssertTrue(target.waitForExistence(timeout:15)); XCTAssertEqual(target.label,"Point 0000")
    }
    func testLargestTextWaypointGridAndActionsRemainReadable() { runLargestCard(night:false) }
    func testLargestTextWaypointGridAndActionsRemainReadableAtNight() { runLargestCard(night:true) }
    func testLargeLibrarySearchGridSelectionAndNightCards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLargeLibrary","-uiTestBoundaryMap","-startTab","waypoints"]
        app.launch()
        let count = app.staticTexts["library-listed-count"]
        func counts(_ expected: String) {
            let predicate = NSPredicate(format: "label CONTAINS %@",expected)
            XCTAssertTrue(count.waitForExistence(timeout: 10))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate,object: count)],timeout: 10),.completed,app.debugDescription)
            XCTAssertFalse(app.progressIndicators["library-updating"].exists)
        }
        func query(_ text: String) {
            let clear = app.buttons["library-search-clear"]
            if clear.exists { clear.tap() }
            let input = app.textFields["library-search"]
            XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text+"\n")
        }
        func capture(_ name: String) {
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        }
        counts("5,000 waypoints · 1,000 graphics · 0 tracks")
        XCTAssertTrue(app.buttons["edit-waypoint-Point 4999"].waitForExistence(timeout: 5))
        capture("large-library-favourite-first")
        query("Folder 099"); counts("50 waypoints · 0 graphics · 0 tracks")
        app.buttons["library-select-button"].tap(); app.buttons["library-select-all"].tap()
        XCTAssertEqual(app.staticTexts["library-selected-count"].label,"50 selected")
        query("Route 0999")
        XCTAssertTrue(app.buttons["Select graphic Route 0999"].waitForExistence(timeout: 10))
        app.buttons["library-select-all"].tap()
        XCTAssertEqual(app.staticTexts["library-selected-count"].label,"1 selected")
        app.buttons["library-selection-done"].tap()
        counts("0 waypoints · 1 graphics · 0 tracks")
        query("Point 0000"); counts("1 waypoints · 0 graphics · 0 tracks")
        let point = app.buttons["edit-waypoint-Point 0000"]
        XCTAssertTrue(point.waitForExistence(timeout: 5))
        // Search the exact displayed MGRS, rather than hardcoding a grid fixture.
        let range = point.label.range(of: #"40R [A-Z]{2} [0-9]{5} [0-9]{5}"#,options: .regularExpression)
        XCTAssertNotNil(range,point.debugDescription)
        query(range.map { String(point.label[$0]) } ?? "missing grid"); counts("1 waypoints · 0 graphics · 0 tracks")
        app.tabBars.buttons["Map"].tap(); mapTool(app, "Toggle map night mode").tap(); app.buttons["Waypoints"].tap()
        XCTAssertTrue(point.waitForExistence(timeout: 10))
        capture("large-library-grid-search-night")
    }
}
