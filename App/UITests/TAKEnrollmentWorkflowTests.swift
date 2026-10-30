import XCTest

final class TAKEnrollmentWorkflowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func open(night: Bool, local: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-startTab", "map"]
        if night { app.launchArguments.append("-uiTestTAKEnrollmentNight") }
        if local { app.launchArguments.append("-uiTestTAKEnrollmentLocal") }
        app.launch()
        let tak = mapStatusButton(app, "map-tak")
        XCTAssertTrue(tak.waitForExistence(timeout: 20)); tapNativeMenuItem(tak)
        let signIn = app.buttons["tak-enrollment"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 8)); tapNativeMenuItem(signIn)
        XCTAssertTrue(app.textFields["tak-enroll-host"].waitForExistence(timeout: 8))
        return app
    }
    private func form(night: Bool) {
        let app = open(night: night)
        XCTAssertFalse(app.secureTextFields["tak-enroll-password"].exists, "Credentials must wait for server verification")
        let host = app.textFields["tak-enroll-host"]
        tapTextInput(host); host.typeText("127.0.0.1")
        let port = app.textFields["tak-enroll-port"]
        tapTextInput(port); port.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "0")
        dismissFieldKeyboard()
        tapNativeMenuItem(app.buttons["tak-enroll-verify"])
        let error = app.staticTexts["tak-enroll-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5)); revealSettingsControl(error, in: app)
        capture(night ? "tak-enrollment-invalid-port-night" : "tak-enrollment-invalid-port-day")
        tapNativeMenuItem(app.buttons["tak-enroll-cancel"])
        XCTAssertTrue(app.buttons["tak-enrollment"].waitForExistence(timeout: 5))
    }
    func testReadableSignInFormAndPortValidationInDay() { form(night: false) }
    func testReadableSignInFormAndPortValidationAtNight() { form(night: true) }

    /// Opt-in marker is staged only on the owned local simulator. Ordinary CI
    /// skips this; it must never contact a developer/customer server.
    func testLocalTrustPromptAndWrongPasswordStayInEnrollmentSheet() throws {
        let app = open(night: false, local: true)
        guard app.staticTexts["tak-enroll-local-fixture-ready"].exists else { throw XCTSkip("Local enrollment UI marker has not been explicitly staged") }
        let host = app.textFields["tak-enroll-host"]
        tapTextInput(host); host.typeText("127.0.0.1"); dismissFieldKeyboard()
        tapNativeMenuItem(app.buttons["tak-enroll-verify"])
        let trust = app.buttons["tak-enroll-trust"]
        XCTAssertTrue(trust.waitForExistence(timeout: 25), app.debugDescription)
        revealSettingsControl(trust, in: app); capture("tak-enrollment-local-fingerprint-review")
        tapNativeMenuItem(trust)
        let username = app.textFields["tak-enroll-username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        revealSettingsControl(username, in: app); tapTextInput(username); username.typeText("enroll_ios")
        let password = app.secureTextFields["tak-enroll-password"]
        revealSettingsControl(password, in: app); tapTextInput(password); password.typeText("intentionally-wrong-local-test")
        dismissFieldKeyboard()
        let submit = app.buttons["tak-enroll-submit"]
        revealSettingsControl(submit, in: app); tapNativeMenuItem(submit)
        let error = app.staticTexts["tak-enroll-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 20)); revealSettingsControl(error, in: app)
        XCTAssertTrue(error.label.contains("Sign-in refused"))
        XCTAssertTrue(app.buttons["tak-enroll-submit"].exists)
        capture("tak-enrollment-local-wrong-password-retry")
        tapNativeMenuItem(app.buttons["tak-enroll-cancel"])
        XCTAssertTrue(app.buttons["tak-enrollment"].waitForExistence(timeout: 5))
    }
}
