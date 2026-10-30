import XCTest
@testable import GridFixCore

final class LibrarySearchTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    private func point(_ name: String,_ lon: Double = 0,created: Int64 = 0,favorite: Bool = false) -> Waypoint {
        .init(id: name,name: name,lat: 0,lon: lon,createdAt: created,favorite: favorite)
    }
    func testFavoritesLeadEveryOrderAndDistanceFallsBackToNameWithoutFix() {
        let points = [point("charlie",0.003,created: 3),point("alpha",0.002,created: 1,favorite: true),point("bravo",0.001,created: 2)]
        XCTAssertEqual(LibraryListing.waypoints(points,folder: nil,origin: nil).map(\.name),["alpha","bravo","charlie"])
        XCTAssertEqual(LibraryListing.waypoints(points,folder: nil,origin: nil,sort: .name).map(\.name),["alpha","bravo","charlie"])
        XCTAssertEqual(LibraryListing.waypoints(points,folder: nil,origin: nil,sort: .newest).map(\.name),["alpha","charlie","bravo"])
        XCTAssertEqual(LibraryListing.waypoints(points,folder: nil,origin: .init(lat: 0,lon: 0)).map(\.name),["alpha","bravo","charlie"])
    }
    func testSearchFindsNameFolderDesignationAndCompactGridAndStillFiltersFolder() {
        var a = point("OBJ Hawk"); a.folder = "Lane A"; a.designation = "1 PLT"
        var b = point("RP"); b.lat = 35.5; b.lon = -79.5; b.folder = "Lane B"
        for query in [" hawk ","lane a","1 plt"] { XCTAssertEqual(LibraryListing.waypoints([a,b],folder: nil,origin: nil,query: query).map(\.id),[a.id]) }
        let grid = MGRS.parts(lat: b.lat,lon: b.lon,digits: 10)!.full
        XCTAssertEqual(LibraryListing.waypoints([a,b],folder: nil,origin: nil,query: String(grid.replacingOccurrences(of: " ",with: "").prefix(9))).map(\.id),[b.id])
        XCTAssertTrue(LibraryListing.waypoints([a,b],folder: "Lane A",origin: nil,query: "RP").isEmpty)
    }
    func testCaseInsensitiveOrderMatchesActualJVMFixtureAndRetainsCaseTies() {
        // Generated with Java17 String.CASE_INSENSITIVE_ORDER, including simple
        // casing that differs from locale collation/full Unicode folding.
        let names = ["Zulu","alpha","ALPHA","İ","i","ı","ß","SS","Σ","ς","σ","𐐀","𐐨","😀","\u{E000}"]
        let expected = ["alpha","ALPHA","İ","i","ı","SS","Zulu","ß","Σ","ς","σ","\u{E000}","𐐀","𐐨","😀"]
        XCTAssertEqual(LibraryListing.waypoints(names.map { point($0) },folder: nil,origin: nil,sort: .name).map(\.name),expected)
    }
    func testOldLocalSnapshotDefaultsFavoriteWithoutLosingMetadataOwnershipOrSelection() throws {
        let dir = try directory(); var original = point("Legacy"); original.sourceRouteId = "route"; original.sourceRoutePointIndex = 1
        original.metadata = .init(color: "red",milgpsSymbolCode: 1101,elevationMeters: 123,timestampMillis: 1000)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object.removeValue(forKey: "favorite")
        let bytes = try JSONSerialization.data(withJSONObject: ["waypoints":[object],"folders":[["name":"Base","visible":true]],"selectedId":original.id])
        try bytes.write(to: dir.appendingPathComponent("waypoints-v1.json"))
        let store = WaypointStore(directory: dir)
        XCTAssertEqual(store.waypoints,[original]); XCTAssertEqual(store.selectedId,original.id)
        try store.setFavorite(id: original.id,favorite: true)
        let reopened = WaypointStore(directory: dir)
        XCTAssertTrue(reopened.waypoints[0].favorite); XCTAssertEqual(reopened.waypoints[0].metadata,original.metadata)
        XCTAssertEqual(reopened.waypoints[0].sourceRouteId,"route"); XCTAssertEqual(reopened.selectedId,original.id)
    }
    func testFavoriteRoundTripsAndroidBackupAndLegacyManifestDefaultsFalse() throws {
        let original = point("Star",favorite: true), document = Backup.Document(waypoints: [point("Plain"),original])
        let restored = try Backup.importZip(Backup.exportZip(document))
        XCTAssertEqual(restored.waypoints.map(\.favorite),[false,true])
        var legacy = try JSONSerialization.jsonObject(with: Backup.encodeManifest(document)) as! [String: Any]
        var records = legacy["waypoints"] as! [[String: Any]]
        for i in records.indices { records[i].removeValue(forKey: "favorite") }
        legacy["waypoints"] = records
        XCTAssertTrue(try Backup.decodeManifest(JSONSerialization.data(withJSONObject: legacy)).waypoints.allSatisfy { !$0.favorite })
    }
    func testFailedFavoriteWriteDoesNotPublishAndEditsRouteRegenerationRetainFavorite() throws {
        let dir = try directory(), store = WaypointStore(directory: dir)
        try store.replaceRouteWaypoints(routeID: "r",name: "R",points: [.init(lat: 0,lon: 0),.init(lat: 0,lon: 1)],folder: "Base")
        let id = store.waypoints[0].id; try store.setFavorite(id: id,favorite: true)
        try store.replaceRouteWaypoints(routeID: "r",name: "Renamed",points: [.init(lat: 0,lon: 0),.init(lat: 0,lon: 2)],folder: "Base")
        store.update(id: id,draft: .init(name: "Edited",lat: 1,lon: 1)); XCTAssertTrue(store.waypoints[0].favorite)
        let path = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.setFavorite(id: id,favorite: false)); XCTAssertTrue(store.waypoints[0].favorite)
    }
}
