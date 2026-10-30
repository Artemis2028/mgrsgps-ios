import XCTest
@testable import GridFixCore

final class WatchMapSnapshotTests: XCTestCase {
    func testSimplifiedRouteKeepsExactOrdinalsAtRepeatedCoordinatesAndLegacyDoesNotRenumber() throws {
        let route = Backup.Graphic(id:"r",name:"Repeated",type:"route",points:Array(repeating:.init(lat:24,lon:54),count:500))
        let scene = WatchMapSnapshot.build(waypoints:[],folders:[],document:.init(graphics:[route]))
        let feature = try XCTUnwrap(scene.features.first)
        XCTAssertEqual(feature.routeVertexIndices,[0,499]); XCTAssertEqual(feature.routeLegLabels,["1–499"])
        XCTAssertEqual(WatchMapSnapshot.decode(try XCTUnwrap(scene.encoded())),scene)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(scene.encoded())) as? [String:Any])
        var features = try XCTUnwrap(legacy["features"] as? [[String:Any]])
        features[0].removeValue(forKey:"routeVertexIndices"); legacy["features"] = features
        let decoded = try XCTUnwrap(WatchMapSnapshot.decode(JSONSerialization.data(withJSONObject:legacy)))
        XCTAssertNil(decoded.features.first?.routeLegLabels)
        var bad = scene
        for indices in [[0,498],[1,499],[0,499,500],[0,-1]] {
            bad.features[0].routeVertexIndices = indices; XCTAssertNil(bad.encoded())
        }
        bad.features[0].type = "phase_line"; bad.features[0].routeVertexIndices = [0,499]
        XCTAssertNil(bad.encoded())
    }
    func testRetainedRouteIndicesMatchEverySampledCoordinateAndCoverAllOriginalLegs() throws {
        let points = (0..<500).map { GeoPoint(lat:$0 == 251 ? 24.5 : 24,lon:54+Double($0)*0.0001) }
        let indices = try TrackBacktrack.retainedIndices(points,tolerance:0,maxPoints:160)
        XCTAssertEqual(try TrackBacktrack.simplify(points,tolerance:0,maxPoints:160),indices.map { points[$0] })
        XCTAssertEqual(indices.first,0); XCTAssertEqual(indices.last,499); XCTAssertTrue(indices.contains(251))
        let route = Backup.Graphic(id:"r",name:"Bend",type:"route",points:points.map { .init(lat:$0.lat,lon:$0.lon) })
        let feature = try XCTUnwrap(WatchMapSnapshot.build(waypoints:[],folders:[],document:.init(graphics:[route])).features.first)
        XCTAssertEqual(feature.routeVertexIndices,indices)
        XCTAssertEqual(feature.routeLegLabels?.count,feature.points.count-1)
    }
    func testVisibilityMetadataAndCompleteEmptyReplacement() throws {
        var shown = Waypoint(id: "unit", name: "Recon", lat: 24, lon: 54, symbol: "nato_f_recon", affiliation: "friendly", echelon: "plt")
        shown.rotation = 45
        var hidden = shown; hidden.id = "hidden"; hidden.visible = false
        var folderHidden = shown; folderHidden.id = "secret"; folderHidden.folder = "reCON"
        let folders = [FolderInfo(name: "Recon", visible: false)]
        let graphic = Backup.Graphic(id: "route", name: "Route", type: "route", points: [.init(lat: 24, lon: 54), .init(lat: 24.1, lon: 54.1)])
        let concealed = Backup.Graphic(id: "hidden-route", name: "Hidden", type: "route", points: graphic.points, folder: "RECON")
        let snapshot = WatchMapSnapshot.build(waypoints: [shown, hidden, folderHidden], folders: folders, document: .init(graphics: [graphic, concealed]))
        XCTAssertEqual(snapshot.waypoints.map(\.id), ["unit"])
        XCTAssertEqual(snapshot.waypoints.first?.symbol, "nato_f_recon")
        XCTAssertEqual(snapshot.waypoints.first?.rotation, 45)
        XCTAssertEqual(snapshot.features.map(\.id), ["route"])
        let data = try XCTUnwrap(snapshot.encoded())
        XCTAssertEqual(WatchMapSnapshot.decode(data), snapshot)
        let clear = WatchMapSnapshot.build(waypoints: [], folders: [], document: .init())
        XCTAssertTrue(try XCTUnwrap(WatchMapSnapshot.decode(XCTUnwrap(clear.encoded()))).waypoints.isEmpty)
        XCTAssertTrue(clear.features.isEmpty)
    }

    func testLineBudgetPreservesEndpointsAndSharpBendWhileAreasAreNeverDecimated() throws {
        let points = (0..<500).map { GeoPoint(lat: $0 == 251 ? 24.5 : 24, lon: 54 + Double($0) * 0.0001) }
        let route = Backup.Graphic(id: "r", name: "Bend", type: "route", points: points.map { .init(lat: $0.lat, lon: $0.lon) })
        let largeArea = Backup.Graphic(id: "area", name: "Area", type: "area", points: route.points)
        let snapshot = WatchMapSnapshot.build(waypoints: [], folders: [], document: .init(graphics: [route, largeArea]))
        let line = try XCTUnwrap(snapshot.features.first)
        XCTAssertLessThanOrEqual(line.points.count, WatchMapSnapshot.maxLinePoints)
        XCTAssertEqual(line.points.first, points.first)
        XCTAssertEqual(line.points.last, points.last)
        XCTAssertTrue(line.points.contains(points[251]))
        XCTAssertTrue(line.simplified)
        XCTAssertEqual(snapshot.simplifiedItems, 1)
        XCTAssertEqual(snapshot.omittedItems, 1)
    }

    func testTracksDisplayedBoundaryMalformedAndPolarItems() throws {
        let id = UUID().uuidString.lowercased(), badID = UUID().uuidString.lowercased()
        let points = [TrackPoint(lat: 24, lon: 54), TrackPoint(lat: 24.01, lon: 54.01)]
        let tracks = [id, badID].map { Backup.TrackMeta(id: $0, name: "Log", startedAt: 0, endedAt: 0, distanceM: 10, pointCount: 2) }
        let boundary = BoundaryArea(id: "shown", name: "Displayed fence", vertices: [.init(lat: 24, lon: 54), .init(lat: 24.01, lon: 54), .init(lat: 24, lon: 54.01)])
        let document = Backup.Document(tracks: tracks, trackFiles: [id: try TrackCodec.encode(points), badID: Data("bad".utf8)])
        let map = WatchMapSnapshot.build(waypoints: [.init(name: "Polar", lat: 86, lon: 0)], folders: [], document: document, boundary: boundary)
        XCTAssertEqual(Set(map.features.map(\.kind)), ["track", "boundary"])
        XCTAssertEqual(map.features.first { $0.kind == "boundary" }?.points, boundary.vertices)
        XCTAssertEqual(map.omittedItems, 2)
    }

    func testEncodedUnicodeBudgetAndRejectMalformedWireSnapshot() throws {
        let waypoints = (0..<500).map { Waypoint(id: String($0), name: String(repeating: "🧭", count: 80), lat: 24, lon: 54) }
        var map = WatchMapSnapshot.build(waypoints: waypoints, folders: [], document: .init())
        let bytes = try XCTUnwrap(map.encoded())
        XCTAssertLessThanOrEqual(bytes.count, WatchMapSnapshot.maxEncodedBytes)
        XCTAssertGreaterThan(map.omittedItems, 0)
        map.version = 99
        XCTAssertNil(WatchMapSnapshot.decode(try JSONEncoder().encode(map)))
        XCTAssertNil(WatchMapSnapshot.decode(Data(repeating: 32, count: WatchMapSnapshot.maxEncodedBytes + 1)))
    }
}

extension WatchMapSnapshotTests {
    func testDatelineLinesSplitAndAreasAreExplicitlyOmitted() {
        let points = [Backup.GraphicPoint(lat: 10, lon: 179.9), .init(lat: 10, lon: -179.9), .init(lat: 10.1, lon: -179.9)]
        let document = Backup.Document(graphics: [.init(id: "line", name: "Date line", type: "route", points: points), .init(id: "area", name: "Crossing", type: "area", points: points)])
        let map = WatchMapSnapshot.build(waypoints: [], folders: [], document: document)
        XCTAssertEqual(map.features.count, 1)
        XCTAssertEqual(map.omittedItems, 1)
        XCTAssertEqual(FieldMapGeometry.lineSegments(map.features[0].points).count, 2)
    }

    func testSectorUsesMercatorClockwiseArcAndRejectsPolarInputs() throws {
        let center = GeoPoint(lat: 24, lon: 54)
        let outline = try XCTUnwrap(WatchMapGeometry.sectorOutline([center, .init(lat: 24.01, lon: 54), .init(lat: 24, lon: 54.01)]))
        XCTAssertEqual(outline.first, center)
        XCTAssertTrue(outline.allSatisfy(WatchMapSnapshot.validCoordinate))
        XCTAssertTrue(outline.dropFirst().allSatisfy { $0.lat >= center.lat - 1e-8 && $0.lon >= center.lon - 1e-8 })
        XCTAssertNil(WatchMapGeometry.sectorOutline([.init(lat: 89, lon: 0), .init(lat: 89, lon: 1), .init(lat: 89, lon: 2)]))
    }
}

extension WatchMapSnapshotTests {
    func testRevisionPreventsResurrectionAndAcceptsClockRollback() {
        let cached = WatchMapSnapshot(updatedAt: Date(timeIntervalSince1970: 200), sourceID: "phone", revision: 8)
        let older = WatchMapSnapshot(updatedAt: Date(timeIntervalSince1970: 300), sourceID: "phone", revision: 7)
        let newerWithOlderClock = WatchMapSnapshot(updatedAt: Date(timeIntervalSince1970: 100), sourceID: "phone", revision: 9)
        XCTAssertFalse(older.shouldApply(over: cached))
        XCTAssertTrue(newerWithOlderClock.shouldApply(over: cached))
        XCTAssertTrue(cached.shouldApply(over: cached))
        var conflicting = cached; conflicting.omittedItems = 1
        XCTAssertFalse(conflicting.shouldApply(over: cached))
        XCTAssertTrue(WatchMapSnapshot(sourceID: "new paired phone", revision: 1).shouldApply(over: cached))
    }
}
