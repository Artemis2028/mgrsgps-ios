import CoreLocation
import Foundation
@testable import GridFixCore
import Security
import XCTest
@testable import MGRSGPS

private final class TAKTestTransport: TAKTransportDriving {
    var callback: ((TAKTransport.Event) -> Void)?
    var sends: [String] = []
    var starts = 0
    func start(host: String, port: UInt16, tls: Bool, identity: SecIdentity?, anchors: [SecCertificate], pinnedSHA256: String?, onEvent: @escaping (TAKTransport.Event) -> Void) {
        starts += 1; callback = onEvent
    }
    func send(_ xml: String) { sends.append(xml) }
    func stop() {}
}
@MainActor private final class TAKTestLocation: RecordingLocationDriver {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var precise = true, servicesEnabled = true
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var starts = 0, stops = 0, requests = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func requestPermission() { requests += 1 }
}
@MainActor final class TAKSessionTests: XCTestCase {
    private func package() -> Data {
        ZipArchive.write(entries: [.init(name: "server.pref", data: Data("<preferences><preference><entry key='connectString0'>127.0.0.1:8088:tcp</entry></preference></preferences>".utf8))])
    }
    private func drain() async { for _ in 0..<20 { await Task.yield() } }
    func testDefaultPresenceIsPositionlessAndNoLocationDemandThenExplicitSharingAndBackgroundStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = TAKTestTransport(), location = TAKTestLocation()
        let session = TAKSession(directory: root, transport: transport, driver: location, startTimer: false)
        defer { session.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(session.profile.uid); try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(session.sharePosition); XCTAssertFalse(session.connected)
        await session.importPackage(package())
        XCTAssertNil(session.failure)
        session.connect(); await drain()
        XCTAssertEqual(transport.starts, 1)
        transport.callback?(.ready); await drain()
        XCTAssertTrue(session.connected)
        XCTAssertTrue(transport.sends.first?.contains("type=\"a-f-G-U-C\"") == true)
        XCTAssertTrue(transport.sends.first?.contains("takv") == true, "The first wire event must identify the device before pings or items")
        XCTAssertEqual(location.starts, 0); XCTAssertEqual(location.requests, 0)
        XCTAssertTrue(transport.sends.contains { $0.contains("takv") && $0.contains("lat=\"0.0000000\" lon=\"0.0000000\"") })
        XCTAssertTrue(transport.sends.contains { $0.contains("t-x-c-t") })
        session.sharePosition = true
        XCTAssertEqual(location.starts, 1)
        location.onLocations?([CLLocation(coordinate: .init(latitude: 35.1388, longitude: -78.9914), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: Date())])
        session.setCallsign("FAKE POSITION") // force fresh presence on next tick
        session.setForeground(true)
        XCTAssertTrue(transport.sends.contains { $0.contains("lat=\"35.1388000\"") })
        session.setForeground(false); XCTAssertEqual(location.stops, 0)
        session.sharePosition = false; XCTAssertEqual(location.stops, 1)
        session.setForeground(false); XCTAssertFalse(session.connected)
        session.disconnect(); XCTAssertFalse(session.sharePosition)
    }
    func testRefusedCertificateStopsAutomaticReconnectAndLateCallbacksCannotReviveDisconnectedSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = TAKTestTransport(), location = TAKTestLocation()
        let session = TAKSession(directory: root, transport: transport, driver: location, startTimer: false)
        defer { session.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(session.profile.uid); try? FileManager.default.removeItem(at: root) }
        await session.importPackage(package()); session.connect(); await drain()
        let old = transport.callback
        transport.callback?(.refused("Changed pinned certificate")); await drain()
        XCTAssertEqual(session.status, "Connection refused")
        session.setForeground(false); session.setForeground(true); await drain()
        XCTAssertEqual(transport.starts, 1)
        session.disconnect(); old?(.ready); await drain()
        XCTAssertFalse(session.connected); XCTAssertTrue(transport.sends.isEmpty)
    }
    func testSharedFolderWithdrawalSurvivesDisconnectAndSessionRecreation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let waypoints = WaypointStore(directory: root), field = FieldDataStore(directory: root)
        _ = waypoints.add(.init(name: "OP CAFÉ", lat: 35.1388, lon: -78.9914, folder: "Recon", affiliation: "hostile"))
        try field.saveGraphic(.init(id: "area", name: "IOS AREA", type: "objective", points: [.init(lat: 35.138, lon: -78.991), .init(lat: 35.139, lon: -78.991), .init(lat: 35.139, lon: -78.990)], folder: "Recon"))
        let firstTransport = TAKTestTransport()
        let first = TAKSession(directory: root, transport: firstTransport, driver: TAKTestLocation(), startTimer: false, waypoints: waypoints, field: field)
        defer { first.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(first.profile.uid); try? FileManager.default.removeItem(at: root) }
        await first.importPackage(package()); first.connect(); await drain()
        firstTransport.callback?(.ready); await drain()
        first.setFolderShared("Recon", shared: true); await drain()
        XCTAssertTrue(firstTransport.sends.contains { $0.contains("OP CAFÉ") && $0.contains("type=\"a-h-G\"") })
        XCTAssertTrue(firstTransport.sends.contains { $0.contains("IOS AREA") && $0.contains("type=\"u-d-f\"") })
        let local = try TAKLocalStore(root: root)
        XCTAssertEqual(try local.readSent(profile: first.profile).count, 2)
        var otherEndpoint = first.profile; otherEndpoint.port = 8089
        XCTAssertTrue(try local.readSent(profile: otherEndpoint).isEmpty)
        first.disconnect(); first.setFolderShared("Recon", shared: false)
        XCTAssertEqual(try local.readSent(profile: first.profile).count, 2, "Offline withdrawal must retain pending tombstones")
        let secondTransport = TAKTestTransport()
        let second = TAKSession(directory: root, transport: secondTransport, driver: TAKTestLocation(), startTimer: false, waypoints: waypoints, field: field)
        defer { second.disconnect() }
        XCTAssertEqual(second.profile.uid, first.profile.uid); XCTAssertTrue(second.sharedFolders.isEmpty)
        second.connect(); await drain(); secondTransport.callback?(.ready); await drain()
        XCTAssertTrue(secondTransport.sends.first?.contains("takv") == true, "Reconnect must announce before offline tombstones")
        XCTAssertEqual(secondTransport.sends.filter { $0.contains("type=\"t-x-d-d\"") }.count, 2)
        XCTAssertTrue(try local.readSent(profile: second.profile).isEmpty)
    }
    func testExplicitTrustResetDisconnectsStopsLocationAndDoesNotReconnectSilently() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try TAKLocalStore(root: root)
        var profile = try store.readProfile()
        profile.host = "127.0.0.1"; profile.port = 8088; profile.tls = false; profile.pin = "synthetic-previous-pin"
        try store.write(profile)
        let parsedPackage = try TAKConnectionPackage.read(package())
        try store.saveCredentials(.init(parsedPackage), uid: profile.uid)
        let transport = TAKTestTransport(), location = TAKTestLocation()
        let session = TAKSession(directory: root, transport: transport, driver: location, startTimer: false)
        defer { session.disconnect(); try? store.deleteCredentials(profile.uid); try? FileManager.default.removeItem(at: root) }
        session.connect(); await drain(); transport.callback?(.ready); await drain()
        session.sharePosition = true; XCTAssertEqual(location.starts, 1)
        let oldCallback = transport.callback
        session.resetServerTrust(); await drain()
        XCTAssertNil(session.profile.pin); XCTAssertNil(try store.readProfile().pin)
        XCTAssertFalse(session.connected); XCTAssertFalse(session.sharePosition)
        XCTAssertEqual(location.stops, 1); XCTAssertEqual(transport.starts, 1)
        oldCallback?(.ready); await drain(); XCTAssertFalse(session.connected)
    }
    func testInstallIdentitySurvivesRelaunchAndIsExcludedFromBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TAKLocalStore(root: root), first = try store.readProfile()
        XCTAssertEqual(try TAKLocalStore(root: root).readProfile().uid, first.uid)
        XCTAssertTrue(first.uid.hasPrefix("MGRSGPS-"))
        XCTAssertEqual(try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let other = try TAKLocalStore(root: root.appendingPathComponent("second-install")).readProfile()
        XCTAssertNotEqual(first.uid, other.uid)
    }
}
