import XCTest

final class TAKLocalWorkflowTests: XCTestCase {
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reach(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0..<8 {
            if element.exists {
                let frame = element.frame
                if element.isHittable, frame.minY > app.frame.minY + 125, frame.maxY < app.frame.maxY - 65 { return }
                if !frame.isEmpty {
                    if frame.minY < app.frame.minY + 125 { app.swipeDown() } else { app.swipeUp() }
                    continue
                }
            }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    func testLocalAndroidTeammateAndExplicitCertificateApproval() throws {
        // Opt-in only: this test needs a credential ZIP staged outside the repo.
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestTAKLocal", "-startTab", "map"]
        app.launch()
        let open = app.buttons["map-tak"]
        XCTAssertTrue(open.waitForExistence(timeout: 20)); open.tap()
        let load = app.buttons["tak-local-validation"]
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        guard app.staticTexts["tak-local-fixture-ready"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Local TAK UI validation requires a package explicitly staged in this simulator app")
        }
        load.tap()
        let connect = app.buttons["tak-connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15)); reach(connect, app: app, up: false); connect.tap()
        let review = app.staticTexts["Server name does not match"]
        XCTAssertTrue(review.waitForExistence(timeout: 25), app.debugDescription)
        let trust = app.buttons["tak-trust-certificate"]
        reach(trust, app: app); capture("tak-native-certificate-review"); trust.tap()
        let status = app.staticTexts["tak-status"]
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Connected"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 25), .completed, app.debugDescription)
        let share = app.switches["tak-share-position"]
        reach(share, app: app, up: false)
        XCTAssertEqual(share.value as? String, "0", "Position sharing must start off")
        share.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap()
        let android = app.staticTexts["MGRS-ADA5"]
        XCTAssertTrue(android.waitForExistence(timeout: 35), app.debugDescription)
        reach(android, app: app); capture("tak-android-contact-on-ios")
        let uid = app.staticTexts["tak-device-uid"]
        reach(uid, app: app); print("TAK local validation uid: \(uid.label)")
        let show = app.buttons["Show MGRS-ADA5 on map"]
        reach(show, app: app, up: false); show.tap()
        XCTAssertTrue(app.buttons["map-tak"].waitForExistence(timeout: 8))
        capture("tak-android-contact-native-map")
        // Leave the real native session running briefly for the Android peer's
        // independently observed capture. No simulated server or fake UI result.
        let hold = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
        _ = XCTWaiter.wait(for: [hold], timeout: 60)
    }
    func testLocalFolderSharingWithdrawalAndReconnect() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestTAKLocal", "-uiTestTAKSharing", "-startTab", "map"]
        app.launch()
        let open = app.buttons["map-tak"]
        XCTAssertTrue(open.waitForExistence(timeout: 20)); open.tap()
        let load = app.buttons["tak-local-validation"]
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        guard app.staticTexts["tak-local-fixture-ready"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Requires the explicitly staged local-only connection package")
        }
        reach(load, app: app); load.tap()
        let connect = app.buttons["tak-connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15)); reach(connect, app: app, up: false); connect.tap()
        XCTAssertTrue(app.staticTexts["Server name does not match"].waitForExistence(timeout: 25), app.debugDescription)
        let trust = app.buttons["tak-trust-certificate"]
        reach(trust, app: app); trust.tap()
        let status = app.staticTexts["tak-status"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Connected'"), object: status)], timeout: 25), .completed, app.debugDescription)
        let share = app.switches["tak-share-position"]
        XCTAssertEqual(share.value as? String, "0")
        let folder = app.switches["tak-folder-TAK INTEROP"]
        reach(folder, app: app); XCTAssertEqual(folder.value as? String, "0")
        folder.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap()
        let uid = app.staticTexts["tak-device-uid"]
        reach(uid, app: app); print("TAK_FOLDER_SHARED uid=\(uid.label) names=IOS OP CAFÉ;IOS TEST AREA")
        capture("tak-ios-folder-shared")
        for _ in 0..<2 { _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)], timeout: 60) }
        reach(folder, app: app, up: false)
        folder.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap()
        print("TAK_FOLDER_WITHDRAWN")
        capture("tak-ios-folder-withdrawn")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)], timeout: 60)
        reach(connect, app: app, up: false); connect.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Disconnected'"), object: status)], timeout: 5), .completed)
        connect.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Connected'"), object: status)], timeout: 25), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Server name does not match"].exists, "The saved pin must survive reconnect")
        XCTAssertTrue(app.staticTexts["MGRS-ADA5"].waitForExistence(timeout: 35))
        print("TAK_RECONNECTED_AFTER_WITHDRAWAL")
        reach(app.staticTexts["MGRS-ADA5"], app: app); capture("tak-ios-reconnected")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)], timeout: 60)
    }

    func testLocalAndroidItemsDrawAndDeleteFromSeparateLayer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestTAKLocal", "-startTab", "map"]
        app.launch()
        XCTAssertTrue(app.buttons["map-tak"].waitForExistence(timeout: 20)); app.buttons["map-tak"].tap()
        let load = app.buttons["tak-local-validation"]
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        guard app.staticTexts["tak-local-fixture-ready"].waitForExistence(timeout: 3) else { throw XCTSkip("Requires explicitly staged local-only credentials") }
        reach(load, app: app); load.tap()
        let connect = app.buttons["tak-connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15)); reach(connect, app: app, up: false); connect.tap()
        XCTAssertTrue(app.staticTexts["Server name does not match"].waitForExistence(timeout: 25), app.debugDescription)
        let trust = app.buttons["tak-trust-certificate"]; reach(trust, app: app); trust.tap()
        let status = app.staticTexts["tak-status"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Connected'"), object: status)], timeout: 25), .completed, app.debugDescription)
        let uid = app.staticTexts["tak-device-uid"]; reach(uid, app: app)
        print("TAK_INBOUND_READY uid=\(uid.label)")
        let marker = app.staticTexts["ANDROID OP CAFÉ"], line = app.staticTexts["ANDROID TEST LINE"]
        XCTAssertTrue(marker.waitForExistence(timeout: 120), app.debugDescription)
        XCTAssertTrue(line.waitForExistence(timeout: 30), app.debugDescription)
        reach(marker, app: app); capture("tak-android-items-received")
        let focusMarker = app.buttons["Show ANDROID OP CAFÉ on map"]
        reach(focusMarker, app: app); focusMarker.tap()
        XCTAssertTrue(app.buttons["map-tak"].waitForExistence(timeout: 5)); capture("tak-android-marker-map")
        app.buttons["map-tak"].tap()
        let focusLine = app.buttons["Show ANDROID TEST LINE on map"]
        reach(focusLine, app: app); focusLine.tap()
        XCTAssertTrue(app.buttons["map-tak"].waitForExistence(timeout: 5)); capture("tak-android-line-map")
        app.buttons["map-tak"].tap(); print("TAK_INBOUND_DRAWN_READY_FOR_DELETE")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !marker.exists && !line.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 120), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts["MGRS-ADA5"].exists, "Deleting shared items must preserve the teammate contact")
        print("TAK_INBOUND_DELETES_CONFIRMED")
        reach(app.staticTexts["MGRS-ADA5"], app: app); capture("tak-android-items-deleted")
        let oldReceived = app.staticTexts["tak-last-received"].value as? String ?? ""
        reach(connect, app: app, up: false); connect.tap(); connect.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Connected'"), object: status)], timeout: 25), .completed, app.debugDescription)
        let heardAgain = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = app.staticTexts["tak-last-received"]
            return value.exists && (value.value as? String) != oldReceived
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [heardAgain], timeout: 35), .completed, "Must receive actual stream data on the new connection")
        print("TAK_INBOUND_RECONNECT_RECEIVED_NEW_DATA")
        capture("tak-inbound-reconnected")
    }

    func testRemoteLayerFocusAndNightReadabilityPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestTAKPreview", "-startTab", "map"]
        app.launch()
        XCTAssertTrue(app.buttons["map-tak"].waitForExistence(timeout: 15)); app.buttons["map-tak"].tap()
        XCTAssertTrue(app.staticTexts["Rendering preview · no server connection"].exists)
        XCTAssertEqual(app.switches["tak-share-position"].value as? String, "0")
        let line = app.buttons["Show ANDROID TEST LINE on map"]
        reach(line, app: app); line.tap()
        XCTAssertTrue(app.buttons["map-tak"].waitForExistence(timeout: 5)); capture("tak-preview-line-focus-day")
        app.buttons["Toggle map night mode"].tap(); capture("tak-preview-line-focus-night")
        app.buttons["map-tak"].tap()
        XCTAssertTrue(app.staticTexts["ANDROID OP CAFÉ"].waitForExistence(timeout: 5))
        reach(app.staticTexts["ANDROID OP CAFÉ"], app: app)
        capture("tak-preview-list-night")
    }

}
