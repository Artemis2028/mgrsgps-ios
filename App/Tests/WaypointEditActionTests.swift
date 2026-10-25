import Combine
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor final class WaypointEditActionTests: XCTestCase {
    func testDurableSavePublishesOnMainAndFailedRetryKeepsDraftIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WaypointStore(directory: root)
        let selected = store.add(.init(name: "Selected",lat: 24,lon: 54)); store.select(selected.id)
        let subscription = store.$waypoints.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        defer { subscription.cancel() }
        let file = root.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        let edit = WaypointStore.Edit.create(id: "stable-ui",createdAt: 1,draft: .init(name: "Draft",lat: 24.1,lon: 54.1))
        do { _ = try await WaypointEditAction.save(edit,to: store); XCTFail("Blocked destination saved") } catch {}
        XCTAssertEqual(store.waypoints,[selected]); XCTAssertEqual(store.selectedId,selected.id)
        try FileManager.default.removeItem(at: file)
        let saved = try await WaypointEditAction.save(edit,to: store)
        XCTAssertEqual(saved.id,"stable-ui"); XCTAssertEqual(store.selectedId,selected.id)
        XCTAssertEqual(WaypointStore(directory: root).waypoints,store.waypoints)
        _ = try await WaypointEditAction.save(edit,to: store); XCTAssertEqual(store.waypoints.count,2)
    }
    func testPreparationAllowsConcurrentSelectionAndAddsWithoutLosingEither() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WaypointStore(directory: root)
        let points = (0..<5000).map { Waypoint(id: "p\($0)",name: "Point \($0)",lat: 24,lon: 54) }
        try store.restore(waypoints: points,folders: [])
        let selection = Task { @MainActor in await Task.yield(); store.select("p4999") }
        let saved = try await WaypointEditAction.save(.create(id: "new",createdAt: 1,draft: .init(name: "New",lat: 24.1,lon: 54.1)),to: store)
        await selection.value
        XCTAssertEqual(saved.id,"new"); XCTAssertEqual(store.selectedId,"p4999")
        let reopened = WaypointStore(directory: root)
        XCTAssertEqual(reopened.waypoints.count,5001); XCTAssertEqual(reopened.selectedId,"p4999")
    }
}
