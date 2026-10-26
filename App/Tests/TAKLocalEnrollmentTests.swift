import Foundation
import GridFixCore
import Security
import XCTest
@testable import MGRSGPS

/// Records only the fake-position test's public CoT reports, forwarding every
/// byte and all trust handling through the unchanged native TLS transport.
private final class EnrolledPeerTransport: TAKTransportDriving {
    private let real = TAKTransport()
    var reports: [String] = []
    func start(host: String,port: UInt16,tls: Bool,identity: SecIdentity?,anchors: [SecCertificate],pinnedSHA256: String?,onEvent: @escaping (TAKTransport.Event) -> Void) {
        real.start(host: host,port: port,tls: tls,identity: identity,anchors: anchors,pinnedSHA256: pinnedSHA256,onEvent: onEvent)
    }
    func send(_ xml: String) { if xml.contains("takv") { reports.append(xml) }; real.send(xml) }
    func send(_ xml: String,completion: @escaping (Bool) -> Void) { real.send(xml,completion: completion) }
    func stop() { real.stop() }
}

/// Opt-in development test. The login file must be staged into the simulator;
/// no credentials are in source, arguments, test attachments or diagnostics.
@MainActor final class TAKLocalEnrollmentTests: XCTestCase {
    /// Separate opt-in from the disposable enrollment regression: retains the
    /// real device key/profile for the subsequent native app peer round.
    func testPrepareEnrolledLocalPeerApp() async throws {
        #if targetEnvironment(simulator)
        let documents = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0]
        let file = documents.appendingPathComponent("tak-local-enrolled-peer-login.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Enrolled peer round has not been explicitly staged") }
        struct Login: Decodable { let username: String; let password: String }
        let login = try JSONDecoder().decode(Login.self,from: Data(contentsOf: file))
        defer { try? FileManager.default.removeItem(at: file) }
        let target = try TAKEnrollment.Target(host: "127.0.0.1")
        let pin: String
        do { _ = try await TAKEnrollmentClient.verify(target); XCTFail("Expected explicit local certificate approval"); return }
        catch let approval as TAKEnrollmentClient.NeedsApproval { pin = approval.certificate.sha256 }
        let verified = try await TAKEnrollmentClient.verify(target,approvedPin: pin)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mgrsgps-ui-tests",isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        let transport = EnrolledPeerTransport()
        let session = TAKSession(directory: root,transport: transport,startTimer: true)
        defer { session.disconnect() }
        let enrolled = try await TAKEnrollmentClient.enroll(server: verified,username: login.username,password: login.password,deviceUID: session.profile.uid)
        try session.installEnrollment(enrolled)
        session.setCallsign("IOS-ENR-" + String(session.profile.uid.suffix(8)))
        XCTAssertFalse(session.sharePosition); XCTAssertTrue(session.sharedFolders.isEmpty)
        session.connect()
        for _ in 0..<120 {
            if session.connected,session.lastReceivedAt != nil { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertTrue(session.connected,session.failure ?? session.status)
        XCTAssertNotNil(session.lastReceivedAt)
        print("TAK_ENROLLED_PEER_PREPARED callsign=\(session.profile.callsign) uid=\(session.profile.uid)")
        let continuous = documents.appendingPathComponent("tak-local-enrolled-position-optin")
        if FileManager.default.fileExists(atPath: continuous.path) {
            defer { try? FileManager.default.removeItem(at: continuous) }
            session.sharePosition = true
            func isPosition(_ xml: String) -> Bool { xml.contains("lat=\"35.1389") && xml.contains("lon=\"-78.9909") }
            let deadline = Date().addingTimeInterval(30)
            while !transport.reports.contains(where: isPosition),Date() < deadline { try await Task.sleep(nanoseconds: 250_000_000) }
            let first = try XCTUnwrap(transport.reports.firstIndex(where: isPosition),"Continuous local fake fixes must reach the enrolled native session")
            let heard = session.lastReceivedAt
            print("TAK_ENROLLED_CONTINUOUS_POSITION_READY callsign=\(session.profile.callsign)")
            try await Task.sleep(nanoseconds: 90_000_000_000)
            let reports = Array(transport.reports[first...])
            XCTAssertGreaterThanOrEqual(reports.count,9)
            XCTAssertTrue(reports.allSatisfy(isPosition),"No positionless presence is allowed while fresh fixes continue")
            XCTAssertTrue(session.connected,session.failure ?? session.status)
            XCTAssertNotEqual(session.lastReceivedAt,heard,"The live enrolled connection must continue receiving server data")
            let artifact = XCTAttachment(string: reports.joined(separator: "\n")); artifact.name = "tak-enrolled-fake-position-reports"; artifact.lifetime = .keepAlways; add(artifact)
            print("TAK_ENROLLED_CONTINUOUS_POSITION_COMPLETE reports=\(reports.count)")
            session.sharePosition = false
        }
        #else
        throw XCTSkip("Local peer validation is restricted to the simulator")
        #endif
    }

    func testLocalSignInRejectsWrongPasswordThenEnrollsAndReconnectsWithDeviceKey() async throws {
        #if targetEnvironment(simulator)
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tak-local-enrollment-login.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Local-only enrollment login has not been explicitly staged") }
        struct Login: Decodable { let username: String; let password: String }
        let login = try JSONDecoder().decode(Login.self, from: Data(contentsOf: file))
        defer { try? FileManager.default.removeItem(at: file) }
        let target = try TAKEnrollment.Target(host: "127.0.0.1")
        var fingerprint: String?
        do { _ = try await TAKEnrollmentClient.verify(target); XCTFail("Private CA/name mismatch did not require approval") }
        catch let approval as TAKEnrollmentClient.NeedsApproval { fingerprint = approval.certificate.sha256 }
        let pin = try XCTUnwrap(fingerprint)
        // Refusing a changed pin is independent of credentials and HTTP auth.
        do { _ = try await TAKEnrollmentClient.verify(target, approvedPin: "changed"); XCTFail("Changed pin accepted") }
        catch { XCTAssertFalse(error is TAKEnrollmentClient.NeedsApproval) }
        let server = try await TAKEnrollmentClient.verify(target, approvedPin: pin)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = TAKSession(directory: root, startTimer: true)
        let before = session.profile
        let store = try TAKLocalStore(root: root)
        defer {
            session.disconnect()
            if let id = session.profile.credentialID {
                if let tag = (try? store.credentials(id))?.enrollmentKeyTag { try? TAKEnrollmentKey.delete(tag) }
                try? store.deleteCredentials(id)
            }
            try? FileManager.default.removeItem(at: root)
        }
        do {
            _ = try await TAKEnrollmentClient.enroll(server: server, username: login.username, password: "intentionally-wrong-local-test", deviceUID: before.uid)
            XCTFail("Wrong password was accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Sign-in refused")) }
        XCTAssertEqual(session.profile.host, before.host)
        XCTAssertNil(session.profile.credentialID)
        XCTAssertNil(try store.credentials(before.uid))
        let result = try await TAKEnrollmentClient.enroll(server: server, username: login.username, password: login.password, deviceUID: before.uid)
        XCTAssertNotNil(result.credentials.identity)
        let profileFile = store.directory.appendingPathComponent("profile.json")
        let previousBytes = try Data(contentsOf: profileFile)
        try FileManager.default.removeItem(at: profileFile)
        try FileManager.default.createDirectory(at: profileFile, withIntermediateDirectories: false)
        XCTAssertThrowsError(try session.installEnrollment(result))
        XCTAssertNil(session.profile.credentialID)
        XCTAssertEqual(session.profile.host, before.host)
        // Failed durable save must roll back its newly-created credential
        // archive rather than leave an unreferenced identity/password account.
        var accounts: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "app.gridfix.tak.credentials",
                                   kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        let queryStatus = SecItemCopyMatching(query as CFDictionary, &accounts)
        XCTAssertTrue(queryStatus == errSecSuccess || queryStatus == errSecItemNotFound)
        let ownedAccounts = (accounts as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(before.uid) }
        XCTAssertTrue(ownedAccounts.isEmpty)
        try FileManager.default.removeItem(at: profileFile)
        try previousBytes.write(to: profileFile, options: .atomic)
        try session.installEnrollment(result)
        XCTAssertEqual(session.profile.pin, pin); XCTAssertFalse(session.sharePosition)
        XCTAssertTrue(session.sharedFolders.isEmpty)
        let saved = try store.readProfile(), id = try XCTUnwrap(saved.credentialID)
        let archive = try XCTUnwrap(store.credentials(id))
        XCTAssertNil(archive.client); XCTAssertNil(archive.clientPassword)
        XCTAssertNotNil(try archive.read(saved).identity)
        session.setCallsign("IOS-ENROLL-" + String(saved.uid.suffix(8)))
        session.connect()
        for _ in 0..<120 {
            if session.connected, session.lastReceivedAt != nil { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertTrue(session.connected, session.failure ?? session.status)
        XCTAssertNotNil(session.lastReceivedAt, "Enrolled TLS client must receive the local server's ping reply")
        XCTAssertFalse(session.sharePosition, "Enrollment never enables position sharing")
        session.disconnect(); session.connect()
        for _ in 0..<120 {
            if session.connected, session.lastReceivedAt != nil { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertTrue(session.connected, session.failure ?? session.status)
        XCTAssertNotNil(session.lastReceivedAt)
        session.disconnect()
        let relaunched = TAKSession(directory: root, startTimer: true)
        defer { relaunched.disconnect() }
        XCTAssertFalse(relaunched.sharePosition)
        relaunched.connect()
        for _ in 0..<120 {
            if relaunched.connected, relaunched.lastReceivedAt != nil { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertTrue(relaunched.connected, relaunched.failure ?? relaunched.status)
        XCTAssertNotNil(relaunched.lastReceivedAt)
        #else
        throw XCTSkip("Local enrollment validation is restricted to the simulator")
        #endif
    }
}
