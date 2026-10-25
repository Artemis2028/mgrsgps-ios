import XCTest
@testable import GridFixCore

final class RouteCardReportTests: XCTestCase {
    func testAndroidKnownRouteRowsReferencesUnitsAndShareSummary() throws {
        let points = [GeoPoint(lat: 1,lon: 179.99),GeoPoint(lat: 1,lon: -179.99)]
        let a = try RouteCard.report(name: "Patrol",points: points,configuration: .init(northReference: 1),generatedAt: Date(timeIntervalSince1970: 1700000000)) { _ in 10 }
        XCTAssertEqual(a.rows[0].azimuth,"080°"); XCTAssertEqual(a.rows[0].backAzimuth,"260°")
        XCTAssertEqual(a.rows[0].distance,"2.23 km"); XCTAssertEqual(a.dtg,"142213Z NOV 23")
        XCTAssertTrue(a.shareText.contains("START "+a.startGrid)); XCTAssertTrue(a.shareText.contains("TOTAL "+a.totalDistance)); XCTAssertTrue(a.shareText.contains("pace 65/100 m"))
        let b = try RouteCard.report(name: "Patrol",points: points,configuration: .init(northReference: 1,units: .imperial,angleUnit: .mils,pacePer100m: 70)) { _ in 20 }
        XCTAssertEqual(b.rows[0].azimuth,"1244 mils"); XCTAssertEqual(b.rows[0].backAzimuth,"4444 mils"); XCTAssertEqual(b.rows[0].distance,"1.38 mi")
        XCTAssertGreaterThan(b.totalPaces,a.totalPaces)
    }
    func testImportedRoutesBeyondTenThousandVerticesKeepEveryLeg() throws {
        let points = (0...10_000).map { i in GeoPoint(lat: 24+Double(i%2)*0.001,lon: 54) }
        let report = try RouteCard.report(name: "Imported route",points: points,configuration: .init()) { _ in nil }
        XCTAssertEqual(report.rows.count,10_000); XCTAssertEqual(report.rows.last?.index,10_000)
        XCTAssertEqual(report.rows.last?.destinationGrid,MGRS.parts(lat: 24,lon: 54,digits: 8)?.full)
        XCTAssertGreaterThan(report.totalMeters,1_000_000)
    }
    func testBackReferenceUsesDestinationAndMissingReferenceHasNoFallback() throws {
        let points = [GeoPoint(lat: 55,lon: 3),GeoPoint(lat: 65,lon: 12)]
        let a = try RouteCard.report(name: "Endpoints",points: points,configuration: .init(northReference: 1)) { $0.lat == 55 ? 2 : 7 }
        let reverse = Geodesy.navInfo(fromLat: 65,fromLon: 12,toLat: 55,toLon: 3).bearingTrue-7
        XCTAssertEqual(a.rows[0].backAzimuth,Format.angle(degrees: reverse,unit: .degrees))
        let b = try RouteCard.report(name: "Missing",points: points,configuration: .init(northReference: 1)) { _ in nil }
        XCTAssertEqual(b.rows[0].azimuth,"UNAVAILABLE"); XCTAssertEqual(b.rows[0].backAzimuth,"UNAVAILABLE"); XCTAssertFalse(b.notes.isEmpty)
        let invalid = try RouteCard.report(name: "Invalid model",points: points,configuration: .init(northReference: 1)) { _ in .nan }
        XCTAssertEqual(invalid.rows[0].azimuth,"UNAVAILABLE")
    }
    func testGridBoundaryPerEndpointAndEightDigitGridsIgnoreDisplayPrecision() throws {
        let report = try RouteCard.report(name: "Boundary",points: [.init(lat: 78,lon: 8.99),.init(lat: 78,lon: 9.01)],configuration: .init(northReference: 2)) { _ in XCTFail("Grid bearings must not call magnetic model"); return nil }
        XCTAssertEqual(report.rows[0].azimuth,"084°"); XCTAssertEqual(report.rows[0].backAzimuth,"276°")
        XCTAssertEqual(report.rows[0].destinationGrid,MGRS.parts(lat: 78,lon: 9.01,digits: 8)?.full)
        let polar = try RouteCard.report(name: "Polar",points: [.init(lat: 85,lon: 0),.init(lat: 85,lon: 1)],configuration: .init(northReference: 2)) { _ in nil }
        XCTAssertEqual(polar.startGrid,"UNAVAILABLE"); XCTAssertEqual(polar.rows[0].azimuth,"UNAVAILABLE"); XCTAssertEqual(polar.notes.count,2)
    }
    func testDatelineSketchKeepsShortLegDirectionAndOrdinaryShape() throws {
        let points = [GeoPoint(lat: 0,lon: 179.99),GeoPoint(lat: 0.01,lon: -179.99),GeoPoint(lat: 0.02,lon: 179.98)]
        let sketch = RouteSketch.coordinates(points)
        XCTAssertGreaterThan(sketch[1].x,sketch[0].x); XCTAssertLessThan(sketch[2].x,sketch[0].x)
        XCTAssertEqual(sketch[2].y,0.02); XCTAssertLessThan(sketch.map(\.x).max()!-sketch.map(\.x).min()!,0.04)
        let west = RouteSketch.coordinates(Array(points.prefix(2)).reversed())
        XCTAssertLessThan(west[1].x,west[0].x)
        XCTAssertTrue(RouteSketch.coordinates([]).isEmpty)
    }
    func testScaleBarLabelsAndDegenerateGeometryStayInsideSketch() throws {
        let ordinary = try RouteSketch.layout([.init(lat: 0,lon: 0),.init(lat: 0,lon: 0.06)],width: 515,height: 280)
        XCTAssertEqual(ordinary.scaleBar.meters,2500); XCTAssertEqual(ordinary.scaleBar.label,"2.5 km")
        XCTAssertEqual(ordinary.points[0].y,ordinary.points[1].y); XCTAssertEqual(ordinary.points[0].y,146)
        let same = try RouteSketch.layout([.init(lat: 24,lon: 54),.init(lat: 24,lon: 54)],width: 515,height: 280)
        XCTAssertEqual(same.points[0],same.points[1]); XCTAssertEqual(same.points[0].x,257.5)
        XCTAssertTrue(same.scaleBar.lengthPoints.isFinite); XCTAssertGreaterThan(same.scaleBar.lengthPoints,20); XCTAssertLessThan(same.scaleBar.lengthPoints,491)
        XCTAssertThrowsError(try RouteSketch.layout([],width: 515,height: 280))
        XCTAssertThrowsError(try RouteSketch.layout([.init(lat: 0,lon: 0)],width: .greatestFiniteMagnitude,height: .greatestFiniteMagnitude))
    }
    func testInvalidInputAndCancelledBuildDoNotReturnReports() async throws {
        XCTAssertThrowsError(try RouteCard.report(name: "Bad",points: [.init(lat: .nan,lon: 0),.init(lat: 0,lon: 0)],configuration: .init()) { _ in nil })
        XCTAssertThrowsError(try RouteCard.report(name: "Bad pace",points: [.init(lat: 0,lon: 0),.init(lat: 0,lon: 0)],configuration: .init(pacePer100m: 0)) { _ in nil })
        let task = Task { try Task.checkCancellation(); return try RouteCard.report(name: "Cancelled",points: [.init(lat: 0,lon: 0),.init(lat: 1,lon: 1)],configuration: .init()) { _ in nil } }
        task.cancel(); do { _ = try await task.value; XCTFail("Cancelled report") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
