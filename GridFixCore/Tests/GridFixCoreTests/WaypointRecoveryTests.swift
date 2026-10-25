import XCTest
@testable import GridFixCore

final class WaypointRecoveryTests: XCTestCase {
    private func fixture() throws -> (URL, URL, Data, WaypointStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path); try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("waypoints-v1.json")
        let original = Data("Unreadable CAFÉ waypoint file\n".utf8) + Data(repeating: 0xFF, count: 200_000)
        try original.write(to: file)
        return (root, file, original, WaypointStore(directory: root))
    }
    func testPreservingDoesNotResetAndFreshLibraryKeepsExactOriginalAcrossRelaunch() throws {
        let (root, file, original, store) = try fixture()
        XCTAssertNotNil(store.loadError)
        let copy = try store.recoverySnapshot().preserveOriginal()
        XCTAssertEqual(try Data(contentsOf: copy), original); XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertNotNil(store.loadError)
        let prepared = try store.recoverySnapshot().prepareFreshLibrary()
        XCTAssertEqual(try Data(contentsOf: prepared.original), original)
        _ = try store.publishRecovery(prepared)
        XCTAssertNil(store.loadError); XCTAssertTrue(store.waypoints.isEmpty); XCTAssertNil(store.selectedId)
        let reopened = WaypointStore(directory: root)
        XCTAssertNil(reopened.loadError); XCTAssertEqual(try reopened.recoveryFiles().count, 2)
        for url in try reopened.recoveryFiles() { XCTAssertEqual(try Data(contentsOf: url), original) }
        _ = reopened.add(.init(name: "After recovery", lat: 24.4539, lon: 54.3773))
        XCTAssertEqual(WaypointStore(directory: root).waypoints.first?.name, "After recovery")
    }
    func testRetryLoadsExternallyRepairedFileWithoutRewritingIt() throws {
        let (root, file, _, store) = try fixture()
        let other = root.appendingPathComponent("repaired", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let repaired = WaypointStore(directory: other)
        let point = repaired.add(.init(name: "Repaired CAFÉ", lat: 24.4539, lon: 54.3773))
        let bytes = try Data(contentsOf: other.appendingPathComponent("waypoints-v1.json"))
        try bytes.write(to: file, options: .atomic)
        let reload = try store.recoverySnapshot().prepareReload()
        XCTAssertTrue(try store.publishReload(reload))
        XCTAssertNil(store.loadError); XCTAssertEqual(store.waypoints.first?.id, point.id)
        XCTAssertEqual(try Data(contentsOf: file), bytes); XCTAssertTrue(try store.recoveryFiles().isEmpty)
    }
    func testChangedSourceOrRevisionCannotBeReplacedByPreparedEmptyLibrary() throws {
        let (_, file, original, store) = try fixture()
        let prepared = try store.recoverySnapshot().prepareFreshLibrary()
        let changed = Data("Externally changed file".utf8)
        try changed.write(to: file, options: .atomic)
        XCTAssertThrowsError(try store.publishRecovery(prepared))
        XCTAssertEqual(try Data(contentsOf: file), changed)
        XCTAssertEqual(try Data(contentsOf: prepared.original), original)
        try original.write(to: file, options: .atomic)
        let second = try store.recoverySnapshot().prepareFreshLibrary()
        _ = store.add(.init(name: "Unsaved legacy change", lat: 24, lon: 54))
        XCTAssertThrowsError(try store.publishRecovery(second))
        XCTAssertEqual(try Data(contentsOf: file), original); XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.waypoints.first?.name, "Unsaved legacy change")
    }
    func testDirectoryAndSymlinkAreNotArchivedOrReplaced() throws {
        let (root, file, original, _) = try fixture()
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let directory = WaypointStore(directory: root)
        XCTAssertThrowsError(try directory.recoverySnapshot().prepareFreshLibrary())
        try FileManager.default.removeItem(at: file)
        let target = root.appendingPathComponent("outside.json"); try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        let linked = WaypointStore(directory: root)
        XCTAssertThrowsError(try linked.recoverySnapshot().prepareFreshLibrary())
        XCTAssertThrowsError(try linked.recoverySnapshot().prepareReload())
        XCTAssertEqual(try Data(contentsOf: target), original)
    }
    func testPublishFailureLeavesOriginalAndPreservedCopyThenRetrySucceeds() throws {
        let (root, file, original, store) = try fixture()
        let prepared = try store.recoverySnapshot().prepareFreshLibrary()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        XCTAssertThrowsError(try store.publishRecovery(prepared))
        XCTAssertNotNil(store.loadError); XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try Data(contentsOf: prepared.original), original)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        _ = try store.publishRecovery(store.recoverySnapshot().prepareFreshLibrary())
        XCTAssertNil(WaypointStore(directory: root).loadError)
    }
    func testCancelledPreparationAndForeignStoreCannotResetLibrary() async throws {
        let (_, file, original, store) = try fixture()
        let snapshot = try store.recoverySnapshot()
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try snapshot.prepareFreshLibrary()
        }
        do { _ = try await task.value; XCTFail("Cancelled preparation was accepted") } catch is CancellationError {} 
        let (_, _, _, foreign) = try fixture()
        let prepared = try snapshot.prepareFreshLibrary()
        XCTAssertThrowsError(try foreign.publishRecovery(prepared))
        XCTAssertEqual(try Data(contentsOf: file), original); XCTAssertNotNil(store.loadError)
    }
}
