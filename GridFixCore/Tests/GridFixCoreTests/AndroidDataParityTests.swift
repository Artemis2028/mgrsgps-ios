import XCTest
@testable import GridFixCore

final class AndroidDataParityTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func fixture() throws -> Backup.Document {
        let file = try XCTUnwrap(Bundle.module.url(forResource: "android-backup-contract", withExtension: "zip"))
        let bytes = try Data(contentsOf: file)
        XCTAssertNotEqual(bytes[6] & 8, 0, "Fixture must exercise Android's streaming data descriptors")
        return try Backup.importZip(bytes)
    }

    func testAndroidStreamingZipRestoresEverySectionAndRecomputesTrackStats() throws {
        let doc = try fixture()
        XCTAssertEqual(doc.waypoints.first?.sourceRouteId, "contract-route")
        XCTAssertEqual(doc.waypoints.first?.sourceRoutePointIndex, 1)
        XCTAssertEqual(doc.waypoints.first?.metadata.milgpsSymbolCode, 2110)
        XCTAssertEqual(doc.graphics.first?.points.count, 2)
        XCTAssertEqual(doc.tracks.first?.pointCount, 2)
        XCTAssertLessThan(try XCTUnwrap(doc.tracks.first?.distanceM), 200)
        XCTAssertEqual(doc.settings.pacePer100m, 70)
        XCTAssertNil(doc.settings.declinationOverride)
        XCTAssertEqual(doc.courseHistory.first?.splits, [500, 700])
        let points = try TrackCodec.decode(try XCTUnwrap(doc.trackFiles.values.first))
        XCTAssertEqual(points.first?.altitudeMeters, 12.5)
        XCTAssertNil(points.last?.altitudeMeters)
        XCTAssertEqual(try Backup.importZip(Backup.exportZip(doc)), doc)
    }

    func testFieldRestoreIsPersistentIdempotentAndKeepsExistingRecords() throws {
        let dir = try directory(), incoming = try fixture()
        let store = FieldDataStore(directory: dir)
        let first = try store.restore(incoming)
        XCTAssertEqual(first.graphics, 1); XCTAssertEqual(first.tracks, 1); XCTAssertEqual(first.course, 1)
        var edited = try XCTUnwrap(store.document.graphics.first)
        edited.name = "Device's own name"
        try store.saveGraphic(edited)
        XCTAssertEqual(try store.restore(incoming).graphics, 0)
        let reloaded = FieldDataStore(directory: dir)
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.document.graphics.first?.name, "Device's own name")
        XCTAssertEqual(reloaded.document.tracks.count, 1)
        XCTAssertEqual(reloaded.document.courseHistory.count, 1)
    }

    func testFailedPublicationDoesNotChangeFieldDataOrPublishPartialRecords() throws {
        let dir = try directory(), incoming = try fixture()
        let store = FieldDataStore(directory: dir)
        let blocked = dir.appendingPathComponent("field-data-v2.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.restore(incoming))
        XCTAssertTrue(store.document.graphics.isEmpty)
        XCTAssertTrue(store.document.tracks.isEmpty)
        try FileManager.default.removeItem(at: blocked)
        XCTAssertEqual(try store.restore(incoming).tracks, 1)
    }

    func testCorruptExistingArchiveIsKeptAndCannotBeSilentlyOverwritten() throws {
        let dir = try directory(), file = dir.appendingPathComponent("field-data-v1.zip")
        let bytes = Data("damaged data".utf8)
        try bytes.write(to: file)
        let store = FieldDataStore(directory: dir)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.restore(fixture()))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testInvalidArchivesAreRejectedBeforeMutation() throws {
        let doc = try fixture()
        var missing = doc; missing.trackFiles = [:]
        XCTAssertThrowsError(try Backup.exportZip(missing))
        var duplicate = doc; duplicate.waypoints += doc.waypoints
        XCTAssertThrowsError(try Backup.exportZip(duplicate))
        let traversal = ZipArchive.write(entries: [.init(name: "../gridfix-backup.json", data: try Backup.encodeManifest(doc))])
        XCTAssertThrowsError(try Backup.importZip(traversal))
        let repeated = ZipArchive.write(entries: [.init(name: "gridfix-backup.json", data: Data()), .init(name: "gridfix-backup.json", data: Data())])
        XCTAssertThrowsError(try ZipArchive.read(repeated))
        var corrupt = try Backup.exportZip(Backup.Document())
        corrupt[60] ^= 1
        XCTAssertThrowsError(try Backup.importZip(corrupt))
        XCTAssertThrowsError(try Backup.decodeManifest(Data("{\"app\":\"Other\",\"version\":1}".utf8)))
        XCTAssertThrowsError(try Backup.decodeManifest(Data("{\"app\":\"GridFix\",\"version\":1,\"tracks\":[42]}".utf8)))
        for section in ["\"folders\":[{}]", "\"courseHistory\":[{\"name\":\"Run\"}]",
                        "\"courseHistory\":[{\"name\":\"Run\",\"points\":1,\"started\":1,\"total\":1,\"splits\":[\"bad\"]}]",
                        "\"settings\":{\"declinationOverride\":\"bad\"}"] {
            XCTAssertThrowsError(try Backup.decodeManifest(Data("{\"app\":\"GridFix\",\"version\":1,\(section)}".utf8)))
        }
    }

    func testRouteRegenerationKeepsSelectedVertexAndNeverStealsNames() throws {
        let store = WaypointStore(directory: try directory())
        let manual = store.add(WaypointDraft(name: "Route WP 1", lat: 24, lon: 54))
        let points = [GeoPoint(lat: 24, lon: 54), GeoPoint(lat: 25, lon: 55), GeoPoint(lat: 26, lon: 56)]
        try store.replaceRouteWaypoints(routeID: "route", name: "Route", points: points, folder: "Base")
        let selected = try XCTUnwrap(store.waypoints.first { $0.sourceRoutePointIndex == 1 })
        store.select(selected.id)
        try store.replaceRouteWaypoints(routeID: "route", name: "Renamed", points: Array(points.prefix(2)), folder: "Recon")
        XCTAssertEqual(store.selectedId, selected.id)
        XCTAssertTrue(store.waypoints.contains { $0.id == manual.id && $0.sourceRouteId == nil })
        XCTAssertEqual(store.waypoints.first { $0.id == selected.id }?.name, "Renamed WP 2")
        try store.replaceRouteWaypoints(routeID: "route", name: "Renamed", points: Array(points.prefix(1)), folder: "Recon")
        XCTAssertNil(store.selectedId)
        try store.replaceRouteWaypoints(routeID: "route", name: "Renamed", points: points, folder: "Recon")
        XCTAssertNotEqual(store.waypoints.first { $0.sourceRoutePointIndex == 1 }?.id, selected.id)
    }

    func testRestoreDeduplicatesRouteVerticesAndIncomingIdsWithoutChangingSelection() throws {
        let store = WaypointStore(directory: try directory())
        let own = Waypoint(id: "own", name: "Own", lat: 24, lon: 54, sourceRouteId: "route", sourceRoutePointIndex: 0)
        XCTAssertEqual(try store.restore(waypoints: [own], folders: []), 1)
        store.select(own.id)
        let regenerated = Waypoint(id: "other", name: "Other", lat: 25, lon: 55, sourceRouteId: "route", sourceRoutePointIndex: 0)
        let standalone = Waypoint(id: "new", name: "New", lat: 26, lon: 56)
        XCTAssertEqual(try store.restore(waypoints: [regenerated, standalone, standalone], folders: []), 1)
        XCTAssertEqual(store.waypoints.count, 2)
        XCTAssertEqual(store.selectedId, own.id)
    }

    func testGpxSegmentsNamespacesAltitudeAndRouteRoundTrip() throws {
        let xml = """
        <gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:m="https://milgps.com/gpx/v1" xmlns:fake="urn:fake">
        <wpt lat="24" lon="54"><name>Mark</name><extensions><fake:color>red</fake:color><m:color>cyan</m:color><m:symbolcode>2110</m:symbolcode></extensions></wpt>
        <rte><name>Route</name><rtept lat="24" lon="54"/><rtept lat="25" lon="55"/></rte>
        <trk><name>Patrol</name><trkseg><trkpt lat="24" lon="54"><ele>123.4</ele><time>2026-01-01T00:00:00.123Z</time></trkpt><trkpt lat="24.001" lon="54.001"/></trkseg><trkseg><trkpt lat="25" lon="55"/><trkpt lat="25.001" lon="55.001"/></trkseg></trk>
        </gpx>
        """
        let doc = try GPX.parse(xml)
        XCTAssertFalse(doc.hasSettings)
        XCTAssertEqual(doc.waypoints.first?.metadata.color, "cyan")
        XCTAssertEqual(doc.graphics.count, 1)
        XCTAssertEqual(doc.tracks.map(\.name), ["Patrol — segment 1", "Patrol — segment 2"])
        let first = try TrackCodec.decode(try XCTUnwrap(doc.trackFiles[doc.tracks[0].id]))
        XCTAssertEqual(first.first?.altitudeMeters, 123.4)
        XCTAssertNil(first.last?.altitudeMeters)
        XCTAssertEqual(first.last?.time, 0)
        let exported = GPX.build(waypoints: doc.waypoints, routes: doc.graphics, tracks: try doc.tracks.map {
            GPX.Track(name: $0.name, points: try TrackCodec.decode(doc.trackFiles[$0.id]!))
        })
        XCTAssertTrue(exported.contains("https://milgps.com/gpx/v1"))
        let round = try GPX.parse(exported)
        XCTAssertEqual(round.tracks.count, 2)
        XCTAssertEqual(round.graphics.count, 1)
        XCTAssertEqual(try TrackCodec.decode(round.trackFiles[round.tracks[0].id]!), first)
        XCTAssertThrowsError(try GPX.parse("<gpx><wpt lat=\"24\" lon=\"54\"/>"))
        let foreign = try GPX.parse("""
        <gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:f="urn:foreign">
        <trk><name>Real</name><f:trkseg><trkpt lat="24" lon="54"/></f:trkseg>
        <trkseg><trkpt lat="25" lon="55"/></trkseg></trk>
        </gpx>
        """)
        XCTAssertEqual(foreign.tracks.count, 1)
        XCTAssertEqual(foreign.tracks.first?.pointCount, 1)
        XCTAssertEqual(try TrackCodec.decode(foreign.trackFiles.values.first!).first?.lat, 25)
    }

    func testTrackSentinelsHistoricalTimesAndStrictBackupFiles() throws {
        let (metadata, file) = try TrackCodec.imported(name: "", points: [.init(lat: 24, lon: 54, time: -1), .init(lat: 24.001, lon: 54.001)], now: 1234)
        XCTAssertEqual(metadata.name, "Imported track")
        XCTAssertEqual(metadata.startedAt, 1234)
        XCTAssertTrue(String(decoding: file, as: UTF8.self).contains("-32768.0"))
        XCTAssertThrowsError(try TrackCodec.decode(Data("24 54 -1 -32768\n".utf8)))
        XCTAssertThrowsError(try TrackCodec.decode(Data("24 inf 1 0\n".utf8)))
        XCTAssertThrowsError(try TrackCodec.encode([.init(lat: 91, lon: 54)]))
        XCTAssertEqual(try TrackCodec.decode(Data(" \n24 54 0\n\t\n".utf8)).count, 1)
    }

    func testRouteBackBearingUsesDestinationReferenceAndNoMagneticFallback() throws {
        let points = [GeoPoint(lat: 55, lon: 3), GeoPoint(lat: 65, lon: 12)]
        let leg = try XCTUnwrap(RouteCard.legs(points: points, northReference: 1, pacePer100m: 65) { $0.lat == 55 ? 2 : 7 }.first)
        let reverse = Geodesy.navInfo(fromLat: 65, fromLon: 12, toLat: 55, toLon: 3).bearingTrue
        XCTAssertEqual(try XCTUnwrap(leg.reverse), (reverse - 7 + 720).truncatingRemainder(dividingBy: 360), accuracy: 1e-8)
        XCTAssertGreaterThan(abs(try XCTUnwrap(leg.reverse) - ((try XCTUnwrap(leg.forward) + 180).truncatingRemainder(dividingBy: 360))), 1)
        XCTAssertNil(RouteCard.legs(points: points, northReference: 1, pacePer100m: 65) { _ in nil }.first?.forward)
    }

    func testDatelineLinesAndFitBoundsFollowTheShortPath() throws {
        let points = [GeoPoint(lat: 10, lon: 179), GeoPoint(lat: 12, lon: -179)]
        let segments = FieldMapGeometry.lineSegments(points)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].last, GeoPoint(lat: 11, lon: 180))
        XCTAssertEqual(segments[1].first, GeoPoint(lat: 11, lon: -180))
        let bounds = try XCTUnwrap(FieldMapGeometry.bounds(points))
        XCTAssertEqual(bounds.east - bounds.west, 2)
        let doc = try fixture()
        let hidden = try FieldMapGeometry.geoJSON(document: doc, folders: doc.folders)
        XCTAssertEqual(hidden.routes, 0); XCTAssertEqual(hidden.tracks, 0)
        let shown = try FieldMapGeometry.geoJSON(document: doc, folders: [])
        XCTAssertEqual(shown.routes, 1); XCTAssertEqual(shown.tracks, 1)
    }

    func testCourseHistoryKeepsNewestThirtyWithExistingResultsWinning() throws {
        let store = FieldDataStore(directory: try directory())
        var incoming = Backup.Document(courseHistory: (0..<35).map { .init(name: "Course", points: 1, started: Int64($0), total: 100, splits: [100]) })
        incoming.hasSettings = false
        XCTAssertEqual(try store.restore(incoming).course, 30)
        XCTAssertEqual(store.document.courseHistory.first?.started, 5)
        XCTAssertEqual(try store.restore(incoming).course, 0)
    }
}
