import CoreLocation
import Foundation
@testable import GridFixCore
import Security
import XCTest
@testable import MGRSGPS

private final class CertificateDetailsTransport: TAKTransportDriving {
    var starts = 0,stops = 0
    var callback: ((TAKTransport.Event) -> Void)?
    func start(host: String,port: UInt16,tls: Bool,identity: SecIdentity?,anchors: [SecCertificate],pinnedSHA256: String?,onEvent: @escaping (TAKTransport.Event) -> Void) { starts += 1; callback = onEvent }
    func send(_ xml: String) {}
    func stop() { stops += 1 }
}
@MainActor private final class CertificateDetailsLocation: RecordingLocationDriver {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var precise = true,servicesEnabled = true,starts = 0,stops = 0,requests = 0
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    func requestPermission() { requests += 1 }
    func start() { starts += 1 }
    func stop() { stops += 1 }
}
@MainActor
final class TAKCertificateDetailsTests: XCTestCase {
    // Public synthetic CA only, shared with the strict server-trust tests.
    private let certificate = Data(base64Encoded: "MIIDCDCCAfCgAwIBAgIUKyRXlRsHq5k7uJeuEQGM/9bvk9AwDQYJKoZIhvcNAQELBQAwJDEiMCAGA1UEAwwZR3JpZEZpeCBzeW50aGV0aWMgdGVzdCBDQTAeFw0yNjEwMjUxNDM2NDRaFw0zNjEwMjIxNDM2NDRaMCQxIjAgBgNVBAMMGUdyaWRGaXggc3ludGhldGljIHRlc3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC+NeGdZ+eL7d9X4dWkO/6ugGF97o8/hKQKydfZTLLomPrrmoyGm/ICXpsgRBwHmLIPGunr8TNobtRTNTjPM3oqKKe4hWJewCJOkJopO1H5BgtBiTJcxuChk+1cNAA4zQvHKj09RVcvd30Ewa6CftgEJnc1u22Qmdfmce5BofpyBcr19bmFSx/rvWQGOTSBLbBortfgru54pK888gv2ZwevRkwgyFL2+7yvDnRQJdCzoBF36jnUFDzwLNuviEPTsae/YzOXy8qUL9kHb+1aQiHMA0p+wel05mx4m9WHJ+Z5rFHFTWius7VMSIrv89cDpetfY6njgOlxjwbck+khJKwrAgMBAAGjMjAwMB0GA1UdDgQWBBSTRXS2rZ2kd7OJEc11R0CWntHL+zAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQA3vZKvYe1atHGboo/i8g4r8apwktRjNDpSu4SuiCaAJQD2rsl9m2Kr0uUyOkWcVXHNakRHdr1Nx0RR6xhr9bQ2mqiWIhPazpnO+8Nu/jAhoOr3wLnKUEQQ4FXqKfr2/tO+k4+kAk9HzP0H7EVLynKEQSd6vVvvWRUs3aGTw7u0+EomfoV/ghQk5hY5B+96ZBtvqYDjC7zEkITehRaKSMJL7m322cgX0o68qODOAdDuulMMrNe/SgkgTh+vCpFgS3vLZ+tmmV+/OWY3upw1tJUEwIVqcInCNaP/IK4YH0Ptfy1ZEqMM0DGnsSvWDAYd9yzzbSOhY7GIvty7gsi6nb+z")!
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private func encodedTime(_ tag: UInt8,_ text: String) -> Data { Data([tag,UInt8(text.utf8.count)]) + Data(text.utf8) }
    private func certificateDates(_ start: Data,_ end: Data,version: Bool = true) -> Data {
        func node(_ tag: UInt8,_ value: Data) -> Data { Data([tag,UInt8(value.count)]) + value }
        let empty = node(0x30,Data())
        let fields = (version ? Data([0xA0,3,2,1,2]) : Data()) + Data([2,1,1]) + empty + empty + node(0x30,start+end) + empty + empty
        return node(0x30,node(0x30,fields)+empty+Data([3,1,0]))
    }
    func testActualCertificateDatesAndFingerprintArePublicMetadata() throws {
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil,certificate as CFData))
        let info = TAKClientCertificateInfo.certificate(cert), validity = try XCTUnwrap(info.validity)
        XCTAssertEqual(TAKClientCertificateInfo.dateLabel(validity.notBefore),"2026-10-25 14:36:44 UTC")
        XCTAssertEqual(TAKClientCertificateInfo.dateLabel(validity.notAfter),"2036-10-22 14:36:44 UTC")
        XCTAssertEqual(info.subject,"GridFix synthetic test CA")
        XCTAssertEqual(info.sha256,"23:23:09:06:A9:C2:0F:3D:30:DC:4B:66:6A:84:B0:A6:B2:72:C5:97:3E:0A:7D:43:9B:20:E3:49:A5:76:27:54")
        XCTAssertEqual(info.state(at: validity.notBefore.addingTimeInterval(-1)),.notYetActive)
        XCTAssertEqual(info.state(at: validity.notBefore),.withinDates)
        XCTAssertEqual(info.state(at: validity.notAfter.addingTimeInterval(-30*86400)),.expiresSoon)
        XCTAssertEqual(info.state(at: validity.notAfter),.expiresSoon)
        XCTAssertEqual(info.state(at: validity.notAfter.addingTimeInterval(0.001)),.expired)
    }
    func testRFCUTCRolloverGeneralizedTimeAndUnversionedCertificateMetadata() throws {
        let bytes = certificateDates(encodedTime(0x17,"500101000000Z"),encodedTime(0x17,"491231235959Z"),version: false)
        let value = try XCTUnwrap(TAKServerTrust.validity(bytes))
        XCTAssertEqual(TAKClientCertificateInfo.dateLabel(value.notBefore),"1950-01-01 00:00:00 UTC")
        XCTAssertEqual(TAKClientCertificateInfo.dateLabel(value.notAfter),"2049-12-31 23:59:59 UTC")
        let future = try XCTUnwrap(TAKServerTrust.validity(certificateDates(encodedTime(0x18,"20500101000000Z"),encodedTime(0x18,"99991231235959Z"))))
        XCTAssertEqual(TAKClientCertificateInfo.dateLabel(future.notBefore),"2050-01-01 00:00:00 UTC")
        XCTAssertEqual(TAKClientCertificateInfo.dateLabel(future.notAfter),"9999-12-31 23:59:59 UTC")
    }
    func testMalformedOrUnsupportedDatesAreUnknownNeverNormalizedOrTrusted() {
        let good = encodedTime(0x17,"261025143644Z")
        for bad in [encodedTime(0x17,"260230143644Z"),encodedTime(0x17,"261325143644Z"),encodedTime(0x17,"261025243644Z"),encodedTime(0x17,"261025143660Z"),encodedTime(0x17,"261025143644+0000"),encodedTime(0x18,"20500101000000.0Z"),encodedTime(0x16,"261025143644Z")] {
            XCTAssertNil(TAKServerTrust.validity(certificateDates(good,bad)))
        }
        XCTAssertNil(TAKServerTrust.validity(certificateDates(encodedTime(0x17,"271025143644Z"),good)))
        for bad in [Data(),Data([0x30,0x80]),Data([0x30,0x84,0xff,0xff,0xff,0xff]),certificate+Data([0]),Data(repeating: 0,count: 1024*1024+1)] { XCTAssertNil(TAKServerTrust.validity(bad)) }
        XCTAssertEqual(TAKClientCertificateInfo(subject: "Unknown",sha256: "",validity: nil).state(at: Date()),.unknown)
    }
    func testPublicEnrollmentDatesRemainReadableWithoutLoadingMissingPrivateKey() throws {
        let root = try directory(), store = try TAKLocalStore(root: root), id = "metadata-test-"+UUID().uuidString
        defer { try? store.deleteCredentials(id) }
        let json: [String:Any] = ["enrollmentCertificate":certificate.base64EncodedString(),"enrollmentKeyTag":Data("MISSING-SYNTHETIC-KEY".utf8).base64EncodedString(),"enrollmentAuthorities":[]]
        let archive = try JSONDecoder().decode(TAKCredentialArchive.self,from: JSONSerialization.data(withJSONObject: json))
        try store.saveCredentials(archive,uid: id)
        XCTAssertThrowsError(try archive.read(TAKProfile()))
        let info = try XCTUnwrap(TAKClientCertificateInfo.read(store: store,id: id))
        XCTAssertNotNil(info.validity); XCTAssertEqual(info.subject,"GridFix synthetic test CA")
    }
    func testRefreshAndRenewalPrefillDoNotConnectChangeTrustOrSharePosition() async throws {
        let root = try directory(), store = try TAKLocalStore(root: root)
        var profile = try store.readProfile(); profile.host = "127.0.0.1"; profile.port = 8089; profile.enrollmentPort = 8446; profile.pin = "keep-this-pin"
        try store.write(profile)
        let before = try Data(contentsOf: store.directory.appendingPathComponent("profile.json")), transport = CertificateDetailsTransport()
        let session = TAKSession(directory: root,transport: transport,startTimer: false)
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil,certificate as CFData)), info = TAKClientCertificateInfo.certificate(cert)
        await session.refreshCertificateDetails(reader: { _,_ in XCTAssertFalse(Thread.isMainThread); return info })
        XCTAssertEqual(session.clientCertificate,info); XCTAssertFalse(session.loadingCertificateDetails)
        XCTAssertTrue(session.suggestCertificateRenewal())
        XCTAssertEqual(session.enrollmentSuggestion,try TAKEnrollment.Target(host: "127.0.0.1",enrollmentPort: 8446,streamPort: 8089))
        session.clearEnrollmentSuggestion()
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("profile.json")),before)
        XCTAssertEqual(session.profile.pin,"keep-this-pin"); XCTAssertFalse(session.sharePosition); XCTAssertEqual(transport.starts,0)
        await session.refreshCertificateDetails(reader: { _,_ in throw CocoaError(.fileReadNoPermission,userInfo: [NSLocalizedDescriptionKey:"SYNTHETIC PRIVATE INPUT MUST NOT APPEAR"]) })
        XCTAssertFalse(session.certificateDetailsStatus.contains("PRIVATE INPUT")); XCTAssertNil(session.failure); XCTAssertEqual(transport.starts,0)
    }
    func testLegacyProfileUsesDefaultEnrollmentPortAndInvalidPortsAreRefused() throws {
        let root = try directory(), store = try TAKLocalStore(root: root)
        var profile = try store.readProfile(); profile.host = "127.0.0.1"; profile.enrollmentPort = nil
        try store.write(profile)
        let session = TAKSession(directory: root,startTimer: false)
        XCTAssertTrue(session.suggestCertificateRenewal()); XCTAssertEqual(session.enrollmentSuggestion?.enrollmentPort,8446)
        profile.enrollmentPort = 0; try store.write(profile)
        let invalid = TAKSession(directory: root,startTimer: false)
        XCTAssertFalse(invalid.suggestCertificateRenewal()); XCTAssertNil(invalid.enrollmentSuggestion)
    }
    /// Profile/transport lifecycle tests accept a synthetic Result at the
    /// already-validated-result seam. They do not issue a certificate or prove
    /// TLS/key binding; those remain covered by the enrollment/strict trust tests.
    private func acceptedResult(_ renewal: TAKSession.Renewal) throws -> TAKEnrollmentClient.Result {
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil,certificate as CFData))
        return .init(server: .init(target: renewal.target,certificate: TAKServerTrust.describe(cert),explicitlyApproved: true),
                     key: try TAKEnrollmentKey(deviceUID: renewal.uid),certificates: .init(client: certificate,authorities: [certificate]),
                     credentials: .init(identity: nil,anchors: [cert]))
    }
    private func connectedFixture() async throws -> (TAKLocalStore,TAKSession,CertificateDetailsTransport,CertificateDetailsLocation) {
        let root = try directory(),store = try TAKLocalStore(root: root)
        var profile = try store.readProfile(); profile.host = "127.0.0.1"; profile.enrollmentPort = 8446; profile.sharedFolders = ["Base"]
        profile.credentialID = profile.uid+"-old"; try store.write(profile)
        let package = TAKServerPackage(description: "Synthetic lifecycle",host: "127.0.0.1",port: 8089,usesTLS: true,caPKCS12: certificate,caPassword: nil,clientPKCS12: nil,clientPassword: nil)
        try store.saveCredentials(.init(package),uid: profile.credentialID!)
        let oldID = profile.credentialID!
        addTeardownBlock { try? store.deleteCredentials(oldID) }
        let transport = CertificateDetailsTransport(),location = CertificateDetailsLocation()
        let session = TAKSession(directory: root,transport: transport,driver: location,startTimer: false)
        session.connect()
        for _ in 0..<100 where transport.starts == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(transport.starts,1); transport.callback?(.ready)
        for _ in 0..<100 where !session.connected { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(session.connected); session.sharePosition = true
        return (store,session,transport,location)
    }
    func testSuccessfulRenewalKeepsReadyConnectionCurrentPolicyAndRemoteScene() async throws {
        let (store,session,transport,location) = try await connectedFixture()
        let peer = try TAKCoT.presence(uid: "synthetic-peer",callsign: "SYNTHETIC PEER",now: Date(),position: .init(lat: 24,lon: 54),accuracy: 5)
        transport.callback?(.xml(peer))
        for _ in 0..<100 where session.remoteItems.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(session.remoteItems.count,1)
        XCTAssertTrue(session.suggestCertificateRenewal()); let context = try XCTUnwrap(session.renewalContext)
        let result = try acceptedResult(context),oldID = session.profile.credentialID!,starts = transport.starts,stops = transport.stops,locationStops = location.stops
        defer { session.disconnect(); try? store.deleteCredentials(session.profile.credentialID!); try? TAKEnrollmentKey.delete(result.key.tag) }
        session.setCallsign("LATEST LOCAL CALLSIGN")
        try session.installEnrollment(result,renewal: context)
        XCTAssertTrue(session.connected); XCTAssertTrue(session.sharePosition); XCTAssertEqual(session.sharedFolders,["Base"])
        XCTAssertEqual(session.profile.callsign,"LATEST LOCAL CALLSIGN"); XCTAssertEqual(session.remoteItems.count,1)
        XCTAssertEqual(transport.starts,starts); XCTAssertEqual(transport.stops,stops); XCTAssertEqual(location.stops,locationStops)
        XCTAssertNotEqual(session.profile.credentialID,oldID)
        XCTAssertEqual(try store.readProfile().credentialID,session.profile.credentialID)
        XCTAssertEqual(try store.credentials(session.profile.credentialID!)?.enrollmentKeyTag,result.key.tag)
        XCTAssertNil(try store.credentials(oldID)); XCTAssertNotNil(session.certificateRenewalMessage)
    }
    func testFailedRenewalProfileCommitKeepsWorkingCredentialsAndSession() async throws {
        let (store,session,transport,_) = try await connectedFixture()
        XCTAssertTrue(session.suggestCertificateRenewal()); let context = try XCTUnwrap(session.renewalContext)
        let result = try acceptedResult(context),oldID = session.profile.credentialID!,stops = transport.stops
        defer { session.disconnect(); try? TAKEnrollmentKey.delete(result.key.tag) }
        let file = store.directory.appendingPathComponent("profile.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        XCTAssertThrowsError(try session.installEnrollment(result,renewal: context))
        XCTAssertEqual(session.profile.credentialID,oldID); XCTAssertNotNil(try store.credentials(oldID))
        XCTAssertTrue(session.connected); XCTAssertTrue(session.sharePosition); XCTAssertEqual(session.sharedFolders,["Base"])
        XCTAssertEqual(transport.stops,stops)
    }
    func testRenewalFromOlderCredentialCannotReplaceANewerConnection() async throws {
        let (store,session,_,_) = try await connectedFixture()
        XCTAssertTrue(session.suggestCertificateRenewal()); let context = try XCTUnwrap(session.renewalContext)
        let result = try acceptedResult(context)
        defer { session.disconnect(); try? TAKEnrollmentKey.delete(result.key.tag); if let id = session.profile.credentialID { try? store.deleteCredentials(id) } }
        let pref = "<preferences><preference name=\"cot_streams\"><entry key=\"connectString0\" class=\"class java.lang.String\">127.0.0.1:8089:tcp</entry></preference></preferences>"
        await session.importPackage(ZipArchive.write(entries: [.init(name: "certs/server.pref",data: Data(pref.utf8))]))
        let replacement = session.profile.credentialID
        XCTAssertThrowsError(try session.installEnrollment(result,renewal: context))
        XCTAssertEqual(session.profile.credentialID,replacement); XCTAssertFalse(session.profile.tls); XCTAssertFalse(session.sharePosition)
    }
    func testFreshSignInKeepsExistingResetBehavior() async throws {
        let (store,session,transport,_) = try await connectedFixture()
        XCTAssertTrue(session.suggestCertificateRenewal()); let context = try XCTUnwrap(session.renewalContext)
        let result = try acceptedResult(context),stops = transport.stops
        defer { try? store.deleteCredentials(session.profile.credentialID!); try? TAKEnrollmentKey.delete(result.key.tag) }
        try session.installEnrollment(result)
        XCTAssertFalse(session.connected); XCTAssertFalse(session.sharePosition); XCTAssertTrue(session.sharedFolders.isEmpty)
        XCTAssertGreaterThan(transport.stops,stops); XCTAssertNil(session.certificateRenewalMessage)
    }

    func testStaleMetadataCannotReplaceNewImportedConnection() async throws {
        let root = try directory(), store = try TAKLocalStore(root: root)
        var profile = try store.readProfile(); profile.host = "127.0.0.1"; try store.write(profile)
        let transport = CertificateDetailsTransport(),session = TAKSession(directory: root,transport: transport,startTimer: false)
        let entered = expectation(description: "old metadata read entered"), release = DispatchSemaphore(value: 0)
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil,certificate as CFData)), old = TAKClientCertificateInfo.certificate(cert)
        let work = Task { await session.refreshCertificateDetails(reader: { _,_ in entered.fulfill(); release.wait(); return old }) }
        await fulfillment(of: [entered],timeout: 5)
        let pref = "<preferences><preference name=\"cot_streams\"><entry key=\"connectString0\" class=\"class java.lang.String\">127.0.0.1:8089:tcp</entry></preference></preferences>"
        await session.importPackage(ZipArchive.write(entries: [.init(name: "certs/server.pref",data: Data(pref.utf8))]))
        defer { if let id = session.profile.credentialID { try? store.deleteCredentials(id) } }
        release.signal(); await work.value
        XCTAssertFalse(session.profile.tls); XCTAssertNil(session.clientCertificate)
        XCTAssertFalse(session.loadingCertificateDetails); XCTAssertEqual(transport.starts,0)
    }
}
