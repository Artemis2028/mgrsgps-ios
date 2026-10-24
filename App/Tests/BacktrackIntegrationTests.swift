import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class BacktrackIntegrationTests: XCTestCase {
    private func fixture() throws -> (URL,FieldDataStore,WaypointStore,Backup.TrackMeta) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let field = FieldDataStore(directory: dir), waypoints = WaypointStore(directory: dir)
        let point = waypoints.add(.init(name: "Existing target",lat: 24,lon: 54)); waypoints.select(point.id)
        let (track,bytes) = try TrackCodec.imported(name: "Patrol",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54),.init(lat: 24.01,lon: 54.01)],now: 1000,folder: "Recon")
        var doc = Backup.Document(); doc.hasSettings = false; doc.tracks = [track]; doc.trackFiles[track.id] = bytes
        _ = try field.restore(doc); _ = try waypoints.createLibraryFolder("Recon"); try waypoints.setLibraryFolderVisible("Recon",visible: false)
        return (dir,field,waypoints,track)
    }
    func testBacktrackPublishesReverseRouteKeepsLogAndDoesNotSelectNavigationTarget() async throws {
        let (dir,field,waypoints,track) = try fixture(), before = field.document.trackFiles[track.id], selected = waypoints.selectedId
        let route = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints)
        XCTAssertEqual(route.points.first,.init(lat: 24.01,lon: 54.01)); XCTAssertEqual(route.points.last,.init(lat: 24,lon: 54))
        XCTAssertEqual(route.folder,"Recon"); XCTAssertEqual(route.name,"Back Patrol")
        XCTAssertEqual(field.document.trackFiles[track.id],before); XCTAssertEqual(waypoints.selectedId,selected); XCTAssertEqual(waypoints.waypoints.count,1)
        XCTAssertEqual(waypoints.folders.first { $0.name == "Recon" }?.visible,true)
        XCTAssertEqual(FieldDataStore(directory: dir).document.graphics,[route])
    }
    func testCancelledBacktrackCannotPublishLateRoute() async throws {
        let (_,field,waypoints,track) = try fixture()
        let task = Task { try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled work must not publish") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(field.document.graphics.isEmpty); XCTAssertEqual(field.document.tracks.count,1)
    }
    func testDeletedTrackCannotProduceRouteFromOldSelection() async throws {
        let (_,field,waypoints,track) = try fixture(); try field.deleteTrack(track.id)
        do { _ = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints); XCTFail("Deleted track") } catch {}
        XCTAssertTrue(field.document.graphics.isEmpty)
    }
    func testFailedBacktrackSaveKeepsOriginalTrackAndNoPublishedRoute() async throws {
        let (dir,field,waypoints,track) = try fixture(), before = field.document
        let path = dir.appendingPathComponent("field-data-v1.zip")
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        do { _ = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints); XCTFail("Unwritable archive") } catch {}
        XCTAssertEqual(field.document,before)
    }
}
