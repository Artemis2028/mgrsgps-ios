import XCTest
@testable import GridFixCore

final class NavigationGuideTests: XCTestCase {
    private func config(hold: Double = 0,corridor: Double = 0,home: Bool = false) -> GuideConfiguration {
        var c = GuideConfiguration(); c.holdOff = hold; c.corridor = corridor; c.holdAzimuth = !home; return c
    }
    private func sample(_ state: inout GuideCueState,_ t: Double,_ heading: Double?,_ c: GuideConfiguration, cross: Double = 0,bearing: Double = 90,leg: Double? = 90,distance: Double = 1000) -> GuideDecision {
        state.update(now: t,heading: heading,bearing: bearing,leg: leg,crossTrack: cross,distance: distance,config: c)
    }
    func testAndroidAllowanceDirectionsWrapAndHysteresis() {
        var s = GuideCueState(); let c = config()
        XCTAssertEqual(sample(&s,0,90,c).cue,.onBearing)
        XCTAssertEqual(sample(&s,0.25,99.5,c).cue,.onBearing)
        XCTAssertEqual(sample(&s,0.5,80.5,c).cue,.onBearing)
        XCTAssertEqual(sample(&s,1,105,c).cue,.left)
        for (i,h) in [99.0,101,98.5,100.5,99.2].enumerated() { XCTAssertFalse(sample(&s,Double(i+5),h,c).changed) }
        XCTAssertEqual(sample(&s,12,96,c).cue,.onBearing)
        XCTAssertEqual(sample(&s,13,75,c).cue,.right)
        XCTAssertEqual(GuideCueState.delta(5,345),20,accuracy: 0.001)
        XCTAssertEqual(GuideCueState.delta(350,0),-10,accuracy: 0.001)
    }
    func testAndroidHoldOffDoesNotBuzzAroundShortDetour() {
        var s = GuideCueState(); let c = config(hold: 5)
        _ = sample(&s,0,90,c)
        for t in stride(from: 0.25,through: 4,by: 0.25) { XCTAssertEqual(sample(&s,t,40,c).cue,.onBearing) }
        XCTAssertEqual(sample(&s,4.25,92,c).cue,.onBearing)
        XCTAssertEqual(sample(&s,5,120,c).cue,.onBearing)
        XCTAssertEqual(sample(&s,9.99,120,c).cue,.onBearing)
        XCTAssertEqual(sample(&s,10,120,c).cue,.left)
    }
    func testAndroidCorridorInterceptHysteresisAndHoming() {
        var s = GuideCueState(); let c = config(corridor: 100)
        XCTAssertEqual(sample(&s,0,90,c,cross: 80).cue,.onBearing)
        let out = sample(&s,0.25,90,c,cross: 120)
        XCTAssertTrue(out.outsideCorridor); XCTAssertEqual(out.cue,.left)
        XCTAssertEqual(sample(&s,0.5,62,c,cross: 110).cue,.onBearing)
        XCTAssertTrue(sample(&s,0.75,62,c,cross: 90).outsideCorridor)
        XCTAssertFalse(sample(&s,1,90,c,cross: 70).outsideCorridor)
        let near = sample(&s,1.25,90,c,cross: 200,bearing: 120,distance: 60)
        XCTAssertFalse(near.outsideCorridor); XCTAssertEqual(near.cue,.right)
        var home = GuideCueState()
        XCTAssertEqual(sample(&home,0,90,config(home: true),bearing: 70).cue,.left)
    }
    func testUnavailableIsImmediateAndNoLegHomesOnPoint() {
        var s = GuideCueState(); let c = config(hold: 10)
        _ = sample(&s,0,90,c)
        XCTAssertEqual(sample(&s,0.25,nil,c).cue,.unavailable)
        XCTAssertEqual(sample(&s,0.5,.nan,c).cue,.unavailable)
        let d = s.update(now: 1,heading: 90,bearing: nil,leg: 90,crossTrack: 0,distance: 1000,config: c)
        XCTAssertEqual(d.cue,.unavailable)
        s = GuideCueState()
        XCTAssertEqual(sample(&s,2,90,config(),bearing: 70,leg: nil).cue,.left)
        XCTAssertEqual(GuideCueState.crossTrack(distance: 100,bearing: 5,leg: 355),17.36,accuracy: 0.01)
    }
    func testArrivalOnceRearmsAfter150AndIgnoresUnknown() {
        var a = NavigationArrivalState()
        XCTAssertFalse(a.update(target: "a",distance: 49,accuracy: 1))
        XCTAssertTrue(a.update(target: "a",distance: 48,accuracy: 1))
        XCTAssertFalse(a.update(target: "a",distance: nil,accuracy: nil))
        XCTAssertFalse(a.update(target: "a",distance: 1,accuracy: 1))
        XCTAssertFalse(a.update(target: "a",distance: 151,accuracy: 1))
        XCTAssertTrue(a.update(target: "a",distance: 1,accuracy: 1))
        XCTAssertFalse(a.update(target: "b",distance: 1,accuracy: 26))
        XCTAssertTrue(a.update(target: "b",distance: 1,accuracy: 1))
    }
    func testCadenceCorrectionHeartbeatAndBackOnCourse() {
        var cadence = GuideCadence()
        func d(_ cue: GuideCue,_ changed: Bool,_ error: Double = 20) -> GuideDecision { .init(cue: cue,deviation: error,outsideCorridor: false,changed: changed) }
        XCTAssertNil(cadence.pulse(now: 1,decision: d(.onBearing,true),arrived: false,heartbeat: 30))
        XCTAssertNil(cadence.pulse(now: 30,decision: d(.onBearing,false),arrived: false,heartbeat: 30))
        XCTAssertEqual(cadence.pulse(now: 31,decision: d(.onBearing,false),arrived: false,heartbeat: 30),.onCourse)
        XCTAssertEqual(cadence.pulse(now: 32,decision: d(.left,true),arrived: false,heartbeat: 0),.left)
        XCTAssertNil(cadence.pulse(now: 33,decision: d(.left,false),arrived: false,heartbeat: 0))
        XCTAssertEqual(cadence.pulse(now: 34,decision: d(.left,false),arrived: false,heartbeat: 0),.left)
        XCTAssertEqual(cadence.pulse(now: 35,decision: d(.onBearing,true),arrived: false,heartbeat: 0),.onCourse)
        XCTAssertNil(cadence.pulse(now: 1000,decision: d(.onBearing,false),arrived: false,heartbeat: 0))
        XCTAssertEqual(cadence.pulse(now: 1001,decision: d(.unavailable,true),arrived: false,heartbeat: 0),.unavailable)
        XCTAssertEqual(cadence.pulse(now: 1002,decision: d(.unavailable,false),arrived: true,heartbeat: 0),.arrival)
    }
    func testOrderedRouteCheckpointUsesStrict25mAndPause() {
        var p = RouteFollowingProgress(routeID: "r",name: "Route",points: [.init(lat: 0,lon: 0),.init(lat: 1,lon: 1)])
        XCTAssertFalse(p.arrive(distance: 20,accuracy: 5))
        p.paused = true; XCTAssertFalse(p.arrive(distance: 1,accuracy: 1))
        p.paused = false; XCTAssertTrue(p.arrive(distance: 19,accuracy: 5)); XCTAssertEqual(p.index,1)
        XCTAssertFalse(p.arrive(distance: 1,accuracy: .nan))
        XCTAssertTrue(p.arrive(distance: 0,accuracy: 0)); XCTAssertTrue(p.complete)
        XCTAssertFalse(p.arrive(distance: 0,accuracy: 0))
    }
    func testGuideSettingsBackupRoundtripAndRejectInvalid() throws {
        var doc = Backup.Document(); doc.settings.guideAllowance = 20; doc.settings.guideHoldOffSec = 3
        doc.settings.guideHeartbeatSec = 0; doc.settings.guideMode = 1; doc.settings.guideCorridorM = 200
        let restored = try Backup.importZip(Backup.exportZip(doc))
        XCTAssertEqual(restored.settings,doc.settings)
        doc.settings.guideCorridorM = 2001; XCTAssertThrowsError(try Backup.validate(doc))
    }
}
