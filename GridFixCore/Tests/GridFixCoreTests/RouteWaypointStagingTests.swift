import XCTest
@testable import GridFixCore

final class RouteWaypointStagingTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private let points = [GeoPoint(lat: 24,lon: 54),GeoPoint(lat: 25,lon: 55)]
    func testNoEarlyPublicationFailedRetryAndRebaseKeepStableOwnerIdsAndSelection() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let target = store.add(.init(name: "Manual route WP 1",lat: 24,lon: 54)); store.select(target.id)
        let edit = WaypointStore.RouteEdit(routeID: "r",name: "Route",points: points,folder: "Recon",now: 123)
        let initial = try store.restoreSnapshot().prepareRoute(edit)
        XCTAssertEqual(store.waypoints.count,1); XCTAssertEqual(WaypointStore(directory: root).waypoints.count,1)
        try store.setFavorite(id: target.id,favorite: true)
        XCTAssertFalse(try store.publishBatch(initial))
        let blocked = root.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: blocked); try FileManager.default.createDirectory(at: blocked,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publishBatch(store.restoreSnapshot().prepareRoute(edit)))
        XCTAssertEqual(store.waypoints.count,1); XCTAssertEqual(store.selectedId,target.id)
        try FileManager.default.removeItem(at: blocked)
        XCTAssertTrue(try store.publishBatch(store.restoreSnapshot().prepareRoute(edit)))
        let ids = store.waypoints.filter { $0.sourceRouteId == "r" }.map(\.id)
        XCTAssertEqual(ids.count,2); XCTAssertTrue(store.waypoints.first { $0.id == target.id }!.favorite)
        XCTAssertTrue(try store.publishBatch(store.restoreSnapshot().prepareRoute(edit)))
        XCTAssertEqual(store.waypoints.filter { $0.sourceRouteId == "r" }.map(\.id),ids)
        XCTAssertEqual(store.waypoints.filter { $0.sourceRouteId == "r" }.map(\.createdAt),[123,123])
        XCTAssertEqual(WaypointStore(directory: root).selectedId,target.id)
    }
    func testSelectedLegacyDuplicateRemainsOwnerAndOtherDuplicatesBecomeStandalone() throws {
        let store = WaypointStore(directory: try directory())
        let first = Waypoint(id: "first",name: "First",lat: 24,lon: 54,sourceRouteId: "r",sourceRoutePointIndex: 0)
        let chosen = Waypoint(id: "chosen",name: "Chosen",lat: 24,lon: 54,sourceRouteId: "r",sourceRoutePointIndex: 0,favorite: true)
        store.replaceAll(waypoints: [first,chosen],folders: []); store.select(chosen.id)
        let edit = WaypointStore.RouteEdit(routeID: "r",name: "Renamed",points: points,folder: "Base")
        XCTAssertTrue(try store.publishBatch(store.restoreSnapshot().prepareRoute(edit)))
        XCTAssertEqual(store.selectedId,chosen.id)
        XCTAssertEqual(store.waypoints.first { $0.id == chosen.id }?.name,"Chosen")
        XCTAssertTrue(store.waypoints.first { $0.id == chosen.id }!.favorite)
        XCTAssertNil(store.waypoints.first { $0.id == first.id }?.sourceRouteId)
        XCTAssertTrue(try store.publishBatch(store.restoreSnapshot().prepareRoute(.init(routeID: "r",name: "Empty",points: [],folder: "Base"))))
        XCTAssertNil(store.selectedId); XCTAssertEqual(store.waypoints.map(\.id),[first.id])
    }
    func testInvalidAndOversizedGenerationLeavesCurrentLibraryUntouched() throws {
        let store = WaypointStore(directory: try directory())
        let target = store.add(.init(name: "Keep",lat: 24,lon: 54)); store.select(target.id)
        XCTAssertThrowsError(try store.restoreSnapshot().prepareRoute(.init(routeID: "r",name: "Bad",points: [.init(lat: .nan,lon: 54)],folder: "Base")))
        let huge = Array(repeating: GeoPoint(lat: 24,lon: 54),count: 10_000)
        XCTAssertThrowsError(try store.restoreSnapshot().prepareRoute(.init(routeID: "r",name: "Large",points: huge,folder: "Base")))
        XCTAssertEqual(store.waypoints,[target]); XCTAssertEqual(store.selectedId,target.id)
    }
}
