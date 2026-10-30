import XCTest
@testable import GridFixCore

final class TAKEnrollmentTests: XCTestCase {
    func testATAKLinkDecodesUnicodeAndPreservesSecretWhitespaceWithoutAcceptingRedirects() throws {
        let link = try TAKEnrollment.link("tak://com.atakmap.app/enroll?host=127.0.0.1%3A8089&username=CAF%C3%89&token=%20secret%2Bvalue%20")
        XCTAssertEqual(link.target.host, "127.0.0.1"); XCTAssertEqual(link.target.streamPort, 8089)
        XCTAssertEqual(link.username, "CAFÉ"); XCTAssertEqual(link.token, " secret+value ")
        for text in ["https://com.atakmap.app/enroll?host=x&username=y&token=z",
                     "tak://evil/enroll?host=x&username=y&token=z",
                     "tak://com.atakmap.app/enroll?host=x&host=y&username=y&token=z",
                     "tak://com.atakmap.app/enroll?host=x%2Fsecret&username=y&token=z",
                     "tak://com.atakmap.app/enroll?host=user%40host&username=y&token=z",
                     "tak://com.atakmap.app/enroll?host=x&username=a%3Ab&token=z"] {
            XCTAssertThrowsError(try TAKEnrollment.link(text))
        }
        let ipv6 = try TAKEnrollment.link("tak://com.atakmap.app/enroll?host=%5B%3A%3A1%5D%3A8089&username=a&token=b")
        XCTAssertEqual(ipv6.target.host, "::1")
        XCTAssertEqual(ipv6.target.url(path: "/Marti/api/tls/config").absoluteString, "https://[::1]:8446/Marti/api/tls/config")
        let query = URLComponents(url: link.target.url(path: "/Marti/api/tls/signClient/v2", deviceUID: "MGRSGPS-CAFÉ&?"), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(query.queryItems?.first?.value, "MGRSGPS-CAFÉ&?")
    }
    func testConfigurationMatchesAndroidNamespaceAndSubjectOrderAndCannotSupplyCN() throws {
        let xml = "<ns2:certificateConfig xmlns='http://bbn.com/marti/xml/config' xmlns:ns2='com.bbn.marti.config'><nameEntries><nameEntry name='O' value='ZZ'/><nameEntry name='OU' value='OpenTAKServer'/><nameEntry name='CN' value='override'/><nameEntry name='OU' value=' '/></nameEntries></ns2:certificateConfig>"
        XCTAssertEqual(try TAKEnrollment.configuration(Data(xml.utf8)), [.init(name: "O", value: "ZZ"), .init(name: "OU", value: "OpenTAKServer")])
        for invalid in ["<!DOCTYPE x [<!ENTITY x 'boom'>]>" + xml, "<config>", String(repeating: " ", count: 65537), "<x>" + String(repeating: "<a>", count: 33) + String(repeating: "</a>", count: 33) + "</x>"] {
            XCTAssertThrowsError(try TAKEnrollment.configuration(Data(invalid.utf8)))
        }
        XCTAssertThrowsError(try TAKEnrollment.CSR.info(rsaPublicKeyPKCS1: Data([1]), subject: [.init(name: "CN", value: "override")], username: "user"))
    }
    func testReplyRequiresClientAndNumericCAFieldsAndToleratesPEMAndDuplicates() throws {
        let reply: [String: String] = ["signedCert": "AQID", "ca0": "BAUG", "ca1": "-----BEGIN CERTIFICATE-----\nBAUG\n-----END CERTIFICATE-----", "callsign": "ignored"]
        let result = try TAKEnrollment.certificates(JSONSerialization.data(withJSONObject: reply))
        XCTAssertEqual(result.client, Data([1, 2, 3])); XCTAssertEqual(result.authorities, [Data([4, 5, 6])])
        for invalid in [["signedCert": "AQID"], ["signedCert": "!", "ca0": "AQID"], ["ca0": "AQID"], ["signedCert": "AQID", "ca": "AQID"], ["signedCert": "AQID", "ca0": "!"]] {
            XCTAssertThrowsError(try TAKEnrollment.certificates(JSONSerialization.data(withJSONObject: invalid)))
        }
    }
    func testRequestBodyHasAndroidLineWrappingAndNoPEMHeader() throws {
        let bytes = Data((0..<200).map(UInt8.init)), body = String(decoding: TAKEnrollment.CSR.body(bytes), as: UTF8.self)
        let lines = body.split(separator: "\n")
        XCTAssertTrue(body.hasSuffix("\n")); XCTAssertFalse(body.contains("BEGIN"))
        XCTAssertTrue(lines.dropLast().allSatisfy { $0.count == 64 })
        XCTAssertEqual(Data(base64Encoded: lines.joined()), bytes)
        XCTAssertThrowsError(try TAKEnrollment.Target(host: "localhost/redirect"))
        XCTAssertThrowsError(try TAKEnrollment.Target(host: "localhost", enrollmentPort: 0))
    }
}
