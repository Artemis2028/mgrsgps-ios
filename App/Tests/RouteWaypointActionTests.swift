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
    func testSelectionCancellationAtPublicationCannotSwitchTarget() async throws {
        let (root,store,_,_) = try fixture(), before = store.selectedId
        let next = store.add(.init(name: "Next",lat: 25,lon: 55))
        var validations = 0
        do {
            try await WaypointEditAction.select(next.id,in: store) {
                validations += 1
                if validations == 2 { throw CancellationError() }
            }
            XCTFail("Cancelled selection published")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(store.selectedId,before); XCTAssertEqual(WaypointStore(directory: root).selectedId,before)
    }
    func testNewerSelectionCannotBeOverwrittenByOlderPreparedTarget() async throws {
        let (root,store,_,_) = try fixture()
        let older = store.add(.init(name: "Older",lat: 25,lon: 55)), newer = store.add(.init(name: "Newer",lat: 26,lon: 56))
        var validations = 0
        do {
            try await WaypointEditAction.select(older.id,in: store) {
                validations += 1
                if validations == 2 { try store.selectDurably(newer.id) }
            }
            XCTFail("An older selection replaced a newer one")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(store.selectedId,newer.id); XCTAssertEqual(WaypointStore(directory: root).selectedId,newer.id)
    }
    func testSelectionRebasesConcurrentEditAndPublishesOnMain() async throws {
        let (root,store,_,_) = try fixture(), next = store.add(.init(name: "Next",lat: 25,lon: 55))
        var validations = 0, libraryPublications = 0
        let library = store.$waypoints.dropFirst().sink { _ in libraryPublications += 1 }
        defer { library.cancel() }
        let subscription = store.$selectedId.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        defer { subscription.cancel() }
        try await WaypointEditAction.select(next.id,in: store) {
            validations += 1
            if validations == 2 { try store.setFavorite(id: next.id,favorite: true) }
        }
        XCTAssertEqual(validations,4); XCTAssertEqual(libraryPublications,1,"Only the concurrent favourite edit changes library contents")
        XCTAssertEqual(WaypointStore(directory: root).selectedId,next.id)
        #if !targetEnvironment(simulator)
        // Simulator does not expose the data-protection attribute. This is an
        // additional device assertion, not evidence of physical lock behavior.
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("waypoints-v1.json").path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType,.completeUntilFirstUserAuthentication)
        #endif
        XCTAssertTrue(store.waypoints.first { $0.id == next.id }!.favorite)
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
