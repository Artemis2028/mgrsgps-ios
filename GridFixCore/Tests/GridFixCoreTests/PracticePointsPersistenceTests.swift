import XCTest
@testable import GridFixCore

final class PracticePointsPersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    private func edit() -> WaypointStore.PracticePointsEdit {
        .init(folder: "Course TEST",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],now: 1234)
    }
    func testPreparedPointsRebasePreservesOtherEditsAndSelection() throws {
        let dir = try directory(), store = WaypointStore(directory: dir), edit = edit()
        let old = store.add(.init(name: "Existing",lat: 23,lon: 54))
        let pending = try store.restoreSnapshot().preparePracticePoints(edit)
        XCTAssertEqual(store.waypoints.count,1)
        try store.setFavorite(id: old.id,favorite: true); try store.selectDurably(old.id)
        XCTAssertNil(try store.publishPracticePoints(pending))
        let added = try XCTUnwrap(store.publishPracticePoints(store.restoreSnapshot().preparePracticePoints(edit)))
        XCTAssertEqual(added.map(\.id),edit.ids); XCTAssertEqual(added.map(\.createdAt),[1234,1234])
        let reopened = WaypointStore(directory: dir)
        XCTAssertEqual(reopened.selectedId,old.id); XCTAssertTrue(reopened.waypoints[0].favorite)
        XCTAssertEqual(reopened.waypoints.map(\.id),[old.id]+edit.ids)
    }
    func testPublishFailureRetainsLibraryAndSamePointsCanBeRetried() throws {
        let dir = try directory(), store = WaypointStore(directory: dir), edit = edit()
        let prepared = try store.restoreSnapshot().preparePracticePoints(edit)
        let path = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publishPracticePoints(prepared))
        XCTAssertTrue(store.waypoints.isEmpty); XCTAssertFalse(store.folders.contains { $0.name == "Course TEST" })
        try FileManager.default.removeItem(at: path)
        let added = try XCTUnwrap(store.publishPracticePoints(store.restoreSnapshot().preparePracticePoints(edit)))
        XCTAssertEqual(added.map(\.id),edit.ids)
        XCTAssertEqual(WaypointStore(directory: dir).waypoints,added)
    }
    func testAcknowledgedProposalIsIdempotentButNeverOverwritesEditedCheckpoint() throws {
        let store = WaypointStore(directory: try directory()), edit = edit()
        let first = try XCTUnwrap(store.publishPracticePoints(store.restoreSnapshot().preparePracticePoints(edit)))
        _ = try store.publishPracticePoints(store.restoreSnapshot().preparePracticePoints(edit))
        XCTAssertEqual(store.waypoints.count,2)
        try store.setFavorite(id: first[0].id,favorite: true)
        XCTAssertThrowsError(try store.restoreSnapshot().preparePracticePoints(edit))
        XCTAssertTrue(store.waypoints[0].favorite)
    }
    func testWrongStoreInvalidAndDamagedInputsCannotPublish() throws {
        let a = WaypointStore(directory: try directory()), b = WaypointStore(directory: try directory())
        let prepared = try a.restoreSnapshot().preparePracticePoints(edit())
        XCTAssertThrowsError(try b.publishPracticePoints(prepared)); XCTAssertTrue(b.waypoints.isEmpty)
        for points: [GeoPoint] in [[],[.init(lat: 24,lon: 54)],[.init(lat: .nan,lon: 54),.init(lat: 24,lon: 54)]] {
            XCTAssertThrowsError(try a.restoreSnapshot().preparePracticePoints(.init(folder: "Bad",points: points)))
        }
        let dir = try directory(), original = Data("SYNTHETIC damaged library".utf8)
        try original.write(to: dir.appendingPathComponent("waypoints-v1.json"))
        XCTAssertThrowsError(try WaypointStore(directory: dir).restoreSnapshot().preparePracticePoints(edit()))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("waypoints-v1.json")),original)
    }
    func testCombinedLimitCountsNewPointsOnly() throws {
        let points = (0..<9999).map { Waypoint(name: "P\($0)",lat: 24,lon: 54) }
        let store = WaypointStore.inMemory(waypoints: points)
        XCTAssertThrowsError(try store.restoreSnapshot().preparePracticePoints(edit()))
        XCTAssertEqual(store.waypoints.count,9999)
    }
}
