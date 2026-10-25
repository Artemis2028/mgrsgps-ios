import XCTest
@testable import GridFixCore

final class WatchLaneOverlayTests: XCTestCase {
    private func lane() -> NavLane {
        let plane=LaneLocalPlane(origin: .init(lat: 24,lon: 54))
        func p(_ x: Double,_ y: Double)->GeoPoint { plane.unproject(.init(x:x,y:y)) }
        return .init(id:"lane",name:"Creek lane",left:.init(points:[p(-50,0),p(-50,300)],label:"Creek"),right:.init(points:[p(50,0),p(50,300)],label:"Road"),backstop:.init(points:[p(-100,320),p(0,350),p(100,320)],label:"Power line"),scope:.checkpoint,targetId:"cp")
    }
    func testCompleteFiniteLimitsBendsLabelsAndLegacyReplacement() throws {
        let value=lane(), overlay=try XCTUnwrap(WatchLaneOverlay.build(value,graphics:[]))
        XCTAssertEqual(overlay.leftLabel,"Creek");XCTAssertEqual(overlay.backstopLabel,"Power line")
        XCTAssertEqual(overlay.backstop.count,3);XCTAssertTrue(overlay.outline.count>4)
        XCTAssertNotEqual(overlay.left.last,value.left.points.last)
        let packet=WatchMapSnapshot.build(waypoints:[],folders:[],document:.init(),lanes:[value])
        let decoded=try XCTUnwrap(WatchMapSnapshot.decode(XCTUnwrap(packet.encoded())))
        XCTAssertEqual(decoded.laneOverlays,[overlay])
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(packet.encoded())) as? [String:Any]);legacy.removeValue(forKey:"lanes")
        XCTAssertTrue(try XCTUnwrap(WatchMapSnapshot.decode(JSONSerialization.data(withJSONObject:legacy))).laneOverlays.isEmpty)
        let empty=WatchMapSnapshot.build(waypoints:[],folders:[],document:.init(),lanes:[],revision:1)
        XCTAssertTrue(empty.shouldApply(over:packet));XCTAssertTrue(empty.laneOverlays.isEmpty)
    }
    func testHiddenDeletedLinksAndOversizedLanesAreWholeOmissions() throws {
        var value=lane();value.visible=false
        XCTAssertTrue(WatchMapSnapshot.build(waypoints:[],folders:[],document:.init(),lanes:[value]).laneOverlays.isEmpty)
        value.visible=true;value.folder="Hidden"
        XCTAssertTrue(WatchMapSnapshot.build(waypoints:[],folders:[.init(name:"Hidden",visible:false)],document:.init(),lanes:[value]).laneOverlays.isEmpty)
        value.folder="Base";value.left.graphicId="deleted"
        let missing=WatchMapSnapshot.build(waypoints:[],folders:[],document:.init(),lanes:[value])
        XCTAssertTrue(missing.laneOverlays.isEmpty);XCTAssertEqual(missing.omittedItems,1)
        value=lane();value.left.points=(0...200).map { i in .init(lat:24+Double(i)*0.00001,lon:53.9995) }
        let large=WatchMapSnapshot.build(waypoints:[],folders:[],document:.init(),lanes:[value])
        XCTAssertTrue(large.laneOverlays.isEmpty);XCTAssertEqual(large.omittedItems,1)
    }
    func testBoundsNeverDropOnlyPartOfALaneAndMalformedGeometryRejects() throws {
        let values=(0..<12).map { i -> NavLane in var v=lane();v.id="lane-\(i)";return v }
        let scene=WatchMapSnapshot.build(waypoints:[],folders:[],document:.init(),lanes:values)
        XCTAssertLessThanOrEqual(scene.laneOverlays.count,8);XCTAssertEqual(scene.laneOverlays.count+scene.omittedItems,12)
        XCTAssertTrue(scene.laneOverlays.allSatisfy(\.isValid));XCTAssertNotNil(scene.encoded())
        var invalid=scene;invalid.lanes?[0].outline=[]
        XCTAssertNil(invalid.encoded())
        var crossing=try XCTUnwrap(scene.laneOverlays.first)
        crossing.backstop=[.init(lat:24,lon:179.99),.init(lat:24,lon:-179.99)]
        XCTAssertFalse(crossing.isValid)
        let p=WatchLaneOverlay.labelPoint([.init(lat:24,lon:54),.init(lat:24.002,lon:54)])
        XCTAssertEqual(p.lat,24.001,accuracy:0.000001)
    }
}
