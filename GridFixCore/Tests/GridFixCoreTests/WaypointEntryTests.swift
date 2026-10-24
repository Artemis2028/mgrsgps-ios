import XCTest
@testable import GridFixCore

final class WaypointEntryTests: XCTestCase {
    func testMalformedImportedCoordinatesCannotReachGridFormatting() {
        for (lat, lon) in [(24.0, Double.infinity), (24, .nan), (.nan, 54), (24, 181)] {
            XCTAssertNil(MGRS.parts(lat: lat, lon: lon, digits: 10))
            XCTAssertNil(UTM.coordinate(lat: lat, lon: lon))
        }
        let xml = """
        <gpx><wpt lat="24" lon="inf"><name>Bad</name></wpt>
        <wpt lat="91" lon="54"><name>Out of range</name></wpt>
        <wpt lat="24" lon="54"><name>Good</name></wpt></gpx>
        """
        XCTAssertEqual(GPX.parseWaypoints(xml).map(\.name), ["Good"])
    }
    func testBlankAndMalformedCoordinatesNeverResolveToZero() {
        var draft = WaypointCoordinateDraft()
        XCTAssertNil(draft.position)
        for grid in ["40R", "40R BN 123 12", "00R BN 1234 5678", "40R IO 1234 5678", "40R BN", "40R BN ١٢٣٤ ٥٦٧٨"] {
            draft.grid = grid
            XCTAssertNil(draft.position, grid)
        }
        draft.format = .decimal
        for (lat, lon) in [("", ""), ("nan", "0"), ("0", "inf"), ("91", "0"), ("0", "181")] {
            draft.latitude = lat; draft.longitude = lon
            XCTAssertNil(draft.position)
        }
        draft.latitude = "0"; draft.longitude = "0"
        XCTAssertEqual(draft.position?.lat, 0)
        XCTAssertEqual(draft.position?.lon, 0)
    }

    func testTypedGridResolvesToCellCentreAtEverySupportedPrecision() throws {
        for digits in [4, 6, 8, 10] {
            var draft = WaypointCoordinateDraft()
            draft.grid = try XCTUnwrap(MGRS.parts(lat: 24.4539, lon: 54.3773, digits: digits)).full.lowercased()
            let p = try XCTUnwrap(draft.position)
            let expected = try XCTUnwrap(MGRS.parse(draft.grid))
            XCTAssertEqual(p.lat, expected.lat)
            XCTAssertEqual(p.lon, expected.lon)
        }
    }

    func testEditingPreservesExactFixUntilCoordinateChanges() throws {
        var draft = WaypointCoordinateDraft(lat: 24.453912345, lon: 54.377312345)
        XCTAssertEqual(draft.position?.lat, 24.453912345)
        draft.format = .decimal
        XCTAssertEqual(draft.position?.lon, 54.377312345)
        draft.latitude = "-33.8688"; draft.longitude = "151.2093"
        XCTAssertEqual(draft.position?.lat, -33.8688)
        draft.format = .mgrs
        draft.grid = "18S UJ 2348 0647"
        XCTAssertNotEqual(try XCTUnwrap(draft.position).lat, 24.453912345)
    }

    func testPolarDecimalCoordinatesAreAllowedWithoutInventingAnMgrsGrid() {
        let draft = WaypointCoordinateDraft(lat: 89, lon: -180)
        XCTAssertEqual(draft.format, .decimal)
        XCTAssertEqual(draft.position?.lat, 89)
    }

    func testChangingFormatKeepsTheLastEnteredCoordinate() throws {
        var draft = WaypointCoordinateDraft()
        draft.grid = "40R BN 3412 0700"
        let gridPosition = try XCTUnwrap(draft.position)
        draft.changeFormat(to: .decimal)
        XCTAssertEqual(draft.position, gridPosition)
        draft.latitude = "-33.8688"; draft.longitude = "151.2093"
        let decimalPosition = try XCTUnwrap(draft.position)
        draft.changeFormat(to: .mgrs)
        XCTAssertEqual(draft.position, decimalPosition)
    }

    func testCoordinateEditPreservesIdentityVisibilityAndInterchangeMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WaypointStore(directory: directory)
        let metadata = WaypointMetadata(color: "blue", milgpsSymbolCode: 2110, elevationMeters: 125, timestampMillis: 1234)
        let waypoint = store.add(WaypointDraft(name: "Original", lat: 24, lon: 54, metadata: metadata))
        store.setVisible(id: waypoint.id, visible: false)
        store.select(waypoint.id)
        store.update(id: waypoint.id, draft: WaypointDraft(name: "Edited", lat: -33, lon: 151, metadata: metadata))
        let reloaded = WaypointStore(directory: directory)
        let edited = try XCTUnwrap(reloaded.waypoints.first)
        XCTAssertEqual(edited.id, waypoint.id)
        XCTAssertEqual(edited.createdAt, waypoint.createdAt)
        XCTAssertEqual(edited.metadata, metadata)
        XCTAssertEqual(edited.lat, -33)
        XCTAssertFalse(edited.visible)
        XCTAssertEqual(reloaded.selectedId, waypoint.id)
    }

    func testMapHonoursWaypointAndCaseInsensitiveFolderVisibility() {
        let shown = Waypoint(id: "shown", name: "Shown", lat: 24, lon: 54, folder: "Base")
        let hidden = Waypoint(id: "hidden", name: "Hidden", lat: 24, lon: 54, visible: false)
        let folderHidden = Waypoint(id: "folder", name: "Folder", lat: 24, lon: 54, folder: "Recon")
        let invalid = Waypoint(id: "invalid", name: "Invalid", lat: .nan, lon: 54)
        let visible = WaypointMapSnapshot.visible(waypoints: [shown, hidden, folderHidden, invalid],
                                                 folders: [FolderInfo(name: "recon", visible: false)])
        XCTAssertEqual(visible.map(\.id), ["shown"])
    }
}
