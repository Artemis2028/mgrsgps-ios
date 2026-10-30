import XCTest
@testable import GridFixCore

final class WatchLaneSessionTests: XCTestCase {
    private let plane = LaneLocalPlane(origin: .init(lat: 24, lon: 54))
    private func p(_ x: Double, _ y: Double) -> GeoPoint { plane.unproject(.init(x: x, y: y)) }
    private func lane() throws -> WatchLaneOverlay {
        try XCTUnwrap(WatchLaneOverlay.build(.init(id: "lane", name: "Creek lane",
            left: .init(points: [p(-50,0),p(-50,300)], label: "Creek"),
            right: .init(points: [p(50,0),p(50,300)], label: "Road"),
            backstop: .init(points: [p(-100,320),p(0,350),p(100,320)], label: "Power line"), scope: .checkpoint, targetId: "cp"), graphics: []))
    }
    @discardableResult private func fix(_ session: inout WatchLaneSession, _ t: Double, _ x: Double, _ y: Double, usable: Bool = true) -> LanePulse? {
        session.update(position: p(x,y), accuracy: 3, fixTime: t, now: t, usable: usable)
    }
    func testLocalConsentEntryDebounceNamedCrossingsAndSilentReturn() throws {
        var session = WatchLaneSession()
        XCTAssertNil(fix(&session,100,-80,100)); XCTAssertFalse(session.active)
        try session.start(lane())
        XCTAssertNil(fix(&session,101,-80,100)); XCTAssertEqual(session.decision?.state,.notYet)
        XCTAssertNil(fix(&session,102,0,100)); XCTAssertNil(fix(&session,103,0,100))
        XCTAssertEqual(session.decision?.state,.inside)
        XCTAssertNil(fix(&session,104,-80,100)); XCTAssertEqual(fix(&session,105,-80,100),.turnRight)
        XCTAssertTrue(session.status.contains("Creek"))
        XCTAssertNil(fix(&session,106,0,100)); XCTAssertNil(fix(&session,107,0,100))
        XCTAssertNil(fix(&session,108,80,100)); XCTAssertEqual(fix(&session,109,80,100),.turnLeft)
        XCTAssertTrue(session.status.contains("Road"))
        fix(&session,110,0,100); fix(&session,111,0,100)
        fix(&session,112,0,400); XCTAssertEqual(fix(&session,113,0,400),.overshot)
        XCTAssertTrue(session.status.contains("Power line"))
    }
    func testDuplicateStaleAndUnavailableFixesCannotConfirmCrossing() throws {
        var session = WatchLaneSession(); try session.start(lane())
        fix(&session,100,0,100); fix(&session,101,0,100)
        fix(&session,102,-80,100)
        XCTAssertNil(fix(&session,102,-80,100)); XCTAssertEqual(session.decision?.state,.inside)
        XCTAssertNil(session.update(position:p(-80,100),accuracy:3,fixTime:102,now:200,usable:true))
        XCTAssertNil(session.decision)
        XCTAssertNil(fix(&session,201,-80,100)); XCTAssertEqual(session.decision?.state,.inside)
        XCTAssertNil(fix(&session,202,-80,100,usable:false))
        XCTAssertNil(fix(&session,203,-80,100)); XCTAssertEqual(fix(&session,204,-80,100),.turnRight)
    }
    func testSceneChangesAndSuspensionRequireExplicitRearmAndFreshEntry() throws {
        var session = WatchLaneSession(); let overlay = try lane(); try session.start(overlay)
        fix(&session,100,0,100); fix(&session,101,0,100)
        session.validateScene([overlay]); XCTAssertTrue(session.active)
        var changed = overlay; changed.backstopLabel = "New limit"
        session.validateScene([changed]); XCTAssertFalse(session.active)
        XCTAssertNil(fix(&session,102,-80,100))
        try session.start(overlay); session.stop("Paused")
        XCTAssertNil(fix(&session,103,-80,100)); XCTAssertEqual(session.status,"Paused")
        try session.start(overlay)
        for t in 104...108 { XCTAssertNil(fix(&session,Double(t),-80,100)) }
        XCTAssertEqual(session.decision?.state,.notYet)
        session.validateScene([]); XCTAssertFalse(session.active)
    }
    func testOptedInBackgroundOwnerRetainsEntryAndNamedCrossingUntilStopped() throws {
        var session = WatchLaneSession(); try session.start(lane(),continueInBackground:true)
        fix(&session,100,0,100); fix(&session,101,0,100)
        fix(&session,102,-80,100)
        session.leaveForeground(backgroundAvailable:true)
        XCTAssertTrue(session.active); XCTAssertTrue(session.continuesInBackground)
        XCTAssertEqual(fix(&session,103,-80,100),.turnRight)
        XCTAssertTrue(session.status.contains("Creek"))
        fix(&session,104,0,100); XCTAssertNil(fix(&session,105,0,100))
        XCTAssertEqual(session.decision?.state,.inside)
        session.stop()
        XCTAssertFalse(session.continuesInBackground); XCTAssertNil(fix(&session,106,-80,100))
    }
    func testForegroundConsentOrMissingBackgroundOwnerRequiresExplicitRearm() throws {
        for backgroundConsent in [false,true] {
            var session = WatchLaneSession(); try session.start(lane(),continueInBackground:backgroundConsent)
            fix(&session,100,0,100); fix(&session,101,0,100)
            session.leaveForeground(backgroundAvailable:!backgroundConsent)
            XCTAssertFalse(session.active); XCTAssertFalse(session.continuesInBackground)
            XCTAssertNil(fix(&session,102,-80,100))
            try session.start(lane(),continueInBackground:backgroundConsent)
            for t in 103...106 { XCTAssertNil(fix(&session,Double(t),-80,100)) }
            XCTAssertEqual(session.decision?.state,.notYet)
        }
    }
    func testBackgroundGPSGapClearsHalfCrossingAndSceneChangeReleasesConsent() throws {
        var session = WatchLaneSession(); let overlay = try lane()
        try session.start(overlay,continueInBackground:true)
        fix(&session,100,0,100); fix(&session,101,0,100); fix(&session,102,-80,100)
        session.leaveForeground(backgroundAvailable:true)
        session.invalidateFix()
        XCTAssertTrue(session.active); XCTAssertNil(session.decision)
        XCTAssertNil(fix(&session,103,-80,100))
        XCTAssertEqual(fix(&session,104,-80,100),.turnRight)
        var changed = overlay; changed.leftLabel = "New creek"
        session.validateScene([changed])
        XCTAssertFalse(session.active); XCTAssertFalse(session.continuesInBackground)
        XCTAssertNil(fix(&session,105,-80,100))
    }
    func testBackgroundNoticesAreQuietInsideAndOnlyOncePerConfirmedExcursion() throws {
        var session = WatchLaneSession(); try session.start(lane(),continueInBackground:true)
        XCTAssertNil(session.takeBackgroundNotice())
        fix(&session,100,0,100); fix(&session,101,0,100)
        XCTAssertNil(session.takeBackgroundNotice())
        fix(&session,102,-80,100); XCTAssertNil(session.takeBackgroundNotice())
        fix(&session,103,-80,100)
        XCTAssertEqual(session.takeBackgroundNotice()?.state,.outLeft)
        for t in 104...110 { fix(&session,Double(t),-80,100); XCTAssertNil(session.takeBackgroundNotice()) }
        fix(&session,111,0,100); fix(&session,112,0,100)
        XCTAssertNil(session.takeBackgroundNotice())
        fix(&session,113,-80,100); fix(&session,114,-80,100)
        XCTAssertEqual(session.takeBackgroundNotice()?.state,.outLeft)
        session.stop(); XCTAssertNil(session.takeBackgroundNotice())
    }
    func testBackgroundNoticeScopeAndGPSGapCannotLeakOrConsumeForegroundCue() throws {
        var session = WatchLaneSession(); try session.start(lane())
        fix(&session,100,0,100); fix(&session,101,0,100); fix(&session,102,80,100)
        XCTAssertEqual(fix(&session,103,80,100),.turnLeft)
        XCTAssertNil(session.takeBackgroundNotice())
        try session.start(lane(),continueInBackground:true)
        fix(&session,104,0,100); fix(&session,105,0,100); fix(&session,106,80,100); fix(&session,107,80,100)
        XCTAssertEqual(session.takeBackgroundNotice()?.state,.outRight)
        session.invalidateFix(); XCTAssertNil(session.takeBackgroundNotice())
        // The engine retains an already confirmed outside state across a GPS
        // gap; the first fresh fix can renew that notice, then stays quiet.
        fix(&session,108,80,100); XCTAssertEqual(session.takeBackgroundNotice()?.state,.outRight)
        fix(&session,109,80,100); XCTAssertNil(session.takeBackgroundNotice())
        fix(&session,110,0,400); fix(&session,111,0,400)
        XCTAssertEqual(session.takeBackgroundNotice()?.state,.overshot)
    }
    func testInvalidReplacementDisarmsAndFutureOrNonfiniteFixesStaySilent() throws {
        var session = WatchLaneSession(); var overlay = try lane(); try session.start(overlay)
        overlay.left = []
        XCTAssertThrowsError(try session.start(overlay)); XCTAssertFalse(session.active)
        try session.start(lane())
        XCTAssertNil(session.update(position:p(0,100),accuracy:3,fixTime:101,now:100,usable:true))
        XCTAssertNil(session.update(position:p(0,100),accuracy:3,fixTime:100,now:.nan,usable:true))
        XCTAssertNil(session.decision)
    }
}
