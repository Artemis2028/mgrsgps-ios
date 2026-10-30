import XCTest

final class TAKLocalWorkflowTests: XCTestCase {
    /// Run only after the opt-in native enrollment preparation and a coordinated
    /// Android peer GO. No imported package or synthetic remote scene is used.
    func testEnrolledAppsExchangePositionsItemsDeletesAndReconnect() throws {
        continueAfterFailure = false
        let optIn = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent("tak-local-enrolled-peer-ui-optin")
        guard FileManager.default.fileExists(atPath: optIn.path) else { throw XCTSkip("Enrolled peer UI round has not been explicitly staged in the test runner") }
        defer { try? FileManager.default.removeItem(at: optIn) }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting","-keepUITestData","-uiTestTAKSharing","-startTab","map"]
        app.launch()
        XCTAssertTrue(mapStatusButton(app, "map-tak").waitForExistence(timeout: 20)); mapStatusButton(app, "map-tak").tap()
        let callsign = app.textFields["tak-callsign"]
        guard callsign.waitForExistence(timeout: 3),
              (callsign.value as? String)?.hasPrefix("IOS-ENR-") == true,
              app.staticTexts["127.0.0.1:8089 · TLS"].exists else { throw XCTSkip("Requires explicitly prepared enrolled local app profile") }
        let connect = app.buttons["tak-connect"],status = app.staticTexts["tak-status"]
        func connection(_ value: String) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@",value),object: status)],timeout: 30),.completed,app.debugDescription)
        }
        reach(connect,app: app,up: false); connect.tap(); connection("Connected")
        XCTAssertFalse(app.buttons["tak-trust-certificate"].exists,"Enrolled profile must retain its explicitly approved certificate pin")
        let share = app.switches["tak-share-position"]
        reach(share,app: app) // Defaults are checked by the preparation; allow an interrupted round to resume.
        setNativeSwitch(share,to: true)
        let folder = app.switches["tak-folder-TAK INTEROP"]
        reach(folder,app: app); setNativeSwitch(folder,to: true)
        print("TAK_ENROLLED_SHARED_READY names=IOS OP CAFÉ;IOS TEST AREA")
        XCTAssertTrue(app.staticTexts["MGRS-ADA5"].waitForExistence(timeout: 45),app.debugDescription)
        let marker = app.staticTexts["ANDROID OP CAFÉ"],line = app.staticTexts["ANDROID TEST LINE"]
        XCTAssertTrue(marker.waitForExistence(timeout: 180),app.debugDescription)
        XCTAssertTrue(line.waitForExistence(timeout: 45),app.debugDescription)
        reach(marker,app: app); capture("tak-enrolled-android-items-received")
        for name in ["MGRS-ADA5","ANDROID OP CAFÉ","ANDROID TEST LINE"] {
            let focus = app.buttons["Show " + name + " on map"]
            reach(focus,app: app); focus.tap()
            XCTAssertTrue(mapStatusButton(app, "map-tak").waitForExistence(timeout: 8))
            capture("tak-enrolled-map-" + name)
            mapStatusButton(app, "map-tak").tap()
        }
        print("TAK_ENROLLED_INBOUND_DRAWN_READY_FOR_DELETE")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in !marker.exists && !line.exists },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [gone],timeout: 180),.completed,app.debugDescription)
        XCTAssertTrue(app.staticTexts["MGRS-ADA5"].exists)
        print("TAK_ENROLLED_INBOUND_DELETES_CONFIRMED")
        let received = app.staticTexts["tak-last-received"].value as? String ?? ""
        reach(connect,app: app,up: false); connect.tap(); connection("Disconnected")
        connect.tap(); connection("Connected")
        let heard = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            let value = app.staticTexts["tak-last-received"]
            return value.exists && (value.value as? String) != received
        },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [heard],timeout: 35),.completed)
        print("TAK_ENROLLED_RECONNECTED_NEW_DATA")
        reach(folder,app: app); setNativeSwitch(folder,to: false)
        print("TAK_ENROLLED_OUTBOUND_WITHDRAWN")
        capture("tak-enrolled-withdrawn-reconnected")
        // Give the independently operated Android peer time to observe deletes.
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in false },object: nil)],timeout: 60)
        reach(share,app: app,up: false); setNativeSwitch(share,to: false)
        reach(connect,app: app,up: false); connect.tap(); connection("Disconnected")
    }

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
        let open = mapStatusButton(app, "map-tak")
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
        XCTAssertTrue(mapStatusButton(app, "map-tak").waitForExistence(timeout: 8))
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
        let open = mapStatusButton(app, "map-tak")
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
        XCTAssertTrue(mapStatusButton(app, "map-tak").waitForExistence(timeout: 20)); mapStatusButton(app, "map-tak").tap()
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
        XCTAssertTrue(mapStatusButton(app, "map-tak").waitForExistence(timeout: 5)); capture("tak-android-marker-map")
        mapStatusButton(app, "map-tak").tap()
        let focusLine = app.buttons["Show ANDROID TEST LINE on map"]
        reach(focusLine, app: app); focusLine.tap()
        XCTAssertTrue(mapStatusButton(app, "map-tak").waitForExistence(timeout: 5)); capture("tak-android-line-map")
        mapStatusButton(app, "map-tak").tap(); print("TAK_INBOUND_DRAWN_READY_FOR_DELETE")
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
        let preview = app.staticTexts["Rendering preview · no server connection"]
        XCTAssertTrue(mapStatusButton(app, "map-tak").waitForExistence(timeout: 15))
        tapNativeMenuItem(mapStatusButton(app, "map-tak"),revealing: preview)
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["tak-share-position"].value as? String, "0")
        let line = app.buttons["Show ANDROID TEST LINE on map"]
        reach(line, app: app); line.tap()
        XCTAssertTrue(mapStatusButton(app, "map-tak").waitForExistence(timeout: 5)); capture("tak-preview-line-focus-day")
        mapTool(app, "Toggle map night mode").tap(); capture("tak-preview-line-focus-night")
        tapNativeMenuItem(mapStatusButton(app, "map-tak"),revealing: preview)
        XCTAssertTrue(app.staticTexts["ANDROID OP CAFÉ"].waitForExistence(timeout: 5))
        reach(app.staticTexts["ANDROID OP CAFÉ"], app: app)
        capture("tak-preview-list-night")
    }

}
