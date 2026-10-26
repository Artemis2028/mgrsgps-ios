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
    func testPreparedStartupRetainsIdentityTrustSharingAndStaysDisconnected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TAKLocalStore(root: root)
        var profile = try store.readProfile()
        profile.host = "127.0.0.1"; profile.callsign = "TEST CAFÉ"; profile.pin = "saved-trust"; profile.sharedFolders = ["Base"]
        try store.write(profile); try store.writeSent(["sent-item":"fingerprint"],profile: profile)
        let prepared = await Task.detached { TAKLocalStore.prepareStartup(root: root) }.value
        try prepared.validate()
        XCTAssertEqual(prepared.sent,["sent-item":"fingerprint"])
        let transport = TAKTestTransport(),location = TAKTestLocation()
        let session = TAKSession(directory: root,startup: prepared,transport: transport,driver: location,startTimer: false)
        XCTAssertEqual(session.profile.uid,profile.uid); XCTAssertEqual(session.profile.pin,profile.pin)
        XCTAssertEqual(session.profile.callsign,"TEST CAFÉ"); XCTAssertEqual(session.sharedFolders,["Base"])
        XCTAssertFalse(session.connected); XCTAssertFalse(session.connecting); XCTAssertFalse(session.sharePosition)
        XCTAssertEqual(transport.starts,0); XCTAssertEqual(location.starts,0); XCTAssertNil(session.failure)
    }
    func testPreparedFirstInstallHasStableIdentityAndNoSpuriousChange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = await Task.detached { TAKLocalStore.prepareStartup(root: root) }.value
        try prepared.validate()
        let stored = try TAKLocalStore(root: root).readProfile()
        XCTAssertEqual(prepared.profile?.uid,stored.uid)
        XCTAssertTrue(prepared.sent.isEmpty); XCTAssertTrue(prepared.sharingAvailable)
        XCTAssertNil(prepared.failure)
    }
    func testPreparedSharingHistoryRefusesCreationReplacementAndRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TAKLocalStore(root: root),profile = try store.readProfile()
        let absent = TAKLocalStore.prepareStartup(root: root)
        try store.writeSent(["old":"one"],profile: profile)
        XCTAssertThrowsError(try absent.validate())
        let old = TAKLocalStore.prepareStartup(root: root)
        try store.writeSent(["new":"two"],profile: profile)
        XCTAssertThrowsError(try old.validate())
        let latest = TAKLocalStore.prepareStartup(root: root)
        let sent = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: store.directory,includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("sent-") })
        try FileManager.default.removeItem(at: sent)
        XCTAssertThrowsError(try latest.validate())
    }
    func testPreparedCorruptHistoryDisablesFolderSharingAndPreservesBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TAKLocalStore(root: root),profile = try store.readProfile()
        try store.writeSent(["old":"one"],profile: profile)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: store.directory,includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("sent-") })
        let raw = Data("damaged sharing history".utf8); try raw.write(to: file,options: .atomic)
        let prepared = TAKLocalStore.prepareStartup(root: root)
        try prepared.validate(); XCTAssertFalse(prepared.sharingAvailable); XCTAssertNotNil(prepared.failure)
        XCTAssertEqual(prepared.profile?.uid,profile.uid); XCTAssertEqual(try Data(contentsOf: file),raw)
        let transport = TAKTestTransport()
        let session = TAKSession(directory: root,startup: prepared,transport: transport,driver: TAKTestLocation(),startTimer: false)
        XCTAssertTrue(session.failure?.contains("folder sharing is disabled") == true); XCTAssertEqual(transport.starts,0)
    }
    func testPreparedProfileRejectsChangedOrDifferentLibraryAndPreservesDamage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = TAKLocalStore.prepareStartup(root: root)
        let store = try TAKLocalStore(root: root),file = store.directory.appendingPathComponent("profile.json")
        let raw = Data("damaged identity".utf8); try raw.write(to: file,options: .atomic)
        XCTAssertThrowsError(try prepared.validate())
        let damaged = TAKLocalStore.prepareStartup(root: root)
        try damaged.validate(); XCTAssertNil(damaged.profile); XCTAssertNotNil(damaged.failure)
        XCTAssertEqual(try Data(contentsOf: file),raw)
        let transport = TAKTestTransport()
        let session = TAKSession(directory: root.appendingPathComponent("other"),startup: prepared,transport: transport,driver: TAKTestLocation(),startTimer: false)
        XCTAssertNotNil(session.failure); XCTAssertEqual(transport.starts,0)
    }
    func testSharedPositionUsesCommonAndroidAgeAccuracyAndCoordinateBounds() {
        func fix(age: Double = 0,accuracy: Double = 5,lat: Double = 35,lon: Double = -79) -> Fix {
            .init(lat: lat,lon: lon,accuracyMeters: accuracy,altitudeMeters: nil,speedMetersPerSecond: nil,timestamp: Date(),timestampUptime: 100-age)
        }
        for accuracy in [0.0,25,40,1000] { XCTAssertTrue(TAKSession.canShare(fix(age: 30,accuracy: accuracy),nowUptime: 100)) }
        for accuracy in [-1.0,1000.001,.nan,.infinity] { XCTAssertFalse(TAKSession.canShare(fix(accuracy: accuracy),nowUptime: 100)) }
        for age in [-0.001,30.001,.nan,.infinity] { XCTAssertFalse(TAKSession.canShare(fix(age: age),nowUptime: 100)) }
        for (lat,lon) in [(0.0,0.0),(90.001,0),(-90.001,0),(0,180.001),(0,-180.001),(.nan,1),(1,.infinity)] {
            XCTAssertFalse(TAKSession.canShare(fix(lat: lat,lon: lon),nowUptime: 100))
        }
        XCTAssertTrue(TAKSession.canShare(fix(lat: 0,lon: 1),nowUptime: 100))
        XCTAssertTrue(TAKSession.canShare(fix(lat: 1,lon: 0),nowUptime: 100))
        XCTAssertFalse(TAKSession.canShare(fix(),nowUptime: .nan))
    }

    /// Uses the real Core Location driver and a fake wire transport. The host
    /// must explicitly stage this marker and continuously feed this simulator.
    func testLocalSimulatorSharedPositionRemainsFreshWithContinuousLocationFeed() async throws {
        #if targetEnvironment(simulator)
        let marker = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent("tak-local-position-feed-optin")
        guard FileManager.default.fileExists(atPath: marker.path) else { throw XCTSkip("Continuous simulator location feed has not been explicitly staged") }
        defer { try? FileManager.default.removeItem(at: marker) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = TAKTestTransport(),driver = CoreLocationRecordingDriver()
        let session = TAKSession(directory: root,transport: transport,driver: driver,startTimer: true)
        defer { session.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(session.profile.credentialID ?? session.profile.uid); try? FileManager.default.removeItem(at: root) }
        await session.importPackage(package()); session.connect(); await drain()
        transport.callback?(.ready); await drain(); session.sharePosition = true
        let deadline = Date().addingTimeInterval(30)
        func isPosition(_ xml: String) -> Bool { xml.contains("takv") && xml.contains("lat=\"35.1389") && xml.contains("lon=\"-78.9909") }
        while !transport.sends.contains(where: isPosition),Date() < deadline { try await Task.sleep(nanoseconds: 250_000_000) }
        let first = try XCTUnwrap(transport.sends.firstIndex(where: isPosition),"Real simulator must deliver the staged fresh fix")
        try await Task.sleep(nanoseconds: 55_000_000_000)
        let reports = transport.sends[first...].filter { $0.contains("takv") }
        XCTAssertGreaterThanOrEqual(reports.count,5,"Continuous shared position must retain the 10-second cadence")
        XCTAssertTrue(reports.allSatisfy(isPosition),"Fresh real locations must never become zero-coordinate presence")
        let artifact = XCTAttachment(string: reports.joined(separator: "\n")); artifact.name = "tak-fake-feed-outbound-reports"; artifact.lifetime = .keepAlways; add(artifact)
        #else
        throw XCTSkip("Local location validation is restricted to the simulator")
        #endif
    }

    private func package() -> Data {
        ZipArchive.write(entries: [.init(name: "server.pref", data: Data("<preferences><preference><entry key='connectString0'>127.0.0.1:8088:tcp</entry></preference></preferences>".utf8))])
    }
    private func drain() async { for _ in 0..<20 { await Task.yield() } }
    func testCertificateEnrollmentPackageSuggestsSignInWithoutOverwritingSavedServer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = TAKTestTransport(), location = TAKTestLocation()
        let session = TAKSession(directory: root, transport: transport, driver: location, startTimer: false)
        defer { session.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(session.profile.credentialID ?? session.profile.uid); try? FileManager.default.removeItem(at: root) }
        await session.importPackage(package())
        let previous = session.profile
        let bytes = ZipArchive.write(entries: [.init(name: "server.pref", data: Data("<preferences><preference><entry key='connectString0'>localhost:8090:ssl</entry></preference></preferences>".utf8))])
        await session.importPackage(bytes)
        XCTAssertNil(session.failure)
        XCTAssertEqual(session.enrollmentSuggestion?.host, "localhost")
        XCTAssertEqual(session.enrollmentSuggestion?.streamPort, 8090)
        XCTAssertEqual(session.profile.host, previous.host)
        XCTAssertEqual(session.profile.port, previous.port)
        XCTAssertEqual(try TAKLocalStore(root: root).readProfile().host, previous.host)
        XCTAssertEqual(transport.starts, 0)
        XCTAssertEqual(location.starts, 0)
    }
    func testPackageProfileSaveFailurePreservesPreviousCredentialReferenceAndCanRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = TAKSession(directory: root, transport: TAKTestTransport(), driver: TAKTestLocation(), startTimer: false)
        let store = try TAKLocalStore(root: root)
        defer { session.disconnect(); try? store.deleteCredentials(session.profile.credentialID ?? session.profile.uid); try? FileManager.default.removeItem(at: root) }
        await session.importPackage(package())
        let old = session.profile, oldID = try XCTUnwrap(old.credentialID)
        let profileURL = store.directory.appendingPathComponent("profile.json"), original = try Data(contentsOf: profileURL)
        try FileManager.default.removeItem(at: profileURL)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: false)
        await session.importPackage(package())
        XCTAssertNotNil(session.failure)
        XCTAssertEqual(session.profile.credentialID, oldID)
        XCTAssertNotNil(try store.credentials(oldID))
        try FileManager.default.removeItem(at: profileURL); try original.write(to: profileURL, options: .atomic)
        await session.importPackage(package())
        XCTAssertNil(session.failure)
        XCTAssertNotEqual(session.profile.credentialID, oldID)
        XCTAssertNil(try store.credentials(oldID))
        XCTAssertNotNil(try store.credentials(try XCTUnwrap(session.profile.credentialID)))
    }
    func testDefaultPresenceIsPositionlessAndNoLocationDemandThenExplicitSharingAndBackgroundStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = TAKTestTransport(), location = TAKTestLocation()
        let session = TAKSession(directory: root, transport: transport, driver: location, startTimer: false)
        defer { session.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(session.profile.credentialID ?? session.profile.uid); try? FileManager.default.removeItem(at: root) }
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
        XCTAssertNotNil(session.positionWaitMessage)
        location.onLocations?([CLLocation(coordinate: .init(latitude: 35.1388, longitude: -78.9914), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: Date())])
        session.setCallsign("FAKE POSITION") // force fresh presence on next tick
        session.setForeground(true)
        XCTAssertTrue(transport.sends.contains { $0.contains("lat=\"35.1388000\"") })
        XCTAssertNil(session.positionWaitMessage)
        location.onLocations?([CLLocation(coordinate: .init(latitude: 35.1388,longitude: -78.9914),altitude: 0,horizontalAccuracy: 5,verticalAccuracy: -1,timestamp: Date().addingTimeInterval(-40))])
        session.setCallsign("STALE POSITION")
        session.setForeground(true)
        XCTAssertNotNil(session.positionWaitMessage)
        XCTAssertTrue(transport.sends.last(where: { $0.contains("takv") })?.contains("lat=\"0.0000000\" lon=\"0.0000000\"") == true)
        session.setForeground(false); XCTAssertEqual(location.stops, 0)
        session.sharePosition = false; XCTAssertEqual(location.stops, 1)
        XCTAssertNil(session.positionWaitMessage)
        session.setForeground(false); XCTAssertFalse(session.connected)
        session.disconnect(); XCTAssertFalse(session.sharePosition)
    }
    func testRefusedCertificateStopsAutomaticReconnectAndLateCallbacksCannotReviveDisconnectedSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = TAKTestTransport(), location = TAKTestLocation()
        let session = TAKSession(directory: root, transport: transport, driver: location, startTimer: false)
        defer { session.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(session.profile.credentialID ?? session.profile.uid); try? FileManager.default.removeItem(at: root) }
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
        defer { first.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(first.profile.credentialID ?? first.profile.uid); try? FileManager.default.removeItem(at: root) }
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
        let deferredField = FieldDataStore(directory: root,loadImmediately: false)
        let second = TAKSession(directory: root, transport: secondTransport, driver: TAKTestLocation(), startTimer: false, waypoints: waypoints, field: deferredField)
        defer { second.disconnect() }
        XCTAssertEqual(second.profile.uid, first.profile.uid); XCTAssertTrue(second.sharedFolders.isEmpty)
        second.connect(); await drain(); secondTransport.callback?(.ready); await drain()
        XCTAssertTrue(secondTransport.sends.first?.contains("takv") == true, "Reconnect must announce before offline tombstones")
        XCTAssertFalse(deferredField.ready)
        XCTAssertEqual(secondTransport.sends.filter { $0.contains("type=\"t-x-d-d\"") }.count,2,"Explicit full unsharing must not wait for local track loading")
        await deferredField.load()
        second.setFolderShared("Recon",shared: false); await drain()
        XCTAssertEqual(secondTransport.sends.filter { $0.contains("type=\"t-x-d-d\"") }.count, 2)
        XCTAssertTrue(try local.readSent(profile: second.profile).isEmpty)
    }
    func testUnavailableGraphicSourceDoesNotWithdrawStillSharedDrawingsButFullUnshareStillWorks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        let field = FieldDataStore(directory: root), points = WaypointStore(directory: root)
        let hiddenPoint = points.add(.init(name: "Later hidden",lat: 35,lon: -79,folder: "Recon"))
        try field.saveGraphic(.init(id: "area",name: "Saved area",type: "objective",points: [.init(lat: 35,lon: -79),.init(lat: 35.001,lon: -79),.init(lat: 35.001,lon: -79.001)],folder: "Recon"))
        let firstTransport = TAKTestTransport(), first = TAKSession(directory: root,transport: firstTransport,driver: TAKTestLocation(),startTimer: false,waypoints: points,field: field)
        defer { first.disconnect(); try? TAKLocalStore(root: root).deleteCredentials(first.profile.credentialID ?? first.profile.uid); try? FileManager.default.removeItem(at: root) }
        await first.importPackage(package()); first.connect(); await drain(); firstTransport.callback?(.ready); await drain()
        first.setFolderShared("Recon",shared: true); await drain()
        let local = try TAKLocalStore(root: root)
        XCTAssertEqual(try local.readSent(profile: first.profile).count,2); first.disconnect()
        points.setVisible(id: hiddenPoint.id,visible: false)
        let delayed = FieldDataStore(directory: root,loadImmediately: false), transport = TAKTestTransport()
        let second = TAKSession(directory: root,transport: transport,driver: TAKTestLocation(),startTimer: false,waypoints: points,field: delayed)
        defer { second.disconnect() }
        second.connect(); await drain(); transport.callback?(.ready); await drain()
        let earlyDeletes = transport.sends.filter { $0.contains("type=\"t-x-d-d\"") }
        XCTAssertEqual(earlyDeletes.count,1,"A known hidden waypoint must withdraw even while graphics are unavailable")
        XCTAssertTrue(earlyDeletes.first?.contains("-wp-"+hiddenPoint.id) == true)
        XCTAssertNotNil(second.sharingWaitMessage)
        try Data("unreadable saved index".utf8).write(to: root.appendingPathComponent("field-data-v2.json"))
        await delayed.load(); XCTAssertNotNil(delayed.loadError)
        second.setFolderShared("Recon",shared: true); await drain()
        XCTAssertEqual(transport.sends.filter { $0.contains("type=\"t-x-d-d\"") }.count,1)
        XCTAssertEqual(try local.readSent(profile: second.profile).count,1)
        second.setFolderShared("Recon",shared: false); await drain()
        XCTAssertEqual(transport.sends.filter { $0.contains("type=\"t-x-d-d\"") }.count,2)
        XCTAssertNil(second.sharingWaitMessage); XCTAssertTrue(try local.readSent(profile: second.profile).isEmpty)
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
