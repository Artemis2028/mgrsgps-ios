import Foundation
import GridFixCore
import Security
import XCTest
@testable import MGRSGPS

final class TAKEnrollmentKeyTests: XCTestCase {
    func testDeviceOnlyKeySignsPublicCSRAndIsRemovedAfterCancelledEnrollment() throws {
        var key: TAKEnrollmentKey? = try TAKEnrollmentKey(deviceUID: "TEST-" + UUID().uuidString)
        let tag = try XCTUnwrap(key?.tag)
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag,
                                   kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attrs = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attrs[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(attrs[kSecAttrKeySizeInBits as String] as? Int, 2048)
        XCTAssertEqual(attrs[kSecAttrIsExtractable as String] as? Bool, false)
        let csr = try XCTUnwrap(key).request(subject: [.init(name: "O", value: "GridFix Synthetic Test"), .init(name: "OU", value: "Interop")], username: "CAFÉ field user")
        XCTAssertNotNil(csr.range(of: Data("CAFÉ field user".utf8)))
        // Public CSR only, for an independent OpenSSL signature/subject check.
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("gridfix-enrollment-public-test.csr")
        try csr.write(to: url, options: .atomic)
        key = nil
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, nil), errSecItemNotFound)
    }
    func testUnrelatedSignedCertificateCannotBeInstalledForNewKeyAndPendingKeyIsRemoved() throws {
        var key: TAKEnrollmentKey? = try TAKEnrollmentKey(deviceUID: "TEST-" + UUID().uuidString)
        let tag = try XCTUnwrap(key?.tag)
        XCTAssertThrowsError(try key?.identity(certificate: Data([1, 2, 3]), authorities: []))
        key = nil
        XCTAssertThrowsError(try TAKEnrollmentKey.load(tag: tag, certificate: Data(), authorities: []))
    }
}
