import XCTest

final class FieldReferenceWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait; app = XCUIApplication() }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot:app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func reveal(_ element: XCUIElement) {
        let scroll = app.scrollViews.containing(.button,identifier:"reference-phonetic").firstMatch
        for _ in 0..<12 { if element.exists && element.isHittable { return }; scroll.swipeUp() }
        XCTAssertTrue(element.isHittable,app.debugDescription)
    }
    private func check(_ night: Bool) {
        let alphabet = app.buttons["reference-phonetic"]
        XCTAssertTrue(alphabet.waitForExistence(timeout:10),app.debugDescription)
        XCTAssertEqual(alphabet.value as? String,"Expanded")
        let alfa = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","A, Alfa")).firstMatch
        let zulu = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Z, Zulu")).firstMatch
        XCTAssertTrue(alfa.exists); XCTAssertTrue(zulu.exists)
        capture(night ? "reference-alphabet-night" : "reference-alphabet-day")
        alphabet.tap()
        let radio = app.buttons["reference-radio"]; reveal(radio); radio.tap()
        let example = app.staticTexts["reference-radio-example"]
        XCTAssertTrue(example.waitForExistence(timeout:5)); XCTAssertTrue(example.label.contains("One Eight Tango")); XCTAssertTrue(example.label.contains("Victor Papa"))
        radio.tap()
        let grid = app.buttons["reference-grid"]; reveal(grid); grid.tap()
        let accuracy = app.staticTexts["reference-grid-accuracy"]
        XCTAssertTrue(accuracy.exists); reveal(accuracy)
        XCTAssertTrue(accuracy.label.contains("not GPS accuracy"))
        capture(night ? "reference-grid-night" : "reference-grid-day")
        reveal(grid); grid.tap()
        for id in ["pace","contours","north","symbols"] {
            let button = app.buttons["reference-"+id]; reveal(button); button.tap()
            XCTAssertEqual(button.value as? String,"Expanded")
            capture("reference-"+id+(night ? "-night" : "-day"))
            reveal(button); button.tap()
        }
        let note = app.staticTexts["reference-training-note"]; reveal(note); XCTAssertTrue(note.label.contains("SOP"))
        app.navigationBars["Field reference"].buttons["Done"].tap()
    }
    func testOfflineReferenceFromSettingsInDay() {
        app.launchArguments = ["-uiTesting","-startTab","position"]; app.launch()
        app.buttons["Settings"].tap()
        let entry = app.buttons["settings-reference"]; revealSettingsControl(entry,in:app); entry.tap()
        check(false)
        XCTAssertTrue(app.buttons["settings-reference"].waitForExistence(timeout:5))
    }
    func testReferenceAlphabetUsesOneReadableColumnAtAccessibilityTextSize() {
        app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","map","-uiTestReferenceLargeText"]
        app.launch()
        XCTAssertTrue(mapTool(app, "map-measure").waitForExistence(timeout:10)); mapTool(app, "map-measure").tap()
        XCTAssertTrue(app.navigationBars["Map tools"].waitForExistence(timeout:5))
        let entry = app.buttons["field-reference"]
        for _ in 0..<12 { if entry.exists && entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable,app.debugDescription); entry.tap()
        XCTAssertTrue(app.buttons["reference-phonetic"].waitForExistence(timeout:10))
        let alfa = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","A, Alfa")).firstMatch
        let zulu = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Z, Zulu")).firstMatch
        XCTAssertTrue(alfa.exists); XCTAssertTrue(zulu.exists)
        XCTAssertGreaterThan(alfa.frame.height,32,"The launch must actually use accessibility text size")
        XCTAssertEqual(alfa.frame.minX,zulu.frame.minX,accuracy:2)
        XCTAssertGreaterThan(zulu.frame.minY,alfa.frame.maxY)
        XCTAssertLessThanOrEqual(alfa.frame.maxX,app.windows.firstMatch.frame.maxX)
        capture("reference-accessibility-alphabet")
        app.navigationBars["Field reference"].buttons["Done"].tap()
    }
    func testOfflineReferenceFromMapToolsAtNight() {
        app.launchArguments = ["-uiTesting","-uiTestBoundaryMap","-startTab","map"]; app.launch()
        XCTAssertTrue(mapTool(app, "map-measure").waitForExistence(timeout:10))
        mapTool(app, "Toggle map night mode").tap(); mapTool(app, "map-measure").tap()
        let entry = app.buttons["field-reference"]
        for _ in 0..<4 { if entry.exists && entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable,app.debugDescription); entry.tap()
        check(true)
        XCTAssertTrue(mapTool(app, "map-measure").waitForExistence(timeout:5))
    }
}
