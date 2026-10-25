import Foundation
import Security
import XCTest
@testable import MGRSGPS

final class TAKServerTrustTests: XCTestCase {
    // Public synthetic certificates only. No client key or local-server credentials.
    private let caDER = Data(base64Encoded: "MIIDCDCCAfCgAwIBAgIUKyRXlRsHq5k7uJeuEQGM/9bvk9AwDQYJKoZIhvcNAQELBQAwJDEiMCAGA1UEAwwZR3JpZEZpeCBzeW50aGV0aWMgdGVzdCBDQTAeFw0yNjEwMjUxNDM2NDRaFw0zNjEwMjIxNDM2NDRaMCQxIjAgBgNVBAMMGUdyaWRGaXggc3ludGhldGljIHRlc3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC+NeGdZ+eL7d9X4dWkO/6ugGF97o8/hKQKydfZTLLomPrrmoyGm/ICXpsgRBwHmLIPGunr8TNobtRTNTjPM3oqKKe4hWJewCJOkJopO1H5BgtBiTJcxuChk+1cNAA4zQvHKj09RVcvd30Ewa6CftgEJnc1u22Qmdfmce5BofpyBcr19bmFSx/rvWQGOTSBLbBortfgru54pK888gv2ZwevRkwgyFL2+7yvDnRQJdCzoBF36jnUFDzwLNuviEPTsae/YzOXy8qUL9kHb+1aQiHMA0p+wel05mx4m9WHJ+Z5rFHFTWius7VMSIrv89cDpetfY6njgOlxjwbck+khJKwrAgMBAAGjMjAwMB0GA1UdDgQWBBSTRXS2rZ2kd7OJEc11R0CWntHL+zAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQA3vZKvYe1atHGboo/i8g4r8apwktRjNDpSu4SuiCaAJQD2rsl9m2Kr0uUyOkWcVXHNakRHdr1Nx0RR6xhr9bQ2mqiWIhPazpnO+8Nu/jAhoOr3wLnKUEQQ4FXqKfr2/tO+k4+kAk9HzP0H7EVLynKEQSd6vVvvWRUs3aGTw7u0+EomfoV/ghQk5hY5B+96ZBtvqYDjC7zEkITehRaKSMJL7m322cgX0o68qODOAdDuulMMrNe/SgkgTh+vCpFgS3vLZ+tmmV+/OWY3upw1tJUEwIVqcInCNaP/IK4YH0Ptfy1ZEqMM0DGnsSvWDAYd9yzzbSOhY7GIvty7gsi6nb+z")!
    private let leafDER = Data(base64Encoded: "MIIDOzCCAiOgAwIBAgIUVKZAPvofc9QlN2wmRV+1zomFeX4wDQYJKoZIhvcNAQELBQAwJDEiMCAGA1UEAwwZR3JpZEZpeCBzeW50aGV0aWMgdGVzdCBDQTAeFw0yNjEwMjUxNDM4NDNaFw0yNzEwMjUxNDM4NDNaMBgxFjAUBgNVBAMMDW9wZW50YWtzZXJ2ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCxlsWQp+nLZMGmHF3ryprSoAw5hKNunLFFvRQbEo+9q2BSzoWYO0I+fywhIc01J5CyNTzNq9+REXB+xbcOyN+TK9FTY042XdtRi7uFXoA5Tb+u6bLAfeWAOpHuUr1ou1kFrmsx++NTQTw+likaPEza/ysU9xKLrx7oDWEeledE/xkVOXr7BZZ72Lrb8+UNjFpxVyqceXXAD3kIll468Pi7KSCRQiLofkAFNui38J9rOa+FW7RxWx0FDiB6kQmUQ+d8hRgAaBmEtx5eA5fEVyFI3ryOc5nh17K/jf99UaGqS7duUCDs6AkqDVRvr1/hlos7lTjT6bkhWflgeLWGP9mJAgMBAAGjcTBvMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUFBwMBMDoGA1UdEQQzMDGCDW9wZW50YWtzZXJ2ZXKCCHRhay50ZXN0hwTAAAIKhxAgAQ24AAAAAAAAAAAAAAABMA0GCSqGSIb3DQEBCwUAA4IBAQBE/2FvoTdfnYnn935dytyrzL/wH84V72WCb2YxXl5Bk1Z/ukbVuTDLBUrwESfYlBKVDwt0h8O2M5qXYf6qLsuPNuKMSR6wHuMNrQ/xqqN8qYNbgL580HL0cZmnDF0QTFysWfh4+x0KHJylFf36kZ3sZk0A1EhRTkKVNjljXhB586i5XMcFEfInJoHbHU5zyRPmKPLcxLIpRsjMbS+2Oco6aNBF2irCdtQFtdJDe2/OF8J/ipEctZcd5giAaKtDa/UTGgWUbISuHAvEp+XTTI1Ff4HOgHCP2QNIkrmDyNxGX0T+DEa9j+IHz3Mve0hyvxI8aoeNM9CPz4GKXAzw/REg")!
    private func evaluate(host: String, pin: String? = nil, anchored: Bool = true, date: Date? = nil) throws -> TAKServerTrust.Decision {
        let ca = try XCTUnwrap(SecCertificateCreateWithData(nil, caDER as CFData))
        let leaf = try XCTUnwrap(SecCertificateCreateWithData(nil, leafDER as CFData))
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates([leaf] as CFArray, SecPolicyCreateSSL(true, host as CFString), &trust), errSecSuccess)
        let value = try XCTUnwrap(trust)
        // Fixed date ensures fixtures do not silently expire in future test runs.
        SecTrustSetVerifyDate(value, (date ?? Date(timeIntervalSince1970: 1793145600)) as CFDate)
        return TAKServerTrust.evaluate(value, host: host, anchors: anchored ? [ca] : [], pinnedSHA256: pin)
    }
    func testHostnameMismatchBlocksUntilExactCertificatePinIsApproved() throws {
        let decision = try evaluate(host: "127.0.0.1")
        guard case let .nameMismatch(certificate) = decision else { return XCTFail("Expected name mismatch, got \(decision)") }
        XCTAssertEqual(certificate.subject, "opentakserver")
        XCTAssertEqual(certificate.names, ["opentakserver", "tak.test", "192.0.2.10", "2001:db8:0:0:0:0:0:1"])
        XCTAssertEqual(certificate.sha256.split(separator: ":").count, 32)
        XCTAssertEqual(try evaluate(host: "127.0.0.1", pin: certificate.sha256), .trusted)
        XCTAssertEqual(try evaluate(host: "opentakserver"), .trusted)
        XCTAssertEqual(try evaluate(host: "192.0.2.10"), .trusted)
    }
    func testChangedPinRefusedEvenWithMatchingHostname() throws {
        guard case .certificateChanged = try evaluate(host: "opentakserver", pin: "changed") else { return XCTFail("Changed certificate accepted") }
    }
    func testPinNeverBypassesUntrustedCAOrExpiry() throws {
        let leaf = try XCTUnwrap(SecCertificateCreateWithData(nil, leafDER as CFData))
        let pin = TAKServerTrust.describe(leaf).sha256
        guard case .refused = try evaluate(host: "127.0.0.1", pin: pin, anchored: false) else { return XCTFail("Pin bypassed untrusted CA") }
        guard case .refused = try evaluate(host: "127.0.0.1", pin: pin, date: Date(timeIntervalSince1970: 0)) else { return XCTFail("Pin bypassed validity") }
        guard case .refused = try evaluate(host: "127.0.0.1", pin: pin, date: Date(timeIntervalSince1970: 4102444800)) else { return XCTFail("Pin bypassed expiry") }
    }
    func testMalformedCertificateMetadataNeverParsesArbitraryStringsAsNames() {
        for bytes in [Data(), Data([0x30, 0x80]), Data([0x30, 0x84, 0xff, 0xff, 0xff, 0xff]), Data("opentakserver".utf8)] {
            XCTAssertTrue(TAKServerTrust.subjectAlternativeNames(bytes).isEmpty)
        }
    }
}
