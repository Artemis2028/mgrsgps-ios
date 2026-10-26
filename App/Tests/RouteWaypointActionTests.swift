import Combine
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor final class RouteWaypointActionTests: XCTestCase {
    private func fixture() throws -> (URL,WaypointStore,FieldDataStore,Backup.Graphic) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = WaypointStore(directory: root), field = FieldDataStore(directory: root)
        let point = store.add(.init(name: "Selected",lat: 24,lon: 54)); store.select(point.id)
        let route = Backup.Graphic(id: "r",name: "Route",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 25,lon: 55)])
        try field.saveGraphic(route)
        return (root,store,field,route)
    }
    func testFailedPublicationKeepsTargetAndRetryPublishesOnceOnMain() async throws {
        let (root,store,field,route) = try fixture(), selected = store.selectedId
        let subscription = store.$waypoints.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        defer { subscription.cancel() }
        let file = root.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        do { try await RouteWaypointAction.generate(route,to: store,field: field); XCTFail("Blocked save") } catch {}
        XCTAssertEqual(store.waypoints.count,1); XCTAssertEqual(store.selectedId,selected)
        try FileManager.default.removeItem(at: file)
        try await RouteWaypointAction.generate(route,to: store,field: field)
        let ids = store.waypoints.filter { $0.sourceRouteId == route.id }.map(\.id)
        try await RouteWaypointAction.generate(route,to: store,field: field)
        XCTAssertEqual(store.waypoints.filter { $0.sourceRouteId == route.id }.map(\.id),ids)
        XCTAssertEqual(WaypointStore(directory: root).selectedId,selected)
    }
    func testChangedSourceAtFinalValidationCannotPublishStaleVertices() async throws {
        let (_,store,field,route) = try fixture(), before = store.waypoints
        var validations = 0
        do {
            try await RouteWaypointAction.generate(route,to: store,field: field) {
                validations += 1
                if validations == 3 {
                    var changed = route; changed.points[1].lat = 26
                    try field.saveGraphic(changed)
                }
            }
            XCTFail("Changed route saved old points")
        } catch {}
        XCTAssertEqual(validations,3); XCTAssertEqual(store.waypoints,before)
    }
    func testCancellationAtPublicationCannotCreateLateWaypoints() async throws {
        let (_,store,field,route) = try fixture(), before = store.waypoints
        var validations = 0
        do {
            try await RouteWaypointAction.generate(route,to: store,field: field) {
                validations += 1
                if validations == 3 { throw CancellationError() }
            }
            XCTFail("Cancelled route saved")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(store.waypoints,before)
    }
}
