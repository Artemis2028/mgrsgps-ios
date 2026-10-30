import XCTest
@testable import GridFixCore

final class MapMeasurementTests: XCTestCase {
    func testAndroidDatelineAreaVectorsAndReversedWinding() throws {
        let points = [GeoPoint(lat: 0.001,lon: 179.999),.init(lat: 0.001,lon: -179.999),.init(lat: -0.001,lon: -179.999),.init(lat: -0.001,lon: 179.999)]
        for polygon in [points,Array(points.reversed()),Array(points.dropFirst())+[points[0]],points+[points[0]]] {
            let result = try XCTUnwrap(MapMeasurement.polygon(polygon))
            XCTAssertEqual(result.perimeter,888.445831,accuracy: 0.01)
            XCTAssertEqual(result.area,49332.943265,accuracy: 0.1)
        }
        let ordinary = try XCTUnwrap(MapMeasurement.polygon(points.map { .init(lat: $0.lat,lon: TerrainGeometry.wrap($0.lon-174)) }))
        XCTAssertEqual(ordinary.area,49332.943265,accuracy: 0.1)
    }
    func testSmallPolygonKeepsPrecisionFarFromEquatorAndAcrossZones() throws {
        let a = UTM.inverse(easting: 499_999,northing: 8_000_000,zone: 31,north: true)
        let b = UTM.inverse(easting: 500_009,northing: 8_000_000,zone: 31,north: true)
        let c = UTM.inverse(easting: 500_009,northing: 8_000_010,zone: 31,north: true)
        let d = UTM.inverse(easting: 499_999,northing: 8_000_010,zone: 31,north: true)
        let result = try XCTUnwrap(MapMeasurement.polygon([a,b,c,d].map { .init(lat: $0.lat,lon: $0.lon) }))
        XCTAssertEqual(result.area,100,accuracy: 0.001); XCTAssertEqual(result.perimeter,40,accuracy: 0.001)
    }
    func testForcedProjectionAcrossDatelineStaysLocal() {
        for (zone,longitude) in [(60,-179.99),(1,179.99)] {
            let p = UTM.forZone(lat: 1,lon: longitude,zone: zone,north: true)
            XCTAssertTrue((100_000...900_000).contains(p.easting))
            let back = UTM.inverse(easting: p.easting,northing: p.northing,zone: zone,north: true)
            XCTAssertEqual(back.lat,1,accuracy: 0.000001)
            XCTAssertEqual(TerrainGeometry.wrap(back.lon),longitude,accuracy: 0.000001)
        }
    }
    func testAndroidPolarExtrapolationIsExplicitAndAreaUnitsMatch() throws {
        XCTAssertNil(MapMeasurement.polygon([]))
        let polar = try XCTUnwrap(MapMeasurement.polygon([.init(lat: 85,lon: 0),.init(lat: 85,lon: 0.01),.init(lat: 85.01,lon: 0.01)]))
        XCTAssertTrue(polar.extrapolated); XCTAssertGreaterThan(polar.area,0)
        XCTAssertNil(MapMeasurement.polygon([.init(lat: 90,lon: 0),.init(lat: 90,lon: 1),.init(lat: 89.99,lon: 1)]))
        XCTAssertEqual(MapMeasurement.areaLabel(9999),"9999 m²")
        XCTAssertEqual(MapMeasurement.areaLabel(10_000),"1.0 ha")
        XCTAssertEqual(MapMeasurement.areaLabel(1_000_000),"1.00 km²")
    }
    func testRulerReferenceCorrectionsAndReciprocalMatchAndroid() {
        let a = GeoPoint(lat: 0,lon: 0), b = GeoPoint(lat: 0,lon: 0.01)
        let result = MapMeasurement.ruler(from: a,to: b,northReference: 1,declination: 10)
        XCTAssertEqual(result.distance,1113.1949,accuracy: 0.01)
        XCTAssertEqual(result.azimuth!,80,accuracy: 0.001); XCTAssertEqual(result.backAzimuth!,260,accuracy: 0.001)
        XCTAssertNil(MapMeasurement.ruler(from: a,to: b,northReference: 1,declination: nil).azimuth)
        let c = GeoPoint(lat: 60,lon: 30)
        let grid = MapMeasurement.ruler(from: .init(lat: 60,lon: 0),to: c,northReference: 2,declination: nil)
        let trueValue = MapMeasurement.ruler(from: .init(lat: 60,lon: 0),to: c,northReference: 0,declination: nil)
        XCTAssertEqual(grid.azimuth!,trueValue.azimuth!-UTM.gridConvergence(lat: c.lat,lon: c.lon),accuracy: 0.001)
        XCTAssertEqual(grid.backAzimuth!,(grid.azimuth!+180).truncatingRemainder(dividingBy: 360),accuracy: 0.001)
    }
}
