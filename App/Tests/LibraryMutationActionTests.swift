import Combine
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor final class LibraryMutationActionTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    func testPublicationStaysOnMainAndConcurrentSelectionSurvivesLargeSave() async throws {
        let root = try directory(), store = WaypointStore(directory: root)
        try store.restore(waypoints: (0..<5000).map { Waypoint(id: "p\($0)",name: "Point",lat: 24,lon: 54) },folders: [])
        let subscription = store.$waypoints.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        defer { subscription.cancel() }
        let selection = Task { @MainActor in await Task.yield(); store.select("p4999") }
        _ = try await LibraryMutationAction.apply(.favorite("p0",true),to: store)
        await selection.value
        let reopened = WaypointStore(directory: root)
        XCTAssertTrue(reopened.waypoints[0].favorite); XCTAssertEqual(reopened.selectedId,"p4999")
    }
    func testPartialBatchRetryNeverSwapsCompletedWaypointsTwice() async throws {
        let root = try directory(), store = WaypointStore(directory: root), field = FieldDataStore(directory: root)
        let point = store.add(.init(name: "Point",lat: 24,lon: 54))
        try field.saveGraphic(.init(id: "g",name: "Line",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 25,lon: 55)]))
        let file = root.appendingPathComponent("field-data-v1.zip")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        var selection = LibrarySelection(); selection.waypoints = [point.id]; selection.graphics = ["g"]
        let partial = await LibraryMutationAction.batch(selection,action: .swapVisibility,waypoints: store,field: field)
        XCTAssertNotNil(partial.failure); XCTAssertEqual(partial.completed,1)
        XCTAssertTrue(partial.remaining.waypoints.isEmpty); XCTAssertEqual(partial.remaining.graphics,["g"])
        XCTAssertFalse(store.waypoints[0].visible); XCTAssertTrue(field.document.graphics[0].visible)
        try FileManager.default.removeItem(at: file)
        let retry = await LibraryMutationAction.batch(partial.remaining,action: .swapVisibility,waypoints: store,field: field)
        XCTAssertNil(retry.failure); XCTAssertEqual(retry.remaining.count,0)
        XCTAssertFalse(store.waypoints[0].visible); XCTAssertFalse(field.document.graphics[0].visible)
        XCTAssertFalse(WaypointStore(directory: root).waypoints[0].visible)
        XCTAssertFalse(FieldDataStore(directory: root).document.graphics[0].visible)
    }
}
