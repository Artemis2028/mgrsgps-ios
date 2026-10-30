import XCTest
@testable import GridFixCore

final class TAKConnectionPackageTests:XCTestCase {
    private func archive(_ pref:String,files:[ZipArchive.Entry]=[])->Data {
        ZipArchive.write(entries:[.init(name:"settings/server.pref",data:Data(pref.utf8))]+files)
    }
    private func pref(_ entries:[String:String])->String {
        "<preferences><preference name='cot_streams'>"+entries.sorted{$0.key<$1.key}.map{"<entry key='\($0.key)'>\($0.value)</entry>"}.joined()+"</preference></preferences>"
    }
    func testAndroidStyleAbsoluteCertificatePathsAndSeparatePreferenceBlocks() throws {
        let data=archive(pref(["connectString0":"localhost:8089:ssl","description0":"Local TAK","caLocation0":"/sdcard/atak/certs/ca.p12","certificateLocation0":"/sdcard/atak/certs/client.p12","caPassword0":"ca-test","clientPassword0":"client-test"]),files:[.init(name:"certs/CA.P12",data:Data([1,2])),.init(name:"certs/client.p12",data:Data([3,4]))])
        let result=try TAKConnectionPackage.read(data)
        XCTAssertEqual(result.host,"localhost");XCTAssertEqual(result.port,8089);XCTAssertTrue(result.usesTLS)
        XCTAssertFalse(result.needsEnrollment);XCTAssertEqual(result.caPKCS12,Data([1,2]));XCTAssertEqual(result.clientPKCS12,Data([3,4]))
        XCTAssertEqual(result.description,"Local TAK")
    }
    func testCertificatePasswordsKeepMeaningfulWhitespaceAndUnicode() throws {
        let data=archive(pref(["connectString0":"localhost:8089:ssl","caPassword":"  fixtüré🔭  ","clientPassword":"  client phrase  "]))
        let result=try TAKConnectionPackage.read(data)
        XCTAssertEqual(result.caPassword,"  fixtüré🔭  ")
        XCTAssertEqual(result.clientPassword,"  client phrase  ")
    }
    func testPlainTCPAndUnsupportedEnrollmentAreExplicit() throws {
        let tcp=try TAKConnectionPackage.read(archive(pref(["connectString0":"localhost:8088:tcp"])))
        XCTAssertFalse(tcp.usesTLS);XCTAssertFalse(tcp.needsEnrollment)
        let tls=try TAKConnectionPackage.read(archive(pref(["connectString0":"[::1]:8089:tls"])))
        XCTAssertEqual(tls.host,"::1");XCTAssertTrue(tls.needsEnrollment)
    }
    func testMissingAmbiguousCertificatesMalformedXMLAndLimitsReject() throws {
        XCTAssertThrowsError(try TAKConnectionPackage.read(archive(pref(["connectString0":"localhost:8089:ssl","caLocation":"ca.p12"]))))
        XCTAssertThrowsError(try TAKConnectionPackage.read(archive(pref(["connectString0":"localhost:8089:ssl","caLocation":"ca.p12"]),files:[.init(name:"a/ca.p12",data:Data([1])),.init(name:"b/ca.p12",data:Data([2]))])))
        for address in ["localhost:0:ssl","localhost:8089:udp","bad host:8089:ssl"] {XCTAssertThrowsError(try TAKConnectionPackage.read(archive(pref(["connectString0":address]))))}
        XCTAssertThrowsError(try TAKConnectionPackage.read(archive("<!DOCTYPE x [<!ENTITY a 'b'>]>"+pref(["connectString0":"localhost:8089:ssl"]))))
        XCTAssertThrowsError(try TAKConnectionPackage.read(archive(pref(["connectString0":"localhost:8089:ssl"]),files:[.init(name:"large.p12",data:Data(repeating:0,count:2*1024*1024+1))])))
    }
}
