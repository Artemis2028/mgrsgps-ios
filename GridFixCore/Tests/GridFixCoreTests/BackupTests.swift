import XCTest
@testable import GridFixCore

final class BackupTests: XCTestCase {

    func testManifestRoundTripPreservesWaypointsAndNullDeclination() throws {
        var settings = Backup.AppSettings()
        settings.declinationOverride = nil
        settings.mgrsDigits = 8
        let wp = Waypoint(
            id: "wp-1", name: "OP Falcon", lat: 24.4539, lon: 54.3773,
            folder: "Recon",
            metadata: WaypointMetadata(color: "red", milgpsSymbolCode: 1106,
                                       elevationMeters: 12.5, timestampMillis: 1_700_000_000_000)
        )
        let doc = Backup.Document(
            exportedAt: 1_788_514_222_663,
            waypoints: [wp],
            folders: [FolderInfo(name: "Recon", visible: false),
                      FolderInfo(name: "Base", visible: true)],
            settings: settings
        )
        let data = try Backup.encodeManifest(doc)
        let decoded = try Backup.decodeManifest(data)
        XCTAssertEqual(decoded.waypoints.count, 1)
        XCTAssertEqual(decoded.waypoints[0].id, "wp-1")
        XCTAssertEqual(decoded.waypoints[0].metadata.color, "red")
        XCTAssertEqual(decoded.waypoints[0].metadata.milgpsSymbolCode, 1106)
        XCTAssertEqual(decoded.waypoints[0].metadata.elevationMeters!, 12.5, accuracy: 1e-9)
        XCTAssertNil(decoded.settings.declinationOverride)
        XCTAssertEqual(decoded.settings.mgrsDigits, 8)
        // Legacy reserved folder names collapse on read.
        let legacy = try Backup.decodeManifest(Data("""
        {"app":"GridFix","version":1,"waypoints":[{"id":"a","name":"X","lat":1.0,"lon":2.0,"folder":"Waypoints"}],"folders":[],"graphics":[],"settings":{},"tracks":[],"courseHistory":[]}
        """.utf8))
        XCTAssertEqual(legacy.waypoints[0].folder, "Base")
    }

    func testZipRoundTripAndAdditiveRestore() throws {
        let wp1 = Waypoint(id: "a", name: "A", lat: 1, lon: 2)
        let wp2 = Waypoint(id: "b", name: "B", lat: 3, lon: 4, folder: "Recon")
        let doc = Backup.Document(waypoints: [wp1, wp2],
                                  folders: [FolderInfo(name: "Recon")])
        let zip = try Backup.exportZip(doc)
        let round = try Backup.importZip(zip)
        XCTAssertEqual(round.waypoints.map(\.id).sorted(), ["a", "b"])

        let store = WaypointStore.inMemory(waypoints: [wp1])
        let first = Backup.restoreWaypoints(round, into: store)
        XCTAssertEqual(first.waypoints, 1) // only b is new
        let second = Backup.restoreWaypoints(round, into: store)
        XCTAssertEqual(second.waypoints, 0) // idempotent
        XCTAssertEqual(store.waypoints.count, 2)
    }

    func testUnsupportedVersionIsRefused() {
        let data = Data("""
        {"app":"GridFix","version":99,"waypoints":[],"folders":[],"graphics":[],"settings":{},"tracks":[],"courseHistory":[]}
        """.utf8)
        XCTAssertThrowsError(try Backup.decodeManifest(data)) { err in
            guard case BackupError.unsupportedVersion(99) = err else {
                return XCTFail("wrong error \(err)")
            }
        }
    }

    func testGPXRoundTripPreservesMilGpsMetadata() throws {
        let wp = Waypoint(
            id: "1", name: "Mark", lat: 24.5, lon: 54.4,
            metadata: WaypointMetadata(color: "cyan", milgpsSymbolCode: 2100,
                                       elevationMeters: 5, timestampMillis: 1_700_000_000_000)
        )
        let xml = GPX.build(waypoints: [wp])
        XCTAssertTrue(xml.contains("milgps:symbolcode>2100"))
        XCTAssertTrue(xml.contains("milgps:color>cyan"))
        let drafts = GPX.parseWaypoints(xml)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].name, "Mark")
        XCTAssertEqual(drafts[0].metadata?.color, "cyan")
        XCTAssertEqual(drafts[0].metadata?.milgpsSymbolCode, 2100)
        let elev = try XCTUnwrap(drafts[0].metadata?.elevationMeters)
        XCTAssertEqual(elev, 5, accuracy: 1e-9)
    }

    func testMilGpsSymbolEncodeDecode() {
        XCTAssertEqual(MilGpsSymbols.encode(shape: .circle, character: "6"), 1106)
        XCTAssertEqual(MilGpsSymbols.decode(2100)?.shape, .triangle)
        XCTAssertEqual(MilGpsSymbols.decode(2100)?.character, "0")
        XCTAssertNil(MilGpsSymbols.decode(50)) // cross with non-zero suffix
    }
}

final class QuietBoundaryBackupTests: XCTestCase {
    private var area: BoundaryArea { .init(id: "quiet-1",name: "Quiet CAFÉ",vertices: [.init(lat: 24,lon: 54),.init(lat: 24,lon: 54.001),.init(lat: 24.001,lon: 54.001),.init(lat: 24.001,lon: 54)]) }
    func testVersionOneRoundTripKeepsGeometrySeparateAndLegacyDefaultsEmpty() throws {
        let value = Backup.Document(exportedAt: 1,waypoints: [.init(id: "quiet-fixture-wp",name: "QUIET CAFÉ FIXTURE",lat: 24.0005,lon: 54.0005)],quietBoundaries: [area])
        let decoded = try Backup.importZip(Backup.exportZip(value))
        XCTAssertEqual(decoded.quietBoundaries,[area]); XCTAssertTrue(decoded.navLanes.isEmpty)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Backup.encodeManifest(value)) as? [String:Any])
        XCTAssertEqual(root["version"] as? Int,1)
        let record = try XCTUnwrap((root["quietBoundaries"] as? [[String:Any]])?.first)
        XCTAssertEqual(Set(record.keys),["id","name","vertices"])
        XCTAssertTrue(try Backup.decodeManifest(Data(#"{"app":"GridFix","version":1}"#.utf8)).quietBoundaries.isEmpty)
        let plain = try Backup.exportZip(value), password = "synthetic-fixture-only"
        let protected = try BackupCrypto.seal(plain,password: password)
        XCTAssertEqual(try Backup.importZip(BackupCrypto.open(protected,password: password)),decoded)
        if let path = ProcessInfo.processInfo.environment["GRIDFIX_QUIET_FIXTURE_DIRECTORY"] {
            let directory = URL(fileURLWithPath: path,isDirectory: true)
            try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
            try plain.write(to: directory.appendingPathComponent("quiet-boundary-v1.zip"))
            try protected.write(to: directory.appendingPathComponent("quiet-boundary-v1.mgrsgps"))
            try Data(password.utf8).write(to: directory.appendingPathComponent("synthetic-fixture-password.txt"))
        }
    }
    func testMalformedOptionalSectionRejectsWholeBackup() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Backup.encodeManifest(.init(quietBoundaries: [area]))) as? [String:Any])
        let record = try XCTUnwrap((original["quietBoundaries"] as? [[String:Any]])?.first)
        for section: Any in [NSNull(),"bad",[1],[record,record],Array(repeating: record,count: 101)] {
            var root = original; root["quietBoundaries"] = section
            XCTAssertThrowsError(try Backup.decodeManifest(JSONSerialization.data(withJSONObject: root)))
        }
        var bad = area; bad.vertices = [area.vertices[0],area.vertices[2],area.vertices[1],area.vertices[3]]
        XCTAssertThrowsError(try Backup.exportZip(.init(quietBoundaries: [area,bad])))
        bad = area; bad.name = " "
        XCTAssertThrowsError(try Backup.validate(.init(quietBoundaries: [bad])))
        bad = BoundaryArea(id: " ",name: area.name,vertices: area.vertices)
        XCTAssertThrowsError(try Backup.validate(.init(quietBoundaries: [bad])))
        bad = area; bad.vertices = Array(repeating: area.vertices[0],count: 257)
        XCTAssertThrowsError(try Backup.validate(.init(quietBoundaries: [bad])))
    }
}
