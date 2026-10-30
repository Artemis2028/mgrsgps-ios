import XCTest
@testable import GridFixCore

@MainActor
final class StagedRestoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func graphic(_ id: String,_ name: String) -> Backup.Graphic {
        .init(id: id,name: name,type: "checkpoint",points: [.init(lat: 24,lon: 54)])
    }
    private func incoming() -> Backup.Document {
        var document = Backup.Document(); document.hasSettings = false
        document.graphics = [graphic("archive","Archived point")]
        return document
    }

    func testFieldWriteIsInvisibleUntilAtomicPublication() async throws {
        let directory = try directory(), store = FieldDataStore(directory: directory)
        try store.saveGraphic(graphic("local","Local"))
        let original = try Data(contentsOf: directory.appendingPathComponent("field-data-v2.json"))
        let snapshot = try store.restoreSnapshot(), input = incoming()
        let prepared = try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return try snapshot.prepare(input)
        }.value
        XCTAssertEqual(store.document.graphics.count,1)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("field-data-v2.json")),original)
        XCTAssertEqual(FieldDataStore(directory: directory).document.graphics.count,1)
        XCTAssertEqual(try store.publishRestore(prepared)?.graphics,1)
        XCTAssertEqual(FieldDataStore(directory: directory).document.graphics.map(\.id),["local","archive"])
    }

    func testFieldSnapshotRejectsConcurrentEditAndNewRecordingThenRebases() async throws {
        let directory = try directory(), store = FieldDataStore(directory: directory)
        try store.saveGraphic(graphic("local","Local"))
        let snapshot = try store.restoreSnapshot(), input = incoming()
        let prepared = try await Task.detached { try snapshot.prepare(input) }.value
        try store.saveGraphic(graphic("local","Edited during preparation"))
        let (track,bytes) = try TrackCodec.imported(name: "New recording",points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54)],now: 1000)
        var recorded = Backup.Document(); recorded.hasSettings = false
        recorded.tracks = [track]; recorded.trackFiles[track.id] = bytes
        try store.saveRecordedTrack(recorded)
        XCTAssertNil(try store.publishRestore(prepared))
        XCTAssertEqual(store.document.graphics.count,1)
        let fresh = try store.restoreSnapshot()
        let rebased = try await Task.detached { try fresh.prepare(input) }.value
        XCTAssertEqual(try store.publishRestore(rebased)?.graphics,1)
        let reopened = FieldDataStore(directory: directory)
        XCTAssertEqual(reopened.document.graphics[0].name,"Edited during preparation")
        XCTAssertEqual(reopened.document.graphics.count,2)
        XCTAssertEqual(try reopened.points(for: track.id).count,2)
    }

    func testWaypointRevisionIncludesSelectionAndFolderEdits() async throws {
        let directory = try directory(), store = WaypointStore(directory: directory)
        let local = store.add(.init(name: "Local",lat: 24,lon: 54))
        let archived = Waypoint(id: "archive",name: "Archive",lat: 25,lon: 55,folder: "recon")
        let folders = [FolderInfo(name: "Recon",visible: false)]
        let snapshot = store.restoreSnapshot()
        let prepared = try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return try snapshot.prepare(waypoints: [archived],folders: folders)
        }.value
        store.select(local.id)
        _ = try store.createLibraryFolder("Live")
        XCTAssertNil(try store.publishRestore(prepared))
        XCTAssertEqual(store.waypoints.count,1)
        let fresh = store.restoreSnapshot()
        let rebased = try await Task.detached { try fresh.prepare(waypoints: [archived],folders: folders) }.value
        XCTAssertEqual(try store.publishRestore(rebased),1)
        let reopened = WaypointStore(directory: directory)
        XCTAssertEqual(reopened.selectedId,local.id)
        XCTAssertEqual(reopened.waypoints.count,2)
        XCTAssertEqual(reopened.waypoints.last?.folder,"Recon")
        XCTAssertEqual(reopened.folders.first { $0.name == "Recon" }?.visible,false)
        XCTAssertTrue(reopened.folders.contains { $0.name == "Live" })
    }

    func testWaypointEditsInvalidatePreparedFile() async throws {
        let directory = try directory(), store = WaypointStore(directory: directory)
        let local = store.add(.init(name: "Local",lat: 24,lon: 54))
        let snapshot = store.restoreSnapshot()
        let prepared = try await Task.detached { try snapshot.prepare(waypoints: [],folders: []) }.value
        store.update(id: local.id,draft: .init(name: "Edited",lat: 24.01,lon: 54))
        XCTAssertNil(try store.publishRestore(prepared))
        XCTAssertEqual(WaypointStore(directory: directory).waypoints[0].name,"Edited")
    }

    func testPublicationFailureKeepsDestinationAndLiveRecords() async throws {
        let directory = try directory(), store = WaypointStore(directory: directory)
        _ = store.add(.init(name: "Local",lat: 24,lon: 54))
        let snapshot = store.restoreSnapshot()
        let prepared = try await Task.detached { try snapshot.prepare(waypoints: [Waypoint(id: "archive",name: "Archive",lat: 25,lon: 55)],folders: []) }.value
        let target = directory.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target,withIntermediateDirectories: false)
        let sentinel = target.appendingPathComponent("keep")
        try Data("kept".utf8).write(to: sentinel)
        XCTAssertThrowsError(try store.publishRestore(prepared))
        XCTAssertEqual(store.waypoints.count,1)
        XCTAssertEqual(try String(contentsOf: sentinel,encoding: .utf8),"kept")
    }

    func testPreparedSnapshotCannotPublishThroughAnotherStoreInstance() async throws {
        let directory = try directory(), first = FieldDataStore(directory: directory), other = FieldDataStore(directory: directory)
        let snapshot = try first.restoreSnapshot(), input = incoming()
        let prepared = try await Task.detached { try snapshot.prepare(input) }.value
        XCTAssertThrowsError(try other.publishRestore(prepared))
        XCTAssertTrue(first.document.graphics.isEmpty); XCTAssertTrue(other.document.graphics.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("field-data-v2.json").path))
        XCTAssertEqual(try first.publishRestore(prepared)?.graphics,1,"A rejected consumer cannot destroy the owner's preparation")
        XCTAssertEqual(FieldDataStore(directory: directory).document.graphics.count,1)
    }
}
