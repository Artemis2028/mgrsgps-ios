import XCTest

/// Uses a host-side simctl location feed, never an injected Position fix.
final class PositionSolarWorkflowTests:XCTestCase {
    private func capture(_ name:String) {let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    private func verify(_ app:XCUIApplication) {
        let bmnt=app.staticTexts["position-sun-bmnt"]
        let format=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label MATCHES %@",".*[0-9]{4}L [0-9]{4}Z.*"),object:bmnt)
        XCTAssertEqual(XCTWaiter.wait(for:[format],timeout:20),.completed,app.debugDescription)
        for key in ["bmnt","sr","ss","eent"] {XCTAssertTrue(app.staticTexts["position-sun-"+key].label.contains("Z"))}
    }
    func testRealFixSolarReadoutsAcrossPositionFacesAndNightMode() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-uiTesting","-startTab","position"];app.launch()
        verify(app);capture("position-solar-lensatic-day")
        app.buttons["Settings"].tap();app.buttons["Dial"].tap();app.navigationBars.buttons["Done"].tap()
        verify(app);capture("position-solar-dial-day")
        app.buttons["Settings"].tap();app.buttons["Glance"].tap();app.navigationBars.buttons["Done"].tap()
        let details=app.scrollViews["position-details"],last=app.staticTexts["position-sun-eent"]
        for _ in 0..<8 {if last.isHittable && last.frame.maxY<app.frame.maxY-100 {break};details.swipeUp()}
        verify(app);XCTAssertTrue(last.isHittable);capture("position-solar-glance-day")
        app.tabBars.buttons["Map"].tap();app.buttons["Toggle map night mode"].tap();app.buttons["Position"].tap()
        verify(app);capture("position-solar-glance-night")
    }
}
