import XCTest
@testable import GridFixCore

final class TAKSharingTests: XCTestCase {
    private let point = Waypoint(id: "wp", name: "OP CAFÉ", lat: 35, lon: -79, folder: "Recon", affiliation: "hostile")
    private let line = Backup.Graphic(id: "line", name: "PL BLUE", type: "phase_line", points: [.init(lat: 35, lon: -79), .init(lat: 35.01, lon: -79)], folder: "Recon")
    private func current(_ waypoints: [Waypoint], _ graphics: [Backup.Graphic], shared: Set<String> = ["Recon"], visible: Bool = true, callsign: String = "IOS") -> [TAKSharing.Item] {
        TAKSharing.current(sharedFolders: shared, waypoints: waypoints, graphics: graphics, folders: [.init(name: "Recon", visible: visible)], uid: "MGRSGPS-test", callsign: callsign)
    }
    func testOptInFoldersHiddenEyesAndVisibility() {
        XCTAssertTrue(current([point], [line], shared: []).isEmpty)
        XCTAssertTrue(current([point], [line], visible: false).isEmpty)
        var hidden = point; hidden.visible = false
        XCTAssertEqual(current([hidden], [line]).map(\.uid), ["MGRSGPS-test-g-line"])
        XCTAssertEqual(current([point], [line], shared: ["recon"]).count, 2)
    }
    func testChangesDeletesOfflineStateAndResendForLateJoiners() throws {
        let before = current([point], [line]), sent = Dictionary(uniqueKeysWithValues: before.map { ($0.uid, $0.signature) })
        XCTAssertTrue(TAKSharing.plan(current: before, sent: sent, refreshAll: false).send.isEmpty)
        XCTAssertEqual(TAKSharing.plan(current: before, sent: sent, refreshAll: true).send.count, 2)
        var moved = point; moved.lat += 0.001
        let after = current([moved], [])
        let plan = TAKSharing.plan(current: after, sent: sent, refreshAll: false)
        XCTAssertEqual(plan.send.map(\.uid), ["MGRSGPS-test-wp-wp"])
        XCTAssertEqual(plan.delete, ["MGRSGPS-test-g-line"])
        XCTAssertEqual(TAKSharing.plan(current: [], sent: sent, refreshAll: false).delete.count, 2)
        XCTAssertEqual(TAKSharing.plan(current: current([point], [line], callsign: "RENAMED"), sent: sent, refreshAll: false).send.count, 2)
        XCTAssertTrue(try before[0].xml(now: Date()).contains("OP CAFÉ"))
    }
    func testPointGraphicsAreasAndUnsupportedGeometry() throws {
        var pin = line; pin.id = "pin"; pin.type = "checkpoint"; pin.points = [pin.points[0]]
        var area = line; area.id = "area"; area.type = "objective"; area.points.append(.init(lat: 35.01, lon: -79.01))
        for type in ["ring", "sector", "text"] { var excluded = area; excluded.type = type; XCTAssertTrue(current([], [excluded]).isEmpty) }
        let items = current([], [pin, area])
        XCTAssertEqual(items.count, 2); XCTAssertTrue(items[1].closed)
        guard case let .item(decoded) = TAKCoT.parse(try items[1].xml(now: Date()), ownUID: "other", now: Date()) else { return XCTFail("Missing area") }
        XCTAssertTrue(decoded.closed); XCTAssertEqual(decoded.points.count, 3)
        area.points = (0..<500).map { .init(lat: 35 + Double($0) * 0.000001, lon: -79) }
        XCTAssertTrue(current([], [area]).isEmpty, "Closing vertex counts toward wire cap")
        area.type = "route"; XCTAssertEqual(current([], [area]).count, 1)
    }
}
