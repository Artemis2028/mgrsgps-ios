import XCTest
import GridFixCore
import UniformTypeIdentifiers
@testable import MGRSGPS

@MainActor
final class InterchangeIntegrationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testUnchangedImportKeepsEditedFavoritesVisibilityMetadataAndSelectionAcrossReopen() throws {
        let dir = try directory(), waypoints = WaypointStore(directory: dir), field = FieldDataStore(directory: dir)
        let bytes = Data("name,lat,lon,folder,elevation_m\nAlpha,24,54,Patrol,80\n".utf8)
        let first = try TextInterchange.preview(bytes,format: .csv,now: 100)
        XCTAssertTrue(InterchangeCoordinator.apply(first.document,waypoints: waypoints,field: field).completed)
        let id = try XCTUnwrap(waypoints.waypoints.first?.id)
        try waypoints.setFavorite(id: id,favorite: true)
        waypoints.setVisible(id: id,visible: false); waypoints.select(id)
        let original = try XCTUnwrap(waypoints.waypoints.first)
        var draft = WaypointDraft(name: "Edited",lat: original.lat,lon: original.lon,folder: original.folder)
        draft.metadata = original.metadata
        waypoints.update(id: id,draft: draft)
        let second = try TextInterchange.preview(bytes,format: .csv,now: 999)
        let result = InterchangeCoordinator.apply(second.document,waypoints: waypoints,field: field)
        XCTAssertTrue(result.completed); XCTAssertTrue(result.message.contains("Nothing new"))
        let reopened = WaypointStore(directory: dir)
        XCTAssertEqual(reopened.waypoints.count,1); XCTAssertEqual(reopened.selectedId,id)
        XCTAssertEqual(reopened.waypoints.first?.name,"Edited"); XCTAssertEqual(reopened.waypoints.first?.favorite,true)
        XCTAssertEqual(reopened.waypoints.first?.visible,false); XCTAssertEqual(reopened.waypoints.first?.metadata.elevationMeters,80)
    }
    func testTracksCommitBeforeWaypointFailureAndRetryFinishesRemainingRecordsOnce() throws {
        let dir = try directory(), waypoints = WaypointStore(directory: dir), field = FieldDataStore(directory: dir)
        let xml = "<gpx><wpt lat=\"24\" lon=\"54\"><name>Checkpoint</name></wpt><rte><name>Patrol</name><rtept lat=\"24\" lon=\"54\"/><rtept lat=\"24.01\" lon=\"54\"/></rte><trk><name>Walk</name><trkseg><trkpt lat=\"24\" lon=\"54\"/><trkpt lat=\"24.01\" lon=\"54\"/></trkseg></trk></gpx>"
        let document = try GPX.parse(xml)
        let blocked = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.createDirectory(at: blocked,withIntermediateDirectories: true)
        let first = InterchangeCoordinator.apply(document,waypoints: waypoints,field: field)
        XCTAssertFalse(first.completed); XCTAssertTrue(first.message.contains("Already imported: 1 tracks"),first.message)
        XCTAssertEqual(field.document.tracks.count,1); XCTAssertTrue(field.document.graphics.isEmpty); XCTAssertTrue(waypoints.waypoints.isEmpty)
        try FileManager.default.removeItem(at: blocked)
        XCTAssertTrue(InterchangeCoordinator.apply(document,waypoints: waypoints,field: field).completed)
        XCTAssertTrue(InterchangeCoordinator.apply(document,waypoints: waypoints,field: field).completed)
        XCTAssertEqual(FieldDataStore(directory: dir).document.tracks.count,1)
        XCTAssertEqual(FieldDataStore(directory: dir).document.graphics.count,1)
        XCTAssertEqual(WaypointStore(directory: dir).waypoints.count,1)
    }
    func testGraphicFailureKeepsPublishedWaypointsAndRetryAddsRouteWithoutReplacingEdits() throws {
        let dir = try directory(), waypoints = WaypointStore(directory: dir), field = FieldDataStore(directory: dir)
        let json = "{\"type\":\"GeometryCollection\",\"geometries\":[{\"type\":\"Point\",\"coordinates\":[54,24]},{\"type\":\"LineString\",\"coordinates\":[[54,24],[54,24.01]]}]}"
        let doc = try TextInterchange.preview(Data(json.utf8)).document
        let blocked = dir.appendingPathComponent("field-data-v1.zip")
        try FileManager.default.createDirectory(at: blocked,withIntermediateDirectories: true)
        let result = InterchangeCoordinator.apply(doc,waypoints: waypoints,field: field)
        XCTAssertFalse(result.completed); XCTAssertTrue(result.message.contains("Already imported: 1 waypoints"),result.message)
        XCTAssertEqual(waypoints.waypoints.count,1); XCTAssertTrue(field.document.graphics.isEmpty)
        try FileManager.default.removeItem(at: blocked)
        XCTAssertTrue(InterchangeCoordinator.apply(doc,waypoints: waypoints,field: field).completed)
        XCTAssertEqual(waypoints.waypoints.count,1); XCTAssertEqual(field.document.graphics.count,1)
    }
    func testBoundedCoordinatedFileReadAndDocumentTypes() throws {
        let dir = try directory(), url = dir.appendingPathComponent("points.csv")
        let bytes = Data("name,lat,lon\nRead,24,54\n".utf8)
        try bytes.write(to: url)
        XCTAssertEqual(try InterchangeFileReader.read(url,limit: bytes.count),bytes)
        XCTAssertThrowsError(try InterchangeFileReader.read(url,limit: bytes.count-1))
        let csv = TextDocumentFile(text: String(decoding: bytes,as: UTF8.self),contentType: .commaSeparatedText)
        XCTAssertEqual(csv.contentType.preferredFilenameExtension,"csv")
        XCTAssertTrue(UTType.gridFixGeoJSON.conforms(to: .json)); XCTAssertEqual(UTType.gridFixGeoJSON.preferredFilenameExtension,"geojson")
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String:Any]])
        XCTAssertTrue(types.contains { ($0["LSItemContentTypes"] as? [String])?.contains("app.gridfix.geojson") == true })
    }
    func testJavaMissionPackageMappedPreviewOrderedRetryAndReopenedStore() throws {
        let dir = try directory(), source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "android-mission-package",withExtension: "zip"))
        let url = dir.appendingPathComponent("mission.dpk")
        try Data(contentsOf: source).write(to: url)
        let waypoints = WaypointStore(directory: dir), field = FieldDataStore(directory: dir)
        let preview = try InterchangeFileReader.preview(url,format: nil,knownFolders: [])
        XCTAssertEqual(preview.format,.atak); XCTAssertEqual(preview.recordCount,5)
        let blocked = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.createDirectory(at: blocked,withIntermediateDirectories: true)
        let partial = InterchangeCoordinator.apply(preview.document,waypoints: waypoints,field: field)
        XCTAssertFalse(partial.completed); XCTAssertEqual(field.document.tracks.count,1)
        XCTAssertTrue(field.document.graphics.isEmpty); XCTAssertTrue(waypoints.waypoints.isEmpty)
        try FileManager.default.removeItem(at: blocked)
        XCTAssertTrue(InterchangeCoordinator.apply(preview.document,waypoints: waypoints,field: field).completed)
        let point = try XCTUnwrap(waypoints.waypoints.first)
        try waypoints.setFavorite(id: point.id,favorite: true); waypoints.setVisible(id: point.id,visible: false); waypoints.select(point.id)
        let retry = try InterchangeFileReader.preview(url,format: nil,knownFolders: waypoints.folders.map(\.name))
        XCTAssertTrue(InterchangeCoordinator.apply(retry.document,waypoints: waypoints,field: field).completed)
        let reopened = WaypointStore(directory: dir), saved = FieldDataStore(directory: dir)
        XCTAssertEqual(reopened.waypoints.count,2); XCTAssertEqual(reopened.waypoints[0].affiliation,"hostile")
        XCTAssertTrue(reopened.waypoints[0].favorite); XCTAssertFalse(reopened.waypoints[0].visible); XCTAssertEqual(reopened.selectedId,point.id)
        XCTAssertEqual(saved.document.graphics.count,2); XCTAssertEqual(saved.document.tracks.count,1)
    }
    func testKMLKMZDPKDocumentTypesAndCoordinatedUnicodeFileParsing() throws {
        let dir = try directory(), url = dir.appendingPathComponent("unicode.kml")
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><kml><Placemark><name><![CDATA[Café]]></name><Point><coordinates>-117,34</coordinates></Point></Placemark></kml>"
        try XCTUnwrap(xml.data(using: .utf16)).write(to: url)
        XCTAssertEqual(try InterchangeFileReader.preview(url,format: nil,knownFolders: []).document.waypoints[0].name,"Café")
        XCTAssertEqual(UTType.gridFixKML.preferredFilenameExtension,"kml"); XCTAssertTrue(UTType.gridFixKML.conforms(to: .xml))
        XCTAssertEqual(UTType.gridFixKMZ.preferredFilenameExtension,"kmz"); XCTAssertTrue(UTType.gridFixKMZ.conforms(to: .zip))
        XCTAssertEqual(UTType.gridFixDPK.preferredFilenameExtension,"dpk"); XCTAssertTrue(UTType.gridFixDPK.conforms(to: .zip))
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String:Any]])
        let supported = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        for type in ["com.google.earth.kml","com.google.earth.kmz","app.gridfix.dpk","public.zip-archive"] { XCTAssertTrue(supported.contains(type)) }
    }

}
