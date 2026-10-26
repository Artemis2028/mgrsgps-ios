import XCTest
@testable import GridFixCore

final class PracticeTargetPersistenceTests: XCTestCase {
    private func fixture() throws -> (URL,WaypointStore,Waypoint,Waypoint) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WaypointStore(directory: dir)
        let a = store.add(.init(name: "A",lat: 24,lon: 54)), b = store.add(.init(name: "B",lat: 24.01,lon: 54))
        try store.selectDurably(a.id); return (dir,store,a,b)
    }
    func testGateClosesBeforePreparationAndAcknowledgesOnlyAfterPublication() throws {
        let (dir,store,a,b) = try fixture()
        let request = try XCTUnwrap(store.beginPracticeSelection(b.id,locked: true))
        XCTAssertTrue(store.practiceNavigationLocked); XCTAssertTrue(store.practiceNavigationSavePending)
        XCTAssertEqual(store.selectedId,b.id); XCTAssertEqual(WaypointStore(directory: dir).selectedId,a.id)
        XCTAssertThrowsError(try store.restoreSnapshot().prepareSelection(b.id))
        XCTAssertThrowsError(try store.restoreSnapshot().prepareSelection(a.id))
        let prepared = try store.restoreSnapshot().preparePracticeSelection(request)
        XCTAssertTrue(try store.publishPracticeSelection(prepared))
        XCTAssertFalse(store.practiceNavigationSavePending); XCTAssertEqual(WaypointStore(directory: dir).selectedId,b.id)
        XCTAssertNil(store.beginPracticeSelection(b.id,locked: true))
    }
    func testRevisionRebasePreservesConcurrentLibraryEdits() throws {
        let (dir,store,a,b) = try fixture()
        let request = try XCTUnwrap(store.beginPracticeSelection(b.id,locked: true))
        let old = try store.restoreSnapshot().preparePracticeSelection(request)
        try store.setFavorite(id: a.id,favorite: true)
        XCTAssertFalse(try store.publishPracticeSelection(old)); XCTAssertTrue(store.practiceNavigationSavePending)
        XCTAssertTrue(try store.publishPracticeSelection(store.restoreSnapshot().preparePracticeSelection(request)))
        let reopened = WaypointStore(directory: dir)
        XCTAssertTrue(reopened.waypoints[0].favorite); XCTAssertEqual(reopened.selectedId,b.id)
    }
    func testNewerOwnerCancelsOldTargetAndUnlockDoesNotPermitEarlyOrdinaryChoice() throws {
        let (_,store,a,b) = try fixture()
        let first = try XCTUnwrap(store.beginPracticeSelection(b.id,locked: true))
        let old = try store.restoreSnapshot().preparePracticeSelection(first)
        let end = try XCTUnwrap(store.beginPracticeSelection(b.id,locked: false))
        XCTAssertFalse(store.practiceNavigationLocked); XCTAssertTrue(store.practiceNavigationSavePending)
        XCTAssertThrowsError(try store.selectDurably(a.id))
        XCTAssertThrowsError(try store.publishPracticeSelection(old)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(try store.publishPracticeSelection(store.restoreSnapshot().preparePracticeSelection(end)))
        try store.selectDurably(a.id)
        XCTAssertThrowsError(try store.publishPracticeSelection(old)); XCTAssertEqual(store.selectedId,a.id)
    }
    func testDeletedTargetCannotPublishOldSnapshotAndNewNilOwnerRemainsLocked() throws {
        let (dir,store,_,b) = try fixture()
        let first = try XCTUnwrap(store.beginPracticeSelection(b.id,locked: true))
        let old = try store.restoreSnapshot().preparePracticeSelection(first)
        store.delete(ids: [b.id])
        XCTAssertFalse(try store.publishPracticeSelection(old))
        XCTAssertThrowsError(try store.restoreSnapshot().preparePracticeSelection(first))
        let clear = try XCTUnwrap(store.beginPracticeSelection(nil,locked: true))
        XCTAssertTrue(try store.publishPracticeSelection(store.restoreSnapshot().preparePracticeSelection(clear)))
        XCTAssertTrue(store.practiceNavigationLocked); XCTAssertNil(WaypointStore(directory: dir).selectedId)
    }
    func testFailedPublishRetainsPendingGateAndRetryAcknowledgesActualDiskWrite() throws {
        let (dir,store,_,b) = try fixture()
        let request = try XCTUnwrap(store.beginPracticeSelection(b.id,locked: true))
        let pending = try store.restoreSnapshot().preparePracticeSelection(request)
        let path = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publishPracticeSelection(pending))
        XCTAssertTrue(store.practiceNavigationSavePending); XCTAssertTrue(store.practiceNavigationLocked)
        try FileManager.default.removeItem(at: path)
        let retry = try XCTUnwrap(store.beginPracticeSelection(b.id,locked: true))
        XCTAssertTrue(try store.publishPracticeSelection(store.restoreSnapshot().preparePracticeSelection(retry)))
        XCTAssertFalse(store.practiceNavigationSavePending); XCTAssertEqual(WaypointStore(directory: dir).selectedId,b.id)
    }
    func testWrongStoreCannotAcknowledgeOrOverwriteSelection() throws {
        let (_,store,_,b) = try fixture(), (_,other,a,_) = try fixture()
        let request = try XCTUnwrap(store.beginPracticeSelection(b.id,locked: true))
        let pending = try store.restoreSnapshot().preparePracticeSelection(request)
        XCTAssertThrowsError(try other.publishPracticeSelection(pending))
        XCTAssertEqual(other.selectedId,a.id); XCTAssertTrue(store.practiceNavigationSavePending)
    }
}
