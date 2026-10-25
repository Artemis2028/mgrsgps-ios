import XCTest
@testable import GridFixCore

final class NavigationLaneModelTests: XCTestCase {
    private let plane = LaneLocalPlane(origin: .init(lat: 35,lon: -79))
    private func points(_ x: Double,_ end: Double = 500) -> [GeoPoint] {
        [plane.unproject(.init(x: x,y: 0)),plane.unproject(.init(x: x,y: end))]
    }
    private var back: [GeoPoint] { [plane.unproject(.init(x: -100,y: 520)),plane.unproject(.init(x: 100,y: 520))] }
    private func lane(_ id: String = "lane",scope: NavLane.Scope = .checkpoint,target: String = "cp",created: Int64 = 0) -> NavLane {
        .init(id: id,name: "Lane",left: .init(points: points(-50),label: "Bear Creek"),right: .init(points: points(50)),backstop: .init(graphicId: "pl"),scope: scope,targetId: target,createdAt: created)
    }
    private var phaseLine: Backup.Graphic { .init(id: "pl",name: "PL BLUE",type: "phase_line",points: back.map { .init(lat: $0.lat,lon: $0.lon) }) }
    func testCheckpointWinsOverNewerRouteAndHiddenLaneStillGuides() {
        var cp = lane("checkpoint"); cp.visible = false
        let route = lane("route",scope: .route,target: "route",created: 10)
        let target = Waypoint(id: "cp",name: "OBJ",lat: 35,lon: -79,sourceRouteId: "route")
        XCTAssertEqual(NavLanes.forTarget([route,cp],target: target)?.id,"checkpoint")
        var other = target; other.id = "other"
        XCTAssertEqual(NavLanes.forTarget([route,cp],target: other)?.id,"route")
        other.sourceRouteId = nil
        XCTAssertNil(NavLanes.forTarget([route,cp],target: other))
        XCTAssertNil(NavLanes.forTarget([route,cp],target: nil))
        XCTAssertEqual(NavLanes.forTarget([cp,lane("new",created: 20)],target: target)?.id,"new")
    }
    func testLinkedGraphicEditsFollowLiveAndDeletionFails() throws {
        XCTAssertEqual(try NavLanes.resolve(lane(),graphics: [phaseLine]).backstop,back)
        var moved = phaseLine
        moved.points = [-100.0,100].map { x in let p = plane.unproject(.init(x: x,y: 600)); return .init(lat: p.lat,lon: p.lon) }
        let resolved = try NavLanes.resolve(lane(),graphics: [moved])
        XCTAssertEqual(try XCTUnwrap(resolved.shape.read(plane.unproject(.init(x: 0,y: 680))).backstop),80,accuracy: 0.3)
        XCTAssertThrowsError(try NavLanes.resolve(lane(),graphics: [])) { XCTAssertEqual($0.localizedDescription,"The backstop's line is missing") }
    }
    func testNormalizationSwapsMetadataAndIsIdempotent() throws {
        var value = lane(); let original = value.left; value.left = value.right; value.right = original
        let result = try NavLanes.normalized(value,graphics: [phaseLine])
        XCTAssertTrue(result.swapped); XCTAssertEqual(result.lane.left.label,"Bear Creek")
        let again = try NavLanes.normalized(result.lane,graphics: [phaseLine])
        XCTAssertFalse(again.swapped); XCTAssertEqual(again.lane,result.lane)
    }
    func testRouteLegsUseEndpointCheckpointBeforeRouteAndSummariesExplainMissingLinks() {
        var route = phaseLine; route.id = "route"; route.type = "route"
        route.points.append(route.points[0]); route.points.append(route.points[1])
        let routeLane = lane("r",scope: .route,target: "route")
        var checkpointLane = lane("c",target: "cp2"); checkpointLane.left.label = "fence"
        let waypoint = Waypoint(id: "cp2",name: "CP2",lat: 35,lon: -79,sourceRouteId: "route",sourceRoutePointIndex: 2)
        let routeText = "L: Bear Creek · R: right limit · BS: PL BLUE"
        XCTAssertEqual(NavLanes.legLimits(route: route,lanes: [routeLane,checkpointLane],waypoints: [waypoint],graphics: [phaseLine]),[routeText,"L: fence · R: right limit · BS: PL BLUE",routeText])
        XCTAssertEqual(NavLanes.legLimits(route: route,lanes: [routeLane],waypoints: [],graphics: [phaseLine]),Array(repeating: routeText,count: 3))
        XCTAssertEqual(NavLanes.legLimits(route: route,lanes: [],waypoints: [],graphics: []),[nil,nil,nil])
        XCTAssertTrue(NavLanes.limitsSummary(routeLane,graphics: []).contains("backstop (line deleted)"))
    }
    func testOnlyEditableLinesCanBeNewLinkedLimits() {
        XCTAssertTrue(NavLanes.canBeLimit(phaseLine))
        var g = phaseLine; g.type = "route"; XCTAssertTrue(NavLanes.canBeLimit(g))
        for type in ["objective","ring","checkpoint","sector","roadblock"] { g.type = type; XCTAssertFalse(NavLanes.canBeLimit(g),type) }
        g.type = "phase_line"; g.points = []; XCTAssertFalse(NavLanes.canBeLimit(g))
    }
    func testAndroidJSONWireFormatDefaultsAndRoundTrip() throws {
        var value = lane(); value.folder = "Night nav"; value.visible = false
        let encoded = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String:Any])
        let left = try XCTUnwrap(object["left"] as? [String:Any])
        XCTAssertEqual((left["points"] as? [[Double]])?.first,[value.left.points[0].lat,value.left.points[0].lon])
        XCTAssertEqual(object["scope"] as? String,"checkpoint")
        XCTAssertTrue(left["graphicId"] is NSNull)
        XCTAssertEqual(try JSONDecoder().decode(NavLane.self,from: encoded),value)
        let raw = #"{"id":"android","scope":"route","targetId":"r","left":{"points":[[35,-79],[35.01,-79]]},"right":{"graphicId":"line"},"backstop":{"points":[[35.01,-79],[35.01,-78.99]]}}"#
        let decoded = try JSONDecoder().decode(NavLane.self,from: Data(raw.utf8))
        XCTAssertEqual(decoded.folder,Folders.defaultFolder); XCTAssertTrue(decoded.visible)
        XCTAssertEqual(decoded.right.graphicId,"line"); XCTAssertEqual(decoded.name,"")
    }
    func testMalformedLaneDataIsRejectedBeforeItCanBeUsed() throws {
        let data = try JSONEncoder().encode(lane())
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
        func rejects(_ mutate: (inout [String:Any]) -> Void) throws {
            var object = original; mutate(&object)
            XCTAssertThrowsError(try JSONDecoder().decode(NavLane.self,from: JSONSerialization.data(withJSONObject: object)))
        }
        try rejects { $0["id"] = " " }
        try rejects { $0["id"] = String(repeating: "x",count: 65) }
        try rejects { $0["targetId"] = "" }
        try rejects { $0["scope"] = "corridor" }
        try rejects { $0["right"] = ["points": []] }
        try rejects { $0["right"] = ["points": [[91,0],[35,0]]] }
        try rejects { $0["right"] = ["points": [[35],[35,0]]] }
        try rejects { $0["right"] = ["points": Array(repeating: [35,0],count: 501)] }
    }
}
