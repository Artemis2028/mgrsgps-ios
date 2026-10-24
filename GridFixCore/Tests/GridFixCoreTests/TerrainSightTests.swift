import XCTest
@testable import GridFixCore

final class TerrainSightTests: XCTestCase {
    func testAndroidTwentyKilometreVectorAndChordCurvatureSign() throws {
        let distances = (0...500).map { Float($0)*40 }
        let r = try XCTUnwrap(TerrainSight.lineOfSight(distances: distances,elevations: [Float](repeating: 0,count: 501),observerHeight: 2,targetHeight: 2))
        XCTAssertEqual(r.status,.masked); XCTAssertEqual(r.minClearance,-3.886038,accuracy: 0.00001)
        XCTAssertEqual(r.minClearanceDistance,10000); XCTAssertEqual(r.effectiveTerrain[250],5.886038,accuracy: 0.00001)
        XCTAssertEqual(r.sightLine[250],2); XCTAssertTrue((1..<250).contains(r.blockIndex))
    }
    func testAndroidNearHorizonAndEndpointVectors() throws {
        for (distances,gap) in [([Float(0),500,1000],Float(1.985285)),([Float(0),5000,10000],Float(0.5284905))] {
            let r = try XCTUnwrap(TerrainSight.lineOfSight(distances: distances,elevations: [0,0,0],observerHeight: 2,targetHeight: 2))
            XCTAssertEqual(r.status,.visible); XCTAssertEqual(r.minClearance,gap,accuracy: 0.00001)
        }
        let r = try XCTUnwrap(TerrainSight.lineOfSight(distances: [0,500,1000],elevations: [100,110,120],observerHeight: 2,targetHeight: 3))
        XCTAssertEqual(r.effectiveTerrain.first,100); XCTAssertEqual(r.effectiveTerrain.last,120)
        XCTAssertEqual(r.sightLine.first,102); XCTAssertEqual(r.sightLine.last,123)
    }
    func testAndroidCrestAndHeightRequiredToClearIt() throws {
        let distances: [Float] = [0,250,500,750,1000], elevations: [Float] = [120,120,140,120,120]
        let r = try XCTUnwrap(TerrainSight.lineOfSight(distances: distances,elevations: elevations,observerHeight: 2,targetHeight: 2))
        XCTAssertEqual(r.status,.masked); XCTAssertEqual(r.blockIndex,2); XCTAssertGreaterThan(r.clearObserverHeight,39)
        let raised = try XCTUnwrap(TerrainSight.lineOfSight(distances: distances,elevations: elevations,observerHeight: r.clearObserverHeight+0.01,targetHeight: 2))
        XCTAssertEqual(raised.status,.visible)
    }
    func testMissingTerrainCannotPromiseVisibilityClearanceOrHeight() throws {
        for (heights,status) in [([Float(0),.nan,0,0,0],TerrainSight.Status.unknown),([Float(0),.nan,20,0,0],.masked)] {
            let r = try XCTUnwrap(TerrainSight.lineOfSight(distances: [0,250,500,750,1000],elevations: heights,observerHeight: 2,targetHeight: 2))
            XCTAssertEqual(r.status,status); XCTAssertTrue(r.clearObserverHeight.isNaN); XCTAssertTrue(r.minClearance.isNaN); XCTAssertTrue(r.minClearanceDistance.isNaN)
        }
        XCTAssertNil(TerrainSight.lineOfSight(distances: [0,500,1000],elevations: [.nan,0,0],observerHeight: 2,targetHeight: 2))
        XCTAssertNil(TerrainSight.lineOfSight(distances: [0,500,1000],elevations: [0,0,.nan],observerHeight: 2,targetHeight: 2))
    }
    func testInvalidProfilesRejected() {
        for distances: [Float] in [[0,0],[1,500],[0,.nan],[0,500,400],[0,-1,500]] {
            XCTAssertNil(TerrainSight.lineOfSight(distances: distances,elevations: distances.map { _ in 0 },observerHeight: 2,targetHeight: 2))
        }
    }
    func testAndroidViewshedGapPropagationKnownCrestAndMergeRules() {
        var ray = TerrainSight.Ray(eye: 2)
        XCTAssertEqual(ray.sample(distance: 100,elevation: 0),.visible)
        XCTAssertEqual(ray.sample(distance: 200,elevation: nil),.unknown)
        XCTAssertEqual(ray.sample(distance: 300,elevation: 0),.unknown)
        XCTAssertEqual(ray.sample(distance: 400,elevation: 100),.unknown)
        var crest = TerrainSight.Ray(eye: 2)
        _ = crest.sample(distance: 100,elevation: nil)
        XCTAssertEqual(crest.sample(distance: 200,elevation: 20),.unknown)
        XCTAssertEqual(crest.sample(distance: 300,elevation: 0),.masked)
        XCTAssertEqual(TerrainSight.merge(.unknown,.visible),.unknown); XCTAssertEqual(TerrainSight.merge(.masked,.visible),.masked)
    }
    func testAndroidRadialCurvatureDropsTerrainAndMasksFarHorizon() {
        var ray = TerrainSight.Ray(eye: 2)
        for d in stride(from: 100,through: 19900,by: 100) { _ = ray.sample(distance: Double(d),elevation: 0) }
        XCTAssertEqual(ray.sample(distance: 20000,elevation: 0),.masked)
    }
    func testShortestArcAcrossDateLineAndAntipodalDeterminism() {
        let p = TerrainGeometry.position(from: .init(lat: 10,lon: 179.9),to: .init(lat: 10,lon: -179.9),fraction: 0.5)
        XCTAssertEqual(abs(p.lon),180,accuracy: 0.00001); XCTAssertEqual(p.lat,10,accuracy: 0.0001)
        let antipode = TerrainGeometry.position(from: .init(lat: 0,lon: 0),to: .init(lat: 0,lon: 180),fraction: 0.5)
        XCTAssertEqual(antipode.lat,90,accuracy: 0.00001)
    }
    func testProfileIncludesEveryLegEndAndRespectsMissingSamples() async throws {
        let value = try await TerrainAnalysis.profile(points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54),.init(lat: 24.01,lon: 54.01)],elevation: { $0.lat < 24.005 ? nil : 100 })
        let p = try XCTUnwrap(value)
        XCTAssertEqual(p.legEnds.count,2); XCTAssertEqual(p.legEnds.last,p.elevations.count-1)
        XCTAssertGreaterThan(p.missing,0); XCTAssertTrue(p.elevations[0].isNaN)
        XCTAssertGreaterThan(p.total,2000)
    }
    func testPartialTerrainCoverageAtLatitudeLimitRemainsUnknownInsteadOfRejectingWholeShade() async throws {
        let value = try await TerrainAnalysis.viewshed(observer: .init(lat: 84.999,lon: 0),radius: 4000,size: 32,rays: 128,elevation: { abs($0.lat) <= 85 ? 0 : nil })
        let shade = try XCTUnwrap(value)
        XCTAssertGreaterThan(shade.unknownCells,0); XCTAssertGreaterThan(shade.missing,0)
    }
    func testViewshedUnknownHatchingClassesAndCancellation() async throws {
        let observer = GeoPoint(lat: 24,lon: 179.999)
        let value = try await TerrainAnalysis.viewshed(observer: observer,radius: 1000,size: 32,rays: 128,elevation: { point in TerrainGeometry.distance(observer,point) < 100 ? 0 : nil })
        let r = try XCTUnwrap(value)
        XCTAssertGreaterThan(r.missing,0); XCTAssertGreaterThan(r.unknownCells,0); XCTAssertGreaterThan(r.east,180)
        XCTAssertEqual(r.classes[(r.size/2)*r.size+r.size/2],TerrainSight.Cell.visible.rawValue)
        let task = Task { try await TerrainAnalysis.viewshed(observer: observer,elevation: { _ in try? await Task.sleep(nanoseconds: 100_000); return 0 }) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled computation must not publish a shade") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
}
