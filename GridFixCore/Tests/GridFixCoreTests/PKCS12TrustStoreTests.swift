import XCTest
@testable import GridFixCore

final class PKCS12TrustStoreTests: XCTestCase {
    private func fixture(_ name: String, ext: String = "p12") throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext)))
    }
    func testOpenSSLGoldenCAOnlyStoresLegacyAndPBES2YieldExactDER() throws {
        let expected = try fixture("p12-ca-expected", ext: "cer")
        for name in ["aes256", "aes192", "aes128-sha512", "3des", "rc2-40", "rc2-128", "plain", "jca-aes-sha1-prf", "jca-aes-sha512-prf", "jdktrust"] {
            XCTAssertEqual(try PKCS12TrustStore.certificates(fixture("p12-ca-" + name), password: "fixture-password"), [expected], name)
        }
        XCTAssertEqual(try PKCS12TrustStore.certificates(fixture("p12-ca-unicode"), password: "fixtüré🔭"), [expected])
        XCTAssertEqual(try PKCS12TrustStore.certificates(fixture("p12-ca-empty"), password: ""), [expected])
        XCTAssertEqual(try PKCS12TrustStore.certificates(fixture("p12-ca-aes-empty"), password: ""), [expected])
        XCTAssertEqual(try PKCS12TrustStore.certificates(fixture("p12-ca-jca-rc2-empty"), password: ""), [expected])
    }
    func testWrongPasswordAndModifiedFileAreNeverAcceptedAsTrustAnchors() throws {
        for name in ["aes256", "3des", "rc2-40", "plain", "unicode", "empty"] {
            XCTAssertThrowsError(try PKCS12TrustStore.certificates(fixture("p12-ca-" + name), password: "wrong")) { error in
                XCTAssertEqual(error as? PKCS12TrustStore.Failure, .authentication)
            }
        }
        var changed = try fixture("p12-ca-aes256")
        changed[changed.count / 2] ^= 1
        XCTAssertThrowsError(try PKCS12TrustStore.certificates(changed, password: "fixture-password")) { error in
            XCTAssertEqual(error as? PKCS12TrustStore.Failure, .authentication)
        }
        XCTAssertThrowsError(try PKCS12TrustStore.certificates(fixture("p12-ca-no-mac"), password: "fixture-password"))
    }
    func testCryptographicWorkBudgetRejectsExpensiveAuthenticatedInputBeforeDerivation() throws {
        XCTAssertThrowsError(try PKCS12TrustStore.certificates(fixture("p12-ca-excessive-iterations"), password: "fixture-password")) { error in
            XCTAssertEqual(error as? PKCS12TrustStore.Failure, .limits)
        }
        var zero = try fixture("p12-ca-aes256")
        XCTAssertEqual(Array(zero.suffix(4)), [0x02, 0x02, 0x08, 0x00])
        zero[zero.count - 2] = 0
        XCTAssertThrowsError(try PKCS12TrustStore.certificates(zero, password: "fixture-password"))
    }
    func testMalformedOversizedAndIndefiniteLengthInputFailWithoutIndexingTraps() throws {
        for data in [Data(), Data([0x30, 0x80, 0, 0]), Data([0x30, 0x84, 255, 255, 255, 255]), Data([0x30, 0x81, 0]), Data([0x30, 0x7f])] {
            XCTAssertThrowsError(try PKCS12TrustStore.certificates(data, password: "fixture-password"))
        }
        XCTAssertThrowsError(try PKCS12TrustStore.certificates(Data(repeating: 0, count: 2 * 1024 * 1024 + 1), password: ""))
        XCTAssertThrowsError(try PKCS12TrustStore.certificates(fixture("p12-ca-aes256"), password: String(repeating: "x", count: 1025)))
        let valid = try fixture("p12-ca-aes256")
        for count in stride(from: 0, to: valid.count, by: 17) {
            XCTAssertThrowsError(try PKCS12TrustStore.certificates(valid.prefix(count), password: "fixture-password"))
        }
    }
}
