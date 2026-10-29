import XCTest
@testable import GridFixCore

final class WatchSteeringSessionTests: XCTestCase {
    private let east = WatchSnapshot.Target(id:"east",name:"Fake east",lat:0,lon:0.01)
    private func heading(_ value: Double,_ time: Double) -> WatchHeadingSample {
        WatchHeadingSample(trueDegrees:value,accuracy:2,sampleUptime:time,sessionUptime:99,nowUptime:time)!
    }
    private func tick(_ s: inout WatchSteeringSession,_ t: Double,_ h: Double = 0,
                      position: GeoPoint = .init(lat:0,lon:0)) -> NavigationPulse? {
        s.update(position:position,accuracy:5,fixTime:t,heading:heading(h,t),now:t,usable:true)
    }
    func testNoAutoArmAndMalformedTargetCannotStart() {
        var s = WatchSteeringSession()
        XCTAssertNil(tick(&s,100)); XCTAssertFalse(s.active)
        XCTAssertFalse(s.start(.init(id:"bad",name:"Bad",lat:.nan,lon:0)))
        XCTAssertFalse(s.start(.init(id:"",name:"Bad",lat:0,lon:0)))
        XCTAssertNil(tick(&s,101)); XCTAssertFalse(s.active)
    }
    func testConfirmedRightLeftAndQuietOnCourseUseSharedCadence() {
        var s = WatchSteeringSession(); XCTAssertTrue(s.start(east))
        XCTAssertNil(tick(&s,100)); XCTAssertEqual(s.status,"Confirming turn")
        XCTAssertEqual(tick(&s,105),.right); XCTAssertEqual(s.status,"Turn right")
        XCTAssertNil(tick(&s,105.1)); XCTAssertEqual(tick(&s,106,180),.left)
        XCTAssertEqual(tick(&s,107,90),.onCourse); XCTAssertEqual(s.status,"On bearing")
        XCTAssertNil(tick(&s,108,90)); XCTAssertNil(tick(&s,150,90))
    }
    func testNorthWrapDoesNotSuggestFullCircleTurn() {
        var s = WatchSteeringSession(); s.start(.init(id:"north",name:"North",lat:0.01,lon:0))
        XCTAssertNil(tick(&s,100,359)); XCTAssertEqual(s.decision?.cue,.onBearing)
        XCTAssertEqual(s.decision?.deviation ?? 999,1,accuracy:0.001)
    }
    func testStaleOrMissingSensorsAreQuietAndResetPendingTurnConfirmation() {
        var s = WatchSteeringSession(); s.start(east)
        XCTAssertNil(tick(&s,100))
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:101,
                              heading:heading(0,100),now:106,usable:true))
        XCTAssertNil(s.decision); XCTAssertTrue(s.active)
        XCTAssertNil(tick(&s,107)); XCTAssertNil(tick(&s,111)); XCTAssertEqual(tick(&s,112),.right)
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:112,
                              heading:heading(0,123),now:123,usable:true))
        XCTAssertNil(s.decision)
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:124,heading:nil,now:124,usable:true))
        XCTAssertNil(s.decision)
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:125,
                              heading:heading(0,125),now:125,usable:false))
        XCTAssertNil(s.decision)
    }
    func testTargetEditClearAndStopRequireNewConsent() {
        var s = WatchSteeringSession(); s.start(east); tick(&s,100)
        s.validateTarget(east); XCTAssertTrue(s.active)
        var changed = east; changed.lon = 0.02; s.validateTarget(changed)
        XCTAssertFalse(s.active); XCTAssertNil(tick(&s,106))
        s.start(east); s.validateTarget(nil); XCTAssertFalse(s.active)
        s.start(east); s.stop("Paused · start steering again")
        XCTAssertFalse(s.active); XCTAssertNil(tick(&s,107)); XCTAssertTrue(s.status.contains("start steering again"))
    }
    func testArrivalIsQuietAfterFirstCueIncludingSensorGapAndRearmsBeyond150m() {
        var s = WatchSteeringSession(); s.start(.init(id:"near",name:"Near",lat:0,lon:0.0001))
        XCTAssertEqual(tick(&s,100,90),.arrival); XCTAssertEqual(s.status,"Arrived")
        XCTAssertNil(tick(&s,101,90)); s.invalidateSensors(); XCTAssertNil(tick(&s,102,90))
        XCTAssertNil(tick(&s,103,90,position:.init(lat:0,lon:-0.002)))
        XCTAssertEqual(tick(&s,104,90),.arrival)
    }
    func testFuturePoorFixAndUptimeRollbackCannotEmitTurn() {
        var s = WatchSteeringSession(); s.start(east); tick(&s,100)
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:26,fixTime:105,
                              heading:heading(0,105),now:105,usable:true))
        XCTAssertNil(s.update(position:.init(lat:0,lon:0),accuracy:5,fixTime:110,
                              heading:heading(0,106),now:106,usable:true))
        tick(&s,120)
        XCTAssertNil(tick(&s,119)); XCTAssertNil(s.decision)
        XCTAssertNil(s.update(position:.init(lat:.nan,lon:0),accuracy:5,fixTime:121,
                              heading:heading(0,121),now:121,usable:true))
        XCTAssertNil(s.decision)
    }
}
