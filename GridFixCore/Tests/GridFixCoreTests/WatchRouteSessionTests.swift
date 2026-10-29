import XCTest
@testable import GridFixCore

final class WatchRouteSessionTests: XCTestCase {
    private func route() -> WatchMapSnapshot.Feature {
        .init(id:"route",kind:"graphic",name:"Fake patrol",type:"route",affiliation:"none",echelon:"",
              points:[.init(lat:0,lon:0),.init(lat:0,lon:0.001),.init(lat:0,lon:0.002)],originalPointCount:3,simplified:false,routeVertexIndices:[0,1,2])
    }
    private func scene(_ route: WatchMapSnapshot.Feature) -> WatchMapSnapshot {
        var s = WatchMapSnapshot(sourceID:"phone");s.features=[route];return s
    }
    private func tick(_ s: inout WatchRouteSession,_ t: Double,_ lon: Double,accuracy: Double = 5) -> NavigationPulse? {
        s.update(position:.init(lat:0,lon:lon),accuracy:accuracy,fixTime:t,now:t,usable:true)
    }
    func testFullRouteOnlyRejectsSimplificationTruncationTrackAndMalformedGeometry() {
        let good = route(); XCTAssertTrue(WatchRouteSession.canFollow(good))
        var bad = good;bad.simplified=true;XCTAssertFalse(WatchRouteSession.canFollow(bad))
        bad=good;bad.originalPointCount=10;XCTAssertFalse(WatchRouteSession.canFollow(bad))
        bad=good;bad.kind="track";bad.type="track";XCTAssertFalse(WatchRouteSession.canFollow(bad))
        bad=good;bad.points[1] = .init(lat:.nan,lon:0);XCTAssertFalse(WatchRouteSession.canFollow(bad))
        bad=good;bad.routeVertexIndices=[0,2,3];XCTAssertFalse(WatchRouteSession.canFollow(bad))
        bad=good;bad.points=Array(repeating:.init(lat:0,lon:0),count:161);bad.originalPointCount=161;bad.routeVertexIndices=nil
        XCTAssertFalse(WatchRouteSession.canFollow(bad))
    }
    func testExplicitStartAdvancesEveryVertexInOrderThenCompletesWithoutAutoRestart() {
        var s=WatchRouteSession();XCTAssertNil(tick(&s,100,0));XCTAssertFalse(s.active)
        XCTAssertTrue(s.start(route(),sourceID:"phone",now:100));XCTAssertEqual(s.target?.name,"Fake patrol · WP1")
        XCTAssertNil(tick(&s,100,0));XCTAssertEqual(s.progress?.index,0)
        XCTAssertEqual(tick(&s,101,0),.checkpoint);XCTAssertEqual(s.progress?.index,1)
        XCTAssertNil(tick(&s,102,0.002));XCTAssertEqual(s.progress?.index,1,"Cannot skip WP2 by visiting WP3")
        XCTAssertEqual(tick(&s,103,0.001),.checkpoint)
        XCTAssertEqual(tick(&s,104,0.002),.complete);XCTAssertFalse(s.active);XCTAssertNil(s.target)
        XCTAssertNil(tick(&s,105,0.002));XCTAssertTrue(s.hasRoute)
        s.stop();XCTAssertFalse(s.hasRoute)
        var named = route(); named.name = "RT1"; s.start(named,sourceID:"phone",now:110)
        XCTAssertEqual(s.target?.name,"RT1WP1")
        named.name = ""; s.start(named,sourceID:"phone",now:111); XCTAssertEqual(s.target?.name,"WP1")
    }
    func testRepeatedSameFixCannotAdvanceCoincidentCheckpoints() {
        var r=route();r.points=Array(repeating:.init(lat:0,lon:0),count:3)
        var s=WatchRouteSession();s.start(r,sourceID:"phone",now:100)
        XCTAssertEqual(tick(&s,101,0),.checkpoint)
        XCTAssertNil(tick(&s,101,0));XCTAssertEqual(s.progress?.index,1)
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:101.001,
                              now:101.001,usable:true,sampleID:101))
        XCTAssertEqual(s.progress?.index,1,"One source timestamp remains one sample despite uptime conversion jitter")
        XCTAssertEqual(tick(&s,102,0),.checkpoint);XCTAssertEqual(tick(&s,103,0),.complete)
    }
    func testPauseResumeRetainsProgressButRequiresPostResumeFix() {
        var s=WatchRouteSession();s.start(route(),sourceID:"phone",now:100);tick(&s,101,0)
        s.pause();XCTAssertFalse(s.active);XCTAssertNil(tick(&s,102,0.001));XCTAssertEqual(s.progress?.index,1)
        XCTAssertTrue(s.resume(now:110))
        XCTAssertNil(s.update(position:.init(lat:0,lon:0.001),accuracy:5,fixTime:109,now:110,usable:true))
        XCTAssertEqual(tick(&s,111,0.001),.checkpoint)
    }
    func testBadStaleFutureAndRollbackFixesCannotAdvance() {
        var s=WatchRouteSession();s.start(route(),sourceID:"phone",now:100)
        XCTAssertNil(tick(&s,101,0,accuracy:26));XCTAssertEqual(s.progress?.index,0)
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:101,now:112,usable:true))
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:114,now:113,usable:true))
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:115,now:115,usable:false))
        XCTAssertEqual(tick(&s,116,0),.checkpoint)
        XCTAssertNil(tick(&s,115,0.001));XCTAssertEqual(s.progress?.index,1)
    }
    func testSceneReplacementHideDeleteSourceAndGeometryChangesDisarm() {
        let r=route();var s=WatchRouteSession();s.start(r,sourceID:"phone",now:100)
        s.validateScene(scene(r));XCTAssertTrue(s.active)
        var changed=scene(r);changed.features=[];s.validateScene(changed);XCTAssertFalse(s.hasRoute)
        s.start(r,sourceID:"phone",now:101);changed=scene(r);changed.sourceID="other";s.validateScene(changed);XCTAssertFalse(s.hasRoute)
        s.start(r,sourceID:"phone",now:102);changed=scene(r);changed.features[0].points[1] = .init(lat:0,lon:0.003);s.validateScene(changed);XCTAssertFalse(s.hasRoute)
        s.start(r,sourceID:"phone",now:103);s.validateScene(nil);XCTAssertFalse(s.hasRoute)
    }
    func testAccuracyCircleMustFitStrictlyInsideCheckpointRadius() {
        var s=WatchRouteSession();s.start(route(),sourceID:"phone",now:100)
        XCTAssertNil(tick(&s,101,0,accuracy:25));XCTAssertEqual(s.progress?.index,0)
        XCTAssertEqual(tick(&s,102,0,accuracy:24.999),.checkpoint)
    }
}
