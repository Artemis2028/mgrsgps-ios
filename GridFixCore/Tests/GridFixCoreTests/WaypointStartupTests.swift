import XCTest
@testable import GridFixCore

@MainActor
final class WaypointStartupTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testWorkerPreparesFullLargeLibraryFoldersAndSelectedTargetWithoutWriting() async throws {
        let dir = try directory(),store = WaypointStore(directory: dir)
        let points = (0..<5000).map { Waypoint(name: "Point \($0)",lat: 35,lon: -79,folder: "Recon") }
        try store.restore(waypoints: points,folders: [.init(name: "Recon",visible: false),.init(name: "Empty saved folder")])
        store.select(points[3000].id)
        let file = dir.appendingPathComponent("waypoints-v1.json"),before = try Data(contentsOf: file)
        let prepared = try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return try WaypointStore.prepareStartup(directory: dir)
        }.value
        XCTAssertTrue(Thread.isMainThread)
        let reopened = try WaypointStore(startup: prepared)
        XCTAssertEqual(reopened.waypoints,store.waypoints)
        XCTAssertEqual(reopened.folders,store.folders)
        XCTAssertEqual(reopened.selectedId,points[3000].id)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(try Data(contentsOf: file),before)
    }
    func testChangedOrRemovedLibraryCannotPublishOlderStartupSnapshot() throws {
        let dir = try directory(),store = WaypointStore(directory: dir)
        _ = store.add(.init(name: "Original",lat: 35,lon: -79))
        let prepared = try WaypointStore.prepareStartup(directory: dir)
        _ = store.add(.init(name: "Newer",lat: 36,lon: -78))
        let file = dir.appendingPathComponent("waypoints-v1.json"),newer = try Data(contentsOf: file)
        XCTAssertThrowsError(try WaypointStore(startup: prepared))
        XCTAssertEqual(try Data(contentsOf: file),newer)
        let updated = try WaypointStore.prepareStartup(directory: dir)
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try WaypointStore(startup: updated))
    }
    func testMissingLibraryDoesNotWriteAndCannotReplaceNewlyCreatedLibrary() throws {
        let dir = try directory(),file = dir.appendingPathComponent("waypoints-v1.json")
        let prepared = try WaypointStore.prepareStartup(directory: dir)
        let empty = try WaypointStore(startup: prepared)
        XCTAssertTrue(empty.waypoints.isEmpty); XCTAssertNil(empty.loadError)
        XCTAssertEqual(empty.folders.map(\.name),[Folders.defaultFolder])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        _ = WaypointStore(directory: dir).add(.init(name: "Arrived later",lat: 35,lon: -79))
        XCTAssertThrowsError(try WaypointStore(startup: prepared))
    }
    func testCorruptLibraryStaysReadOnlyAndOriginalBytesAreKept() throws {
        let dir = try directory(),file = dir.appendingPathComponent("waypoints-v1.json"),bytes = Data("unreadable CAFÉ waypoints".utf8)
        try bytes.write(to: file)
        let prepared = try WaypointStore.prepareStartup(directory: dir),store = try WaypointStore(startup: prepared)
        XCTAssertNotNil(store.loadError); XCTAssertTrue(store.waypoints.isEmpty)
        XCTAssertThrowsError(try store.restore(waypoints: [.init(name: "Unsafe replacement",lat: 35,lon: -79)],folders: []))
        XCTAssertThrowsError(try store.restoreSnapshot().prepareSelection(nil))
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testCancelledPreparationNeverProducesAStoreOrChangesFiles() async throws {
        let dir = try directory(),store = WaypointStore(directory: dir)
        _ = store.add(.init(name: "Kept",lat: 35,lon: -79))
        let file = dir.appendingPathComponent("waypoints-v1.json"),before = try Data(contentsOf: file)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try WaypointStore.prepareStartup(directory: dir)
        }
        do { _ = try await task.value; XCTFail("Cancelled startup was published") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: file),before)
    }
}
