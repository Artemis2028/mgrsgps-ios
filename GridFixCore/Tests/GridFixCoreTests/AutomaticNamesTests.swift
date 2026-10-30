import XCTest
@testable import GridFixCore

@MainActor
final class AutomaticNamesTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testBlankWaypointsAdvancePastExistingNamesAndKeepCustomNames() throws {
        let url = try directory(), store = WaypointStore(directory: url)
        _ = store.add(.init(name: "WP7", lat: 24, lon: 54))
        let auto = store.add(.init(name: "  ", lat: 24, lon: 54))
        XCTAssertEqual(auto.name, "WP8")
        let custom = store.add(.init(name: "Gate", lat: 24, lon: 54))
        XCTAssertEqual(custom.name, "Gate")
        XCTAssertEqual(WaypointStore(directory: url).waypoints.last?.name, "Gate")
        XCTAssertEqual(AutomaticNames.next(prefix: "WP", among: ["WP1", "WP\(Int.max)"]), "WP2")
    }
    func testConcurrentSuggestionsRebaseBeforePublishingTheNextNumber() throws {
        let store = WaypointStore(directory: try directory())
        let first = WaypointStore.Edit.create(id: "one", createdAt: 1, draft: .init(name: "", lat: 24, lon: 54))
        let second = WaypointStore.Edit.create(id: "two", createdAt: 2, draft: .init(name: "", lat: 24, lon: 54))
        let snapshot = store.restoreSnapshot()
        let preparedFirst = try snapshot.prepare(edit: first)
        let preparedSecond = try snapshot.prepare(edit: second)
        XCTAssertEqual(try store.publishEdit(preparedFirst)?.name, "WP1")
        XCTAssertNil(try store.publishEdit(preparedSecond))
        XCTAssertEqual(try store.publishEdit(store.restoreSnapshot().prepare(edit: second))?.name, "WP2")
        XCTAssertEqual(Set(store.waypoints.map(\.name)).count, 2)
    }
    func testMilitaryAffiliationsFunctionsAndOptionalEchelons() {
        for (affiliation,prefix) in [("hostile","EN"),("friendly","FRN"),("unknown","UNK"),("neutral","NTRL")] {
            let draft = WaypointDraft(name: "", lat: 24, lon: 54, symbol: "nato_h_inf", affiliation: affiliation, echelon: "plt", kind: KIND_UNIT)
            XCTAssertEqual(AutomaticNames.waypoint(draft, among: []), prefix + "-INF-PLT-1")
        }
        let draft = WaypointDraft(name: "", lat: 24, lon: 54, symbol: "nato_h_mechinf", kind: KIND_UNIT)
        let first = Waypoint(name: "EN-MECHINF-1", lat: 24, lon: 54)
        XCTAssertEqual(AutomaticNames.waypoint(draft, among: [first]), "EN-MECHINF-2")
    }
    func testPreparedBlankCreationPublishesOnlyAfterConfirmationAndSurvivesReload() throws {
        let url = try directory(), store = WaypointStore(directory: url)
        let prepared = try store.restoreSnapshot().prepare(edit: .create(id: "new", createdAt: 100, draft: .init(name: "", lat: 24, lon: 54)))
        XCTAssertTrue(store.waypoints.isEmpty)
        XCTAssertEqual(try store.publishEdit(prepared)?.name, "WP1")
        XCTAssertEqual(WaypointStore(directory: url).waypoints.first?.name, "WP1")
    }
    func testRouteNamesRemainStableAndUserRenamesSurviveRegeneration() throws {
        let store = WaypointStore(directory: try directory())
        let points = [GeoPoint(lat: 24, lon: 54), GeoPoint(lat: 25, lon: 55)]
        try store.replaceRouteWaypoints(routeID: "r", name: "Patrol", points: points, folder: "Base")
        XCTAssertEqual(store.waypoints.map(\.name), ["RT1WP1", "RT1WP2"])
        let first = store.waypoints[0]
        store.update(id: first.id, draft: .init(name: "Checkpoint Alpha", lat: first.lat, lon: first.lon))
        try store.replaceRouteWaypoints(routeID: "r", name: "Renamed", points: points, folder: "Base")
        XCTAssertEqual(store.waypoints.map(\.name), ["Checkpoint Alpha", "RT1WP2"])
        try store.replaceRouteWaypoints(routeID: "s", name: "Another", points: points, folder: "Base")
        XCTAssertEqual(store.waypoints.suffix(2).map(\.name), ["RT2WP1", "RT2WP2"])
        XCTAssertEqual(store.waypoints.first?.id, first.id)
    }
    func testBlankGraphicsGetNumberedNamesWithoutWeakeningGeometryValidation() throws {
        let store = FieldDataStore(directory: try directory())
        var first = GraphicDraft(type: "route")
        XCTAssertNotNil(first.validationMessage)
        first.append(.init(lat: 24, lon: 54)); first.append(.init(lat: 25, lon: 55))
        XCTAssertNil(first.validationMessage)
        try store.saveGraphic(first.saved)
        var second = GraphicDraft(type: "route")
        second.append(.init(lat: 24, lon: 54)); second.append(.init(lat: 25, lon: 55))
        try store.saveGraphic(second.saved)
        XCTAssertEqual(store.document.graphics.map(\.name), ["RT1", "RT2"])
    }
}
