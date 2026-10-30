import XCTest
@testable import GridFixCore

final class FieldFixTests: XCTestCase {
    private let a = GeoPoint(lat: 24.4539,lon: 54.3773),b = GeoPoint(lat: 24.4539,lon: 54.3873)
    private func solve(_ x: String,_ y: String,mode: FieldFix.Mode = .intersection,ref: Int = 0,unit: AngleUnit = .degrees,declination: (GeoPoint) -> Double? = { _ in nil }) throws -> FieldFix.Solution {
        try FieldFix.solve(mode: mode,point1: a,point2: b,azimuth1: x,azimuth2: y,angleUnit: unit,northReference: ref,declination: declination)
    }
    func testKnownFixAndAutomaticResectionBackAzimuthMatchAndroid() throws {
        let intersection = try solve("45","315"),resection = try solve("225","135",mode: .resection)
        XCTAssertEqual(intersection,resection)
        XCTAssertEqual(intersection.point.lat,24.4584766,accuracy: 1e-6)
        XCTAssertEqual(intersection.point.lon,54.3823,accuracy: 1e-6)
        XCTAssertEqual(intersection.range1,717.258,accuracy: 0.01)
        XCTAssertEqual(intersection.cutAngle,90); XCTAssertFalse(intersection.poorCut); XCTAssertNotNil(intersection.grid)
        XCTAssertEqual(try solve("4000","2400",mode: .resection,unit: .mils),intersection)
    }
    func testPerPointMagneticAndGridConversionDoNotUseTrueFallback() throws {
        let expected = try solve("45","315")
        XCTAssertEqual(try solve("35","295",ref: 1) { $0 == self.a ? 10 : 20 },expected)
        let gridA = 45-UTM.gridConvergence(lat: a.lat,lon: a.lon)
        let gridB = 315-UTM.gridConvergence(lat: b.lat,lon: b.lon)
        XCTAssertEqual(try solve(String(gridA),String(gridB),ref: 2),expected)
        XCTAssertThrowsError(try solve("45","315",ref: 1))
        XCTAssertThrowsError(try solve("45","315",ref: 1) { _ in .nan })
    }
    func testInvalidOrUnsafeGeometryHasNoFixAndPoorCutIsExplicit() throws {
        for pair in [("45","45"),("315","45"),("NaN","315"),("361","315"),("-1","315")] { XCTAssertThrowsError(try solve(pair.0,pair.1)) }
        XCTAssertTrue(try solve("80","280").poorCut)
        XCTAssertEqual(FieldFix.parseAzimuth(" 6400 ",unit: .mils),360)
        XCTAssertNil(FieldFix.parseAzimuth("6401",unit: .mils))
        XCTAssertNil(Geodesy.rayIntersection(lat1: .nan,lon1: 0,bearing1True: 1,lat2: 0,lon2: 1,bearing2True: 2))
        XCTAssertNil(Geodesy.rayIntersection(lat1: 85,lon1: 0,bearing1True: 45,lat2: 85,lon2: 1,bearing2True: 315))
        XCTAssertNil(Geodesy.rayIntersection(lat1: 0,lon1: 0,bearing1True: 45,lat2: 0,lon2: 3,bearing2True: 315))
        XCTAssertThrowsError(try FieldFix.solve(mode: .intersection,point1: a,point2: a,azimuth1: "45",azimuth2: "315",angleUnit: .degrees,northReference: 0) { _ in nil })
    }
}
