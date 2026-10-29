import Foundation
import GridFixCore
import Security
import XCTest
@testable import MGRSGPS

private struct LocalRenewalFixture: Decodable {
    let username: String
    let password: String
    let expectedServerSHA256: String
    enum Invalid: Error { case staging }
    static let filename = "tak-local-renewal-proof-login.json"
    static func decode(_ bytes: Data, permissions: Int, regular: Bool) throws -> Self {
        guard regular, permissions == 0o600, bytes.count <= 16_384 else { throw Invalid.staging }
        guard let value = try? JSONDecoder().decode(Self.self,from: bytes),
              !value.username.isEmpty, !value.password.isEmpty,
              value.expectedServerSHA256.utf8.count == 95,
              value.expectedServerSHA256.range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){31}$",options: .regularExpression) != nil else { throw Invalid.staging }
        return value
    }
    static func target() throws -> TAKEnrollment.Target {
        try .init(host: "127.0.0.1",enrollmentPort: 8446,streamPort: 8089)
    }
}

/// Observe native TLS lifecycle without altering traffic, trust, or credentials.
private final class LocalRenewalWire: TAKTransportDriving {
    private let native = TAKTransport()
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var presentedCertificates: [Data] = []
    func start(host: String,port: UInt16,tls: Bool,identity: SecIdentity?,anchors: [SecCertificate],pinnedSHA256: String?,onEvent: @escaping (TAKTransport.Event) -> Void) {
        starts += 1
        if let identity {
            var certificate: SecCertificate?
            if SecIdentityCopyCertificate(identity,&certificate) == errSecSuccess,let certificate {
                presentedCertificates.append(SecCertificateCopyData(certificate) as Data)
            }
        }
        native.start(host: host,port: port,tls: tls,identity: identity,anchors: anchors,pinnedSHA256: pinnedSHA256,onEvent: onEvent)
    }
    func send(_ xml: String) { native.send(xml) }
    func send(_ xml: String,completion: @escaping (Bool) -> Void) { native.send(xml,completion: completion) }
    func stop() { stops += 1; native.stop() }
}

@MainActor final class TAKLocalRenewalTests: XCTestCase {
    private func waitFor(_ session: TAKSession, after date: Date? = nil) async throws {
        for _ in 0..<120 {
            if session.connected,let received = session.lastReceivedAt,(date.map { received > $0 } ?? true) { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTFail("The local enrolled TLS session did not receive fresh server data")
        throw LocalRenewalFixture.Invalid.staging
    }
    func testOptInNativeRenewalPreservesOpenTLSAndReconnectsWithNewDeviceKey() async throws {
        #if targetEnvironment(simulator)
        executionTimeAllowance = 300
        let file = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent(LocalRenewalFixture.filename)
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Coordinated local renewal proof has not been explicitly staged") }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let regular = attributes[.type] as? FileAttributeType == .typeRegular
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard regular,permissions == 0o600,((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 16_384 else { throw LocalRenewalFixture.Invalid.staging }
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes: Data
        do {
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            bytes = try input.read(upToCount: 16_385) ?? Data()
        }
        try FileManager.default.removeItem(at: file) // Consume before any network operation.
        let fixture = try LocalRenewalFixture.decode(bytes,permissions: permissions,regular: regular)
        let target = try LocalRenewalFixture.target()
        let verified = try await TAKEnrollmentClient.verify(target,approvedPin: fixture.expectedServerSHA256)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try TAKLocalStore(root: root), wire = LocalRenewalWire()
        let session = TAKSession(directory: root,transport: wire,startTimer: true)
        var ownedIDs: [String] = []
        defer {
            session.disconnect()
            for id in ownedIDs {
                if let archive = try? store.credentials(id),let tag = archive.enrollmentKeyTag { try? TAKEnrollmentKey.delete(tag) }
                try? store.deleteCredentials(id)
            }
            try? FileManager.default.removeItem(at: root)
        }
        let first = try await TAKEnrollmentClient.enroll(server: verified,username: fixture.username,password: fixture.password,deviceUID: session.profile.uid)
        try session.installEnrollment(first)
        let oldID = try XCTUnwrap(session.profile.credentialID); ownedIDs.append(oldID)
        let oldArchive = try XCTUnwrap(store.credentials(oldID)), oldTag = try XCTUnwrap(oldArchive.enrollmentKeyTag)
        XCTAssertNotNil(try oldArchive.read(session.profile).identity)
        XCTAssertFalse(session.sharePosition); XCTAssertTrue(session.sharedFolders.isEmpty)
        session.setCallsign("IOS-RENEW-LOCAL")
        session.connect(); try await waitFor(session)
        XCTAssertTrue(wire.presentedCertificates.last == first.certificates.client,"Initial TLS must use the first real enrolled certificate")
        XCTAssertTrue(session.suggestCertificateRenewal())
        let renewal = try XCTUnwrap(session.renewalContext), uid = session.profile.uid
        let renewedServer = try await TAKEnrollmentClient.verify(renewal.target,approvedPin: renewal.pin)
        let second = try await TAKEnrollmentClient.enroll(server: renewedServer,username: fixture.username,password: fixture.password,deviceUID: uid)
        let starts = wire.starts, stops = wire.stops, received = try XCTUnwrap(session.lastReceivedAt)
        try session.installEnrollment(second,renewal: renewal)
        let newID = try XCTUnwrap(session.profile.credentialID); ownedIDs.append(newID)
        let renewedArchive = try XCTUnwrap(store.credentials(newID))
        let newTag = try XCTUnwrap(renewedArchive.enrollmentKeyTag)
        XCTAssertTrue(newTag != oldTag,"Renewal must create a different device-only key")
        XCTAssertNil(renewedArchive.client); XCTAssertNil(renewedArchive.clientPassword); XCTAssertNil(renewedArchive.caPassword)
        XCTAssertNotNil(session.clientCertificate?.validity)
        XCTAssertTrue(newID != oldID); XCTAssertTrue(second.certificates.client != first.certificates.client)
        XCTAssertTrue(session.connected); XCTAssertEqual(wire.starts,starts); XCTAssertEqual(wire.stops,stops)
        XCTAssertEqual(session.profile.uid,uid); XCTAssertEqual(session.profile.callsign,"IOS-RENEW-LOCAL")
        XCTAssertFalse(session.sharePosition); XCTAssertTrue(session.sharedFolders.isEmpty)
        XCTAssertNil(try store.credentials(oldID))
        XCTAssertThrowsError(try TAKEnrollmentKey.load(tag: oldTag,certificate: first.certificates.client,authorities: first.certificates.authorities))
        try await waitFor(session,after: received) // Existing authenticated socket survives key replacement.
        XCTAssertEqual(wire.starts,starts,"A silent reconnect must not count as open-socket renewal continuity")
        XCTAssertEqual(wire.stops,stops)
        let beforeReconnect = try XCTUnwrap(session.lastReceivedAt)
        session.disconnect(); session.connect(); try await waitFor(session,after: beforeReconnect)
        XCTAssertTrue(wire.presentedCertificates.last == second.certificates.client,"Reconnect must use the newly enrolled native identity")
        session.disconnect()
        let reloadWire = LocalRenewalWire(), reload = TAKSession(directory: root,transport: reloadWire,startTimer: true)
        defer { reload.disconnect() }
        XCTAssertTrue(reload.profile.credentialID == newID); XCTAssertFalse(reload.sharePosition)
        XCTAssertEqual(reload.profile.uid,uid); XCTAssertEqual(reload.profile.callsign,"IOS-RENEW-LOCAL")
        XCTAssertTrue(reload.sharedFolders.isEmpty)
        reload.connect(); try await waitFor(reload)
        XCTAssertTrue(reloadWire.presentedCertificates.last == second.certificates.client,"Fresh-session reload must recover the renewed device key")
        #else
        throw XCTSkip("Local renewal proof is restricted to a simulator")
        #endif
    }
}

final class TAKLocalRenewalGuardTests: XCTestCase {
    private var pin: String { Array(repeating: "AB",count: 32).joined(separator: ":") }
    private func bytes(pin: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["username":"CAFÉ local user","password":"  synthetic secret  ","expectedServerSHA256":pin ?? self.pin])
    }
    func testPrivatePinnedFixturePreservesWhitespaceAndUsesOnlyPreparedEndpoints() throws {
        let value = try LocalRenewalFixture.decode(bytes(),permissions: 0o600,regular: true)
        XCTAssertEqual(value.password,"  synthetic secret  ")
        let target = try LocalRenewalFixture.target()
        XCTAssertEqual(target.host,"127.0.0.1"); XCTAssertEqual(target.enrollmentPort,8446); XCTAssertEqual(target.streamPort,8089)
    }
    func testUnpinnedOversizedPublicOrNonregularFixturesFailBeforeNetwork() throws {
        for bad in ["", "not-a-pin",pin+"\n"] { XCTAssertThrowsError(try LocalRenewalFixture.decode(bytes(pin: bad),permissions: 0o600,regular: true)) }
        XCTAssertThrowsError(try LocalRenewalFixture.decode(bytes(),permissions: 0o644,regular: true))
        XCTAssertThrowsError(try LocalRenewalFixture.decode(bytes(),permissions: 0o600,regular: false))
        XCTAssertThrowsError(try LocalRenewalFixture.decode(Data(repeating: 0,count: 16_385),permissions: 0o600,regular: true))
        XCTAssertThrowsError(try LocalRenewalFixture.decode(Data("{}".utf8),permissions: 0o600,regular: true))
    }
    func testNativeFileMetadataRejectsALinkWithoutTouchingItsTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("synthetic.json"), link = directory.appendingPathComponent("link.json")
        let original = try bytes()
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: link,withDestinationURL: target)
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType,.typeSymbolicLink)
        XCTAssertThrowsError(try LocalRenewalFixture.decode(original,permissions: 0o600,regular: attributes[.type] as? FileAttributeType == .typeRegular))
        XCTAssertTrue(try Data(contentsOf: target) == original)
    }
}
