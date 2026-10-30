import XCTest
@testable import GridFixCore

final class TrackBacktrackTests: XCTestCase {
    func testAndroidBudgetRetainsBothEndsAndOrderAcrossEntireRecording() throws {
        let points = (0...200).map { GeoPoint(lat: 36+Double($0)*0.0001,lon: 45+($0%2 == 0 ? 0 : 0.001)) }.reversed().map { $0 }
        let result = try TrackBacktrack.simplify(points,tolerance: 2,maxPoints: 64)
        XCTAssertEqual(result.count,64); XCTAssertEqual(result.first,points.first); XCTAssertEqual(result.last,points.last)
        let indices = result.map { points.firstIndex(of: $0)! }
        XCTAssertTrue(zip(indices,indices.dropFirst()).allSatisfy { $0 < $1 })
    }
    func testLargestLateBendWinsSmallBudget() throws {
        let points = (0...100).map { i in GeoPoint(lat: i == 10 ? 0.001 : (i == 90 ? 0.01 : 0),lon: Double(i)*0.001) }
        XCTAssertEqual(try TrackBacktrack.simplify(points,tolerance: 1,maxPoints: 3),[points[0],points[90],points[100]])
    }
    func testCollinearTurnaroundAndDatelineDoglegSurvive() throws {
        let points = [GeoPoint(lat: 0,lon: 0),.init(lat: 0,lon: 0.02),.init(lat: 0,lon: 0.01)]
        XCTAssertEqual(try TrackBacktrack.simplify(points),points)
        let dateline = [GeoPoint(lat: 0,lon: 179.99),.init(lat: 0,lon: -179.99),.init(lat: 0.01,lon: -179.99)]
        XCTAssertEqual(try TrackBacktrack.simplify(dateline),dateline)
    }
    func testToleranceDropsNoiseAndTwoVertexBudgetSpansTheTrack() throws {
        let points = (0...100).map { GeoPoint(lat: $0%2 == 0 ? 0 : 0.00001,lon: Double($0)*0.001) }
        XCTAssertEqual(try TrackBacktrack.simplify(points,tolerance: 2),[points[0],points[100]])
        XCTAssertEqual(try TrackBacktrack.simplify(points,tolerance: 0,maxPoints: 2),[points[0],points[100]])
        XCTAssertEqual(try TrackBacktrack.simplify([]),[])
    }
    func testRouteReversesRetainsFolderAndDoesNotModifyOriginalTrack() throws {
        let points = [TrackPoint(lat: 1,lon: 2),.init(lat: 1.01,lon: 2),.init(lat: 1.01,lon: 2.01)]
        let (track,bytes) = try TrackCodec.imported(name: "Long patrol name for example",points: points,now: 1234,folder: "Recon")
        let route = try TrackBacktrack.route(track: track,points: points,now: 5678)
        XCTAssertEqual(route.name,"Back Long patrol nam"); XCTAssertEqual(route.folder,"Recon"); XCTAssertEqual(route.type,"route")
        XCTAssertEqual(route.points.first,.init(lat: points.last!.lat,lon: points.last!.lon)); XCTAssertEqual(route.points.last,.init(lat: points[0].lat,lon: points[0].lon))
        XCTAssertEqual(route.createdAt,5678); XCTAssertTrue(route.visible); XCTAssertEqual(try TrackCodec.decode(bytes),points)
    }
    func testInvalidParametersAndCoordinatesFailBeforePublication() {
        XCTAssertThrowsError(try TrackBacktrack.simplify([],maxPoints: 1))
        XCTAssertThrowsError(try TrackBacktrack.simplify([],tolerance: .nan))
        XCTAssertThrowsError(try TrackBacktrack.simplify([.init(lat: 91,lon: 0)]))
    }

    func testLocalLogBacktrackUsesActualRowsAndMatchesAndroidReverseGeometry() throws {
        let track = Backup.TrackMeta(id: UUID().uuidString.lowercased(),name: "Switchbacks",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: 2,folder: "Patrol")
        let data = Data("0 179.99 0 -32768\n0 -179.99 0 -32768\n0.01 -179.99 0 -32768\n".utf8)
        let route = try TrackBacktrack.route(track: track,data: data,now: 100)
        XCTAssertEqual(route.points,[.init(lat: 0.01,lon: -179.99),.init(lat: 0,lon: -179.99),.init(lat: 0,lon: 179.99)])
        XCTAssertEqual(route.folder,"Patrol"); XCTAssertEqual(route.createdAt,100)
        let turnaround = try TrackBacktrack.route(track: track,data: Data("0 0 0\n0 0.02 0\n0 0.01 0\n".utf8))
        XCTAssertEqual(turnaround.points,[.init(lat: 0,lon: 0.01),.init(lat: 0,lon: 0.02),.init(lat: 0,lon: 0)])
    }
    func testLocalBacktrackValidatesUnsampledRowsAndIgnoresMetadataCount() throws {
        let track = Backup.TrackMeta(id: UUID().uuidString.lowercased(),name: "Patrol",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: 99)
        for invalid in ["0 0 0\n91 0 0\n0 1 0\n","0 0 0\n0 0 -1\n0 1 0\n","0 0 0\n0 0 0 nan\n0 1 0\n"] {
            XCTAssertThrowsError(try TrackBacktrack.route(track: track,data: Data(invalid.utf8)))
        }
        XCTAssertThrowsError(try TrackBacktrack.route(track: track,data: Data("0 0 0\n".utf8)))
        let data = Data((String(repeating: "0 0 0 -32768\n",count: 250_001)+"0 1 0 -32768\n").utf8)
        let route = try TrackBacktrack.route(track: track,data: data)
        XCTAssertEqual(route.points,[.init(lat: 0,lon: 1),.init(lat: 0,lon: 0)])
    }
    func testCancellationStopsLocalDecodeAndSimplification() async throws {
        let track = Backup.TrackMeta(id: UUID().uuidString.lowercased(),name: "Patrol",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: 2)
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TrackBacktrack.route(track: track,data: Data("0 0 0\n0 1 0\n".utf8))
        }
        do { _ = try await work.value; XCTFail("Cancelled local decoding") } catch { XCTAssertTrue(error is CancellationError) }
        let simplify = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TrackBacktrack.simplify([.init(lat: 0,lon: 0),.init(lat: 0,lon: 1)])
        }
        do { _ = try await simplify.value; XCTFail("Cancelled simplification") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
