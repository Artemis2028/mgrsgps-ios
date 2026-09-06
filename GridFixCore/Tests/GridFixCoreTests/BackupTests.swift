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

    func testGPXRoundTripPreservesMilGpsMetadata() {
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
        XCTAssertEqual(drafts[0].metadata?.elevationMeters!, 5, accuracy: 1e-9)
    }

    func testMilGpsSymbolEncodeDecode() {
        XCTAssertEqual(MilGpsSymbols.encode(shape: .circle, character: "6"), 1106)
        XCTAssertEqual(MilGpsSymbols.decode(2100)?.shape, .triangle)
        XCTAssertEqual(MilGpsSymbols.decode(2100)?.character, "0")
        XCTAssertNil(MilGpsSymbols.decode(50)) // cross with non-zero suffix
    }
}
