import XCTest
@testable import GridFixCore

final class WaypointProjectionTests: XCTestCase {
    func testOsmdroidSphereKnownNorthEastAndDatelineDestinations() throws {
        let north = try WaypointProjection.project(base: .init(lat: 24,lon: 54),azimuth: "0",distance: "111319.49079327357",angleUnit: .degrees,northReference: 0) { _ in nil }
        XCTAssertEqual(north.point.lat,25,accuracy: 1e-10); XCTAssertEqual(north.point.lon,54,accuracy: 1e-10)
        let east = try WaypointProjection.project(base: .init(lat: 0,lon: 179.99),azimuth: "1600",distance: "2000",angleUnit: .mils,northReference: 0) { _ in nil }
        XCTAssertEqual(east.point.lon,-179.9920336943,accuracy: 1e-9); XCTAssertEqual(east.point.lat,0,accuracy: 1e-10)
    }
    func testReferenceConversionAtBaseAndFullTurnWrapping() throws {
        let base = GeoPoint(lat: 24,lon: 54)
        let reference = try WaypointProjection.project(base: base,azimuth: "0",distance: "1000",angleUnit: .degrees,northReference: 0) { _ in nil }
        let manual = try WaypointProjection.project(base: base,azimuth: "710",distance: "1000",angleUnit: .degrees,northReference: 1) { XCTAssertEqual($0,base); return 10 }
        XCTAssertEqual(manual,reference)
        let grid = try WaypointProjection.project(base: base,azimuth: String(-UTM.gridConvergence(lat: base.lat,lon: base.lon)),distance: "1000",angleUnit: .degrees,northReference: 2) { _ in XCTFail("Grid must not use magnetic model"); return nil }
        XCTAssertEqual(grid.point.lat,reference.point.lat,accuracy: 1e-10); XCTAssertEqual(grid.point.lon,reference.point.lon,accuracy: 1e-10)
    }
    func testInvalidInputsUnavailableReferenceAndTwoHundredKilometreLimit() throws {
        let base = GeoPoint(lat: 24,lon: 54)
        for distance in ["0","-1","200001","NaN","inf",""] {
            XCTAssertThrowsError(try WaypointProjection.project(base: base,azimuth: "0",distance: distance,angleUnit: .degrees,northReference: 0) { _ in nil })
        }
        for angle in ["NaN","inf","-1",""] { XCTAssertThrowsError(try WaypointProjection.project(base: base,azimuth: angle,distance: "1",angleUnit: .degrees,northReference: 0) { _ in nil }) }
        XCTAssertNoThrow(try WaypointProjection.project(base: base,azimuth: "0",distance: "200000",angleUnit: .degrees,northReference: 0) { _ in nil })
        XCTAssertThrowsError(try WaypointProjection.project(base: base,azimuth: "0",distance: "1",angleUnit: .degrees,northReference: 1) { _ in nil })
        XCTAssertThrowsError(try WaypointProjection.project(base: .init(lat: 85,lon: 0),azimuth: "0",distance: "1",angleUnit: .degrees,northReference: 2) { _ in nil })
        XCTAssertThrowsError(try WaypointProjection.project(base: .init(lat: .nan,lon: 0),azimuth: "0",distance: "1",angleUnit: .degrees,northReference: 0) { _ in nil })
    }
}
