import XCTest
import CoreImage
import GridFixCore
@testable import MGRSGPS

final class PositionQRTests: XCTestCase {
    func testGeneratedQRDecodesToExactAndroidGeoURI() throws {
        let request = try XCTUnwrap(PositionQRRequest(title: "Test waypoint",lat: 24.4539,lon: 54.3773,label: "A&B / waypoint"))
        let image = try XCTUnwrap(PositionQRCode.image(request.payload))
        let decoder = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode,context: CIContext(),options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let result = decoder.features(in: CIImage(cgImage: image)).first as? CIQRCodeFeature
        XCTAssertEqual(result?.messageString,request.payload)
        XCTAssertEqual(request.caption,MGRS.parts(lat: 24.4539,lon: 54.3773,digits: 10)?.full)
    }
    func testPositionPrecisionAndInvalidRequests() throws {
        let request = try XCTUnwrap(PositionQRRequest(title: "My position",lat: 24.4539,lon: 54.3773,label: "Position",digits: 4))
        XCTAssertEqual(request.caption,MGRS.parts(lat: 24.4539,lon: 54.3773,digits: 4)?.full)
        XCTAssertTrue(request.payload.contains("24.453900,54.377300"))
        XCTAssertNil(PositionQRRequest(title: "Invalid",lat: .nan,lon: 0,label: "Invalid"))
    }
}
