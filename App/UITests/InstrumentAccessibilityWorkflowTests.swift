import XCTest

final class InstrumentAccessibilityWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func visible(_ element: XCUIElement,in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout:10),app.debugDescription)
        let frame = element.frame, window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.width,0); XCTAssertGreaterThan(frame.height,0)
        XCTAssertGreaterThanOrEqual(frame.minX,window.minX); XCTAssertLessThanOrEqual(frame.maxX,window.maxX+1)
        XCTAssertGreaterThanOrEqual(frame.minY,window.minY); XCTAssertLessThanOrEqual(frame.maxY,window.maxY-30)
        XCTAssertTrue(element.isHittable,app.debugDescription)
    }
    private func run(night: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-uiTestLibrary","-uiTestTargetSelection","-uiTestBoundaryMap","-startTab","position","-startFace","glance",
                               "-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let settings = app.buttons["Settings"]
        if night {
            tapNativeMenuItem(settings)
            setNativeSwitch(app.switches["Red-on-black, to keep night vision"],to:true)
            tapNativeMenuItem(app.navigationBars.buttons["Done"])
        }
        let qr = app.buttons["position-share-qr"]
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:qr)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:30),.completed)
        capture(night ? "instrument-largest-position-night" : "instrument-largest-position-day")
        visible(app.staticTexts["position-title"],in:app)
        visible(settings,in:app); visible(qr,in:app)
        XCTAssertGreaterThanOrEqual(settings.frame.height,44)
        XCTAssertGreaterThanOrEqual(settings.frame.width,44)
        let callout = app.staticTexts["position-phonetic"]
        visible(callout,in:app); XCTAssertTrue(callout.label.contains(" · "))
        tapNativeMenuItem(qr)
        XCTAssertTrue(app.images["position-qr-image"].waitForExistence(timeout:10))
        capture(night ? "instrument-largest-share-night" : "instrument-largest-share-day")
        tapNativeMenuItem(app.navigationBars.buttons["Done"])
        tapNativeMenuItem(app.buttons["Navigate"])
        let orientation = app.buttons["screen-orientation-menu"], target = app.buttons["Choose navigation target"]
        visible(app.staticTexts["navigation-title"],in:app)
        visible(orientation,in:app); visible(target,in:app)
        capture(night ? "instrument-largest-navigation-night" : "instrument-largest-navigation-day")
        tapNativeMenuItem(target)
        let choice = app.buttons["Selection target"]
        XCTAssertTrue(choice.waitForExistence(timeout:10)); tapNativeMenuItem(choice)
        let selected = app.staticTexts["navigation-target-name"]
        XCTAssertTrue(selected.waitForExistence(timeout:10)); XCTAssertEqual(selected.label,"Selection target")
        capture(night ? "instrument-largest-target-night" : "instrument-largest-target-day")
        XCUIDevice.shared.orientation = .landscapeLeft
        visible(app.staticTexts["navigation-title"],in:app)
        visible(orientation,in:app); visible(target,in:app)
        capture(night ? "instrument-largest-navigation-landscape-night" : "instrument-largest-navigation-landscape-day")
        tapNativeMenuItem(app.buttons["Position"])
        visible(app.staticTexts["position-title"],in:app)
        visible(settings,in:app); visible(qr,in:app)
        capture(night ? "instrument-largest-position-landscape-night" : "instrument-largest-position-landscape-day")
        XCUIDevice.shared.orientation = .portrait
    }
    func testLargestPositionGridSharingAndNavigationControlsInDay() { run(night:false) }
    func testLargestPositionGridSharingAndNavigationControlsAtNight() { run(night:true) }
}
