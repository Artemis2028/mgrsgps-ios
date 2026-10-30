import XCTest
@testable import GridFixCore

final class PositionShareTests: XCTestCase {
    func testAndroidCoordinateAndUriEncodingContract() {
        XCTAssertEqual(PositionShare.geoURI(lat: 24.4539,lon: 54.3773,label: "WP 1 / A&B + 雪"),
                       "geo:24.453900,54.377300?q=24.453900,54.377300(WP%201%20%2F%20A%26B%20%2B%20%E9%9B%AA)")
        XCTAssertEqual(PositionShare.geoURI(lat: -0.0,lon: -180,label: " \n"),"geo:-0.000000,-180.000000?q=-0.000000,-180.000000(Waypoint)")
        XCTAssertTrue(PositionShare.geoURI(lat: 90,lon: 180,label: "A_-.!~'()*")!.hasSuffix("(A_-.!~'()*)"))
    }
    func testInvalidCoordinatesCannotBecomeSharePayloads() {
        for p in [(Double.nan,0.0),(0,Double.infinity),(90.01,0),(0,-180.01)] {
            XCTAssertNil(PositionShare.geoURI(lat: p.0,lon: p.1,label: "invalid"))
        }
    }
}
