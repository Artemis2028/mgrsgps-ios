import Foundation
import GridFixCore
import XCTest
@testable import MGRSGPS

/// Explicit opt-in fixture, staged into this simulator app's Documents directory.
/// Never run against a configured user server or obtain a real GPS position.
final class TAKLocalServerTests: XCTestCase {
    func testPreparedLocalPackageBlocksOnNameMismatchBeforeSending() throws {
        #if targetEnvironment(simulator)
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tak-local-validation.zip")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("Local-only connection package has not been explicitly staged")
        }
        let package = try TAKConnectionPackage.read(Data(contentsOf: file))
        guard package.host == "127.0.0.1", package.port == 8089, package.usesTLS else {
            return XCTFail("Refusing to connect outside the authorized local TLS endpoint")
        }
        let credentials = try TAKImportedCredentials.read(package)
        XCTAssertNotNil(credentials.identity); XCTAssertFalse(credentials.anchors.isEmpty)
        let decision = expectation(description: "Unapproved certificate name blocks application traffic")
        let transport = TAKTransport()
        defer { transport.stop() }
        transport.start(host: package.host, port: 8089, tls: true, identity: credentials.identity,
                        anchors: credentials.anchors, pinnedSHA256: nil) { event in
            switch event {
            case let .trustRequired(certificate):
                XCTAssertTrue(certificate.subject.contains("opentakserver") || certificate.names.contains("opentakserver"))
                XCTAssertEqual(certificate.sha256.split(separator: ":").count, 32)
                decision.fulfill()
            case .ready: XCTFail("Unapproved hostname mismatch was accepted"); decision.fulfill()
            case let .failed(reason), let .refused(reason): XCTFail(reason); decision.fulfill()
            case .xml: XCTFail("Application traffic received before trust approval")
            }
        }
        wait(for: [decision], timeout: 25)
        #else
        throw XCTSkip("Development server validation is restricted to the simulator")
        #endif
    }
}
