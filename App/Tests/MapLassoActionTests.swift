import Combine
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class MapLassoActionTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testPartialHideReportsOnlyRemainingIDsAndRetryCannotReshowPoints() async throws {
        let root = try directory(), points = WaypointStore(directory: root), field = FieldDataStore(directory: root)
        let a = points.add(.init(name: "A",lat: 1,lon: 1)), b = points.add(.init(name: "B",lat: 2,lon: 2))
        try field.saveGraphic(.init(id: "g",name: "g",type: "phase_line",points: [.init(lat: 1,lon: 1),.init(lat: 2,lon: 2)]))
        let file = root.appendingPathComponent("field-data-v1.zip")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        var selection = LibrarySelection(); selection.waypoints = [a.id]; selection.graphics = ["g"]; selection.tracks = ["not-in-scope"]
        let publication = points.$waypoints.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        let partial = await MapLassoAction.apply(selection,action: .hide,waypoints: points,field: field)
        XCTAssertEqual(partial.completed,1); XCTAssertNotNil(partial.error)
        XCTAssertTrue(partial.remaining.waypoints.isEmpty); XCTAssertEqual(partial.remaining.graphics,["g"]); XCTAssertTrue(partial.remaining.tracks.isEmpty)
        XCTAssertFalse(points.waypoints[0].visible); XCTAssertTrue(points.waypoints[1].visible)
        XCTAssertFalse(WaypointStore(directory: root).waypoints[0].visible)
        try FileManager.default.removeItem(at: file)
        let result = await MapLassoAction.apply(partial.remaining,action: .hide,waypoints: points,field: field)
        XCTAssertNil(result.error); XCTAssertEqual(result.completed,1)
        XCTAssertFalse(points.waypoints[0].visible); XCTAssertFalse(FieldDataStore(directory: root).document.graphics[0].visible)
        XCTAssertTrue(points.waypoints.contains { $0.id == b.id }); publication.cancel()
    }
    func testDeletePreservesUnselectedRecordsAndFailureDoesNotContinueToGraphics() async throws {
        let root = try directory(), points = WaypointStore(directory: root), field = FieldDataStore(directory: root)
        let a = points.add(.init(name: "A",lat: 1,lon: 1)), b = points.add(.init(name: "B",lat: 2,lon: 2)); points.select(a.id)
        try field.saveGraphic(.init(id: "g",name: "g",type: "checkpoint",points: [.init(lat: 1,lon: 1)]))
        var selection = LibrarySelection(); selection.waypoints = [a.id]; selection.graphics = ["g"]
        let file = root.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        let failed = await MapLassoAction.apply(selection,action: .delete,waypoints: points,field: field)
        XCTAssertEqual(failed.remaining,selection); XCTAssertEqual(failed.completed,0); XCTAssertEqual(field.document.graphics.count,1)
        try FileManager.default.removeItem(at: file)
        let saved = await MapLassoAction.apply(failed.remaining,action: .delete,waypoints: points,field: field)
        XCTAssertNil(saved.error); XCTAssertEqual(saved.completed,2)
        XCTAssertEqual(WaypointStore(directory: root).waypoints.map(\.id),[b.id]); XCTAssertNil(points.selectedId)
        XCTAssertTrue(FieldDataStore(directory: root).document.graphics.isEmpty)
    }
}
