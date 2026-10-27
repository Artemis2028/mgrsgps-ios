import XCTest
@testable import GridFixCore

final class FieldOverlayGeometryTests: XCTestCase {
    private func document(_ points: [TrackPoint],folder: String = "Base") throws -> Backup.Document {
        let id = UUID().uuidString.lowercased()
        return Backup.Document(tracks: [.init(id: id,name: "Patrol",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: points.count,folder: folder)],trackFiles: [id: try TrackCodec.encode(points)])
    }
    func testTrackFitScansEveryRowWithConstantOutputAndDatelineBounds() throws {
        var bytes = Data("10 179.9 0 -32768\n70 -178.7 0 -32768\n".utf8)
        bytes.append(Data(String(repeating: "10 -179.9 0 -32768\n",count: 300_001).utf8))
        let fit = try FieldMapGeometry.trackFitPoints(bytes), bounds = try XCTUnwrap(FieldMapGeometry.bounds(fit))
        XCTAssertLessThanOrEqual(fit.count,6)
        XCTAssertEqual(bounds.south,10); XCTAssertEqual(bounds.north,70)
        XCTAssertEqual(bounds.west,179.9); XCTAssertEqual(bounds.east,181.3,accuracy: 1e-9)
    }
    func testTrackFitValidatesHiddenTailAndSupportsEmptyAndSinglePointLogs() throws {
        XCTAssertTrue(try FieldMapGeometry.trackFitPoints(Data()).isEmpty)
        let single = try FieldMapGeometry.trackFitPoints(Data("24 54 0 -32768".utf8))
        XCTAssertFalse(single.isEmpty); XCTAssertTrue(single.allSatisfy { $0 == GeoPoint(lat: 24,lon: 54) })
        XCTAssertThrowsError(try FieldMapGeometry.trackFitPoints(Data("24 54 0 -32768\n91 54 1 -32768".utf8)))
        XCTAssertThrowsError(try FieldMapGeometry.trackFitPoints(Data([0xff])))
    }
    func testAndroidDrawingStrideKeepsBothEndsAndExactUnsampledExtrema() throws {
        var points = (0..<6001).map { TrackPoint(lat: 10,lon: 10+Double($0)/10_000) }
        points[2] = .init(lat: 70,lon: 30)
        let doc = try document(points),before = doc.trackFiles
        let snapshot = try FieldMapGeometry.prepareOverlay(document: doc,folders: [])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.data) as? [String:Any])
        let features = try XCTUnwrap(json["features"] as? [[String:Any]])
        let geometry = try XCTUnwrap(features.first?["geometry"] as? [String:Any])
        let segments = try XCTUnwrap(geometry["coordinates"] as? [[[Double]]])
        let rendered = segments.flatMap { $0 }
        XCTAssertEqual(rendered.count,1501)
        XCTAssertEqual(rendered.first,[10,10]); XCTAssertEqual(rendered.last,[10.6,10])
        XCTAssertFalse(rendered.contains([30,70]))
        let bounds = try XCTUnwrap(FieldMapGeometry.bounds(snapshot.points))
        XCTAssertEqual(bounds.north,70); XCTAssertEqual(bounds.east,30)
        XCTAssertLessThanOrEqual(snapshot.points.count,6)
        XCTAssertEqual(snapshot.tracks,1); XCTAssertEqual(snapshot.routes,0)
        XCTAssertEqual(doc.trackFiles,before)
    }
    func testStrideUsesActualRowsDespiteWrongMetadataAndLegacySeparators() throws {
        let points = (0..<3001).map { TrackPoint(lat: 10,lon: 10+Double($0)/10_000) }
        var doc = try document(points)
        doc.tracks[0].pointCount = 2
        let source = try XCTUnwrap(String(data: doc.trackFiles[doc.tracks[0].id]!,encoding: .utf8))
        doc.trackFiles[doc.tracks[0].id] = Data(("  \u{2028}"+source.replacingOccurrences(of: "\n",with: "\r\n\u{0085}\u{2029}")+" ").utf8)
        let before = doc.trackFiles
        let snapshot = try FieldMapGeometry.prepareOverlay(document: doc,folders: [])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.data) as? [String:Any])
        let features = try XCTUnwrap(json["features"] as? [[String:Any]])
        let geometry = try XCTUnwrap(features.first?["geometry"] as? [String:Any])
        let rendered = try XCTUnwrap(geometry["coordinates"] as? [[[Double]]]).flatMap { $0 }
        XCTAssertEqual(rendered.count,1501); XCTAssertEqual(rendered.first,[10,10]); XCTAssertEqual(rendered.last,[10.3,10])
        XCTAssertEqual(snapshot.tracks,1); XCTAssertEqual(doc.trackFiles,before)
    }
    func testSingleRowStillValidatesAndEmptyLogsDoNotDrawOrAffectBounds() throws {
        var doc = try document([.init(lat: 10,lon: 20)])
        let single = try FieldMapGeometry.prepareOverlay(document: doc,folders: [])
        XCTAssertEqual(single.tracks,0); XCTAssertTrue(single.points.isEmpty)
        doc.trackFiles[doc.tracks[0].id] = Data("broken row".utf8)
        XCTAssertThrowsError(try FieldMapGeometry.prepareOverlay(document: doc,folders: []))
        doc.trackFiles[doc.tracks[0].id] = Data(" \r\n\u{2028}".utf8)
        let empty = try FieldMapGeometry.prepareOverlay(document: doc,folders: [])
        XCTAssertEqual(empty.tracks,0); XCTAssertTrue(empty.points.isEmpty)
        doc.trackFiles[doc.tracks[0].id] = Data([0xff,0x0a])
        XCTAssertThrowsError(try FieldMapGeometry.prepareOverlay(document: doc,folders: []))
    }

    func testWholeCircleAndDatelineBoundsMatchEveryOriginalCoordinate() throws {
        let points: [TrackPoint] = [.init(lat: 10,lon: 179),.init(lat: 12,lon: -179)]
        var doc = try document(points)
        doc.graphics = [.init(id: "ring",name: "Ring",type: "ring",points: [.init(lat: 10,lon: 179.8),.init(lat: 10,lon: -179.8)]),
                        .init(id: "route",name: "Route",type: "route",points: [.init(lat: 11,lon: 179.9),.init(lat: 12,lon: -179.8)])]
        let result = try FieldMapGeometry.prepareOverlay(document: doc,folders: [])
        let expected = try XCTUnwrap(FieldMapGeometry.bounds(doc.graphics.flatMap(\.mapExtentPoints)+points.map { .init(lat: $0.lat,lon: $0.lon) }))
        let actual = try XCTUnwrap(FieldMapGeometry.bounds(result.points))
        XCTAssertEqual(actual.south,expected.south); XCTAssertEqual(actual.north,expected.north)
        XCTAssertEqual(actual.west,expected.west); XCTAssertEqual(actual.east,expected.east)
        XCTAssertEqual(result.routes,1); XCTAssertEqual(result.tracks,1)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: result.data) as? [String:Any])
        let features = try XCTUnwrap(json["features"] as? [[String:Any]])
        let coordinates = try XCTUnwrap((features.first?["geometry"] as? [String:Any])?["coordinates"] as? [[[Double]]])
        XCTAssertEqual(coordinates.count,2)
    }
    func testHiddenItemsAndFoldersNeverEnterTrackGeometryCountsOrBounds() throws {
        var doc = try document([.init(lat: 30,lon: 40),.init(lat: 31,lon: 41)],folder: "RECON")
        doc.graphics = [.init(id: "hidden",name: "Hidden",type: "route",points: [.init(lat: -50,lon: 5),.init(lat: -51,lon: 6)],visible: false)]
        let result = try FieldMapGeometry.prepareOverlay(document: doc,folders: [.init(name: "Recon",visible: false)])
        XCTAssertEqual(result.tracks,0); XCTAssertEqual(result.routes,0); XCTAssertTrue(result.points.isEmpty)
        doc.tracks[0].visible = false
        XCTAssertTrue(try FieldMapGeometry.prepareOverlay(document: doc,folders: []).points.isEmpty)
    }
    func testCorruptVisibleLogFailsRatherThanDrawingAValidPrefix() throws {
        var doc = try document([.init(lat: 30,lon: 40),.init(lat: 31,lon: 41)])
        doc.trackFiles[doc.tracks[0].id]!.append(Data("broken row\n".utf8))
        XCTAssertThrowsError(try FieldMapGeometry.prepareOverlay(document: doc,folders: []))
        doc.tracks[0].visible = false
        XCTAssertEqual(try FieldMapGeometry.prepareOverlay(document: doc,folders: []).tracks,0)
    }
}
