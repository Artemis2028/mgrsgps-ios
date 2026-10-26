import XCTest
@testable import GridFixCore

final class WaypointSelectionStagingTests: XCTestCase {
    private func fixture() throws -> (URL,WaypointStore,Waypoint,Waypoint) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = WaypointStore(directory: root)
        let a = store.add(.init(name: "A",lat: 24,lon: 54)), b = store.add(.init(name: "B",lat: 25,lon: 55))
        try store.selectDurably(a.id); return (root,store,a,b)
    }
    func testSelectionWaitsForPublicationAndRebasesWithoutLosingEdits() throws {
        let (root,store,a,b) = try fixture()
        let prepared = try store.restoreSnapshot().prepareSelection(b.id)
        XCTAssertEqual(store.selectedId,a.id); XCTAssertEqual(WaypointStore(directory: root).selectedId,a.id)
        try store.setFavorite(id: b.id,favorite: true)
        XCTAssertFalse(try store.publishSelection(prepared))
        XCTAssertTrue(try store.publishSelection(store.restoreSnapshot().prepareSelection(b.id)))
        XCTAssertEqual(store.selectedId,b.id); XCTAssertEqual(WaypointStore(directory: root).selectedId,b.id)
        XCTAssertTrue(WaypointStore(directory: root).waypoints.first { $0.id == b.id }!.favorite)
        try store.selectDurably(nil); XCTAssertNil(WaypointStore(directory: root).selectedId)
    }
    func testFailedSelectionKeepsOldTargetAndCanRetry() throws {
        let (root,store,a,b) = try fixture(), file = root.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.selectDurably(b.id)); XCTAssertEqual(store.selectedId,a.id)
        store.select(b.id); XCTAssertEqual(store.selectedId,a.id,"Legacy calls must also avoid phantom selection")
        try FileManager.default.removeItem(at: file); try store.selectDurably(b.id)
        XCTAssertEqual(WaypointStore(directory: root).selectedId,b.id)
    }
    func testNewerIntentRejectsOldPreparedSelectionEvenWithoutLibraryEdits() throws {
        let (root,store,a,b) = try fixture()
        store.beginSelection()
        let prepared = try store.restoreSnapshot().prepareSelection(b.id)
        store.beginSelection()
        XCTAssertThrowsError(try store.publishSelection(prepared)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(store.selectedId,a.id); XCTAssertEqual(WaypointStore(directory: root).selectedId,a.id)
    }
    func testCourseLockAndRemovedTargetsInvalidatePreparedSelections() throws {
        let (_,store,a,b) = try fixture()
        let beforeLock = try store.restoreSnapshot().prepareSelection(b.id)
        try store.setPracticeNavigationTarget(a.id,locked: true)
        XCTAssertFalse(try store.publishSelection(beforeLock))
        XCTAssertThrowsError(try store.restoreSnapshot().prepareSelection(b.id))
        XCTAssertThrowsError(try store.restoreSnapshot().prepareSelection(nil))
        XCTAssertEqual(store.selectedId,a.id)
        try store.setPracticeNavigationTarget(a.id,locked: false)
        store.delete(ids: [b.id])
        XCTAssertThrowsError(try store.restoreSnapshot().prepareSelection(b.id))
    }
}
