import Foundation
import GridFixCore
import Security
import XCTest
@testable import MGRSGPS

/// Opt-in development test. The login file must be staged into the simulator;
/// no credentials are in source, arguments, test attachments or diagnostics.
@MainActor final class TAKLocalEnrollmentTests: XCTestCase {
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
