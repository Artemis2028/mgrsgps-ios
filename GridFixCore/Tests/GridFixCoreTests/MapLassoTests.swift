import XCTest
@testable import GridFixCore

final class MapLassoTests: XCTestCase {
    private let square: [MapLasso.Point] = [.init(x: 0,y: 0),.init(x: 10,y: 0),.init(x: 10,y: 10),.init(x: 0,y: 10)]
    func testImplicitClosureConcavityEvenOddAndDegenerateLoops() {
        XCTAssertTrue(MapLasso.contains(.init(x: 5,y: 5),in: square))
        XCTAssertTrue(MapLasso.contains(.init(x: 5,y: 5),in: square.reversed()))
        XCTAssertFalse(MapLasso.contains(.init(x: 11,y: 5),in: square))
        XCTAssertFalse(MapLasso.contains(.init(x: 5,y: 5),in: Array(square.prefix(2))))
        XCTAssertFalse(MapLasso.contains(.init(x: 5,y: 0),in: [.init(x: 0,y: 0),.init(x: 5,y: 0),.init(x: 10,y: 0)]))
        XCTAssertFalse(MapLasso.contains(.init(x: .nan,y: 5),in: square))
        XCTAssertFalse(MapLasso.contains(.init(x: 5,y: 5),in: square + [.init(x: .infinity,y: 0)]))
        // Twice around has even winding and therefore selects nothing.
        XCTAssertFalse(MapLasso.contains(.init(x: 5,y: 5),in: square+square))
        let concave: [MapLasso.Point] = [.init(x: 0,y: 0),.init(x: 10,y: 0),.init(x: 10,y: 3),.init(x: 3,y: 3),.init(x: 3,y: 10),.init(x: 0,y: 10)]
        XCTAssertTrue(MapLasso.contains(.init(x: 2,y: 8),in: concave))
        XCTAssertFalse(MapLasso.contains(.init(x: 8,y: 8),in: concave))
    }
    func testOnlyVisibleLocalPointsAndGraphicsWithAnInsideVertexParticipate() {
        var hidden = Waypoint(id: "hidden",name: "Hidden",lat: 5,lon: 5); hidden.visible = false
        let points = [Waypoint(id: "local",name: "Local",lat: 5,lon: 5),hidden,
                      Waypoint(id: "folder",name: "Folder",lat: 5,lon: 5,folder: "Recon"),
                      Waypoint(id: "tak:remote",name: "Remote",lat: 5,lon: 5),
                      Waypoint(id: "outside",name: "Outside",lat: 12,lon: 12)]
        let graphics: [Backup.Graphic] = [
            .init(id: "vertex",name: "vertex",type: "phase_line",points: [.init(lat: 5,lon: 5),.init(lat: 15,lon: 15)]),
            .init(id: "crossing",name: "crossing",type: "phase_line",points: [.init(lat: 5,lon: -5),.init(lat: 5,lon: 15)]),
            .init(id: "hidden",name: "hidden",type: "checkpoint",points: [.init(lat: 5,lon: 5)],visible: false),
            .init(id: "folder",name: "folder",type: "checkpoint",points: [.init(lat: 5,lon: 5)],folder: "RECON")]
        let result = MapLasso.select(loop: square,waypoints: points,graphics: graphics,folders: [.init(name: "Recon",visible: false)]) {
            .init(x: $0.lon,y: $0.lat)
        }
        XCTAssertEqual(result.waypoints,["local"]); XCTAssertEqual(result.graphics,["vertex"]); XCTAssertTrue(result.tracks.isEmpty)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testBatchStagingRebasesConcurrentVisibilityAndSelectionAndHideNeverToggles() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let a = store.add(.init(name: "A",lat: 1,lon: 1)), b = store.add(.init(name: "B",lat: 2,lon: 2))
        store.select(a.id)
        let stale = try store.restoreSnapshot().prepareBatch(ids: [a.id],action: .hide)
        XCTAssertTrue(store.waypoints[0].visible)
        store.setVisible(id: a.id,visible: false); store.select(b.id)
        XCTAssertFalse(try store.publishBatch(stale))
        XCTAssertTrue(try store.publishBatch(store.restoreSnapshot().prepareBatch(ids: [a.id],action: .hide)))
        XCTAssertFalse(store.waypoints[0].visible); XCTAssertTrue(store.waypoints[1].visible)
        XCTAssertEqual(WaypointStore(directory: root).selectedId,b.id)
        XCTAssertTrue(try store.publishBatch(store.restoreSnapshot().prepareBatch(ids: [a.id],action: .hide)))
        XCTAssertFalse(store.waypoints[0].visible)
        XCTAssertTrue(try store.publishBatch(store.restoreSnapshot().prepareBatch(ids: [b.id],action: .delete)))
        XCTAssertNil(store.selectedId); XCTAssertEqual(WaypointStore(directory: root).waypoints.map(\.id),[a.id])
    }
    func testFailedOrForeignBatchDoesNotPublishAndUnreadableOriginalIsKept() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let a = store.add(.init(name: "A",lat: 1,lon: 1)), other = WaypointStore(directory: try directory())
        let prepared = try store.restoreSnapshot().prepareBatch(ids: [a.id],action: .delete)
        XCTAssertThrowsError(try other.publishBatch(prepared))
        let file = root.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publishBatch(prepared)); XCTAssertEqual(store.waypoints.map(\.id),[a.id])
        try FileManager.default.removeItem(at: file)
        let original = Data("unreadable".utf8); try original.write(to: file)
        XCTAssertThrowsError(try WaypointStore(directory: root).restoreSnapshot().prepareBatch(ids: [a.id],action: .hide))
        XCTAssertEqual(try Data(contentsOf: file),original)
    }
}
