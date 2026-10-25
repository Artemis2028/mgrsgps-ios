import XCTest
@testable import GridFixCore

/// Numerical scenarios ported from Android LaneGuideTest (91cb68f).
final class NavigationLaneTests: XCTestCase {
    func testBackgroundNotificationsAreTransitionsRatherThanRepeatingSteering() {
        for pulse in [NavigationPulse.right,.left,.laneOvershot,.onCourse,.unavailable] { XCTAssertNil(pulse.backgroundNotificationTitle); XCTAssertFalse(pulse.isLaneCrossingEvent) }
        for pulse in [NavigationPulse.laneLeftCrossing,.laneRightCrossing,.laneBackstopCrossing,.laneReentered] { XCTAssertNotNil(pulse.backgroundNotificationTitle); XCTAssertTrue(pulse.isLaneCrossingEvent) }
        XCTAssertEqual(NavigationPulse.arrival.backgroundNotificationTitle,"Arrived")
    }
    func testLaneWarningBackupContractDefaultsAndValidation() throws {
        var document = Backup.Document(); document.settings.laneWarningM = 50
        let decoded = try Backup.importZip(Backup.exportZip(document))
        XCTAssertEqual(decoded.settings.laneWarningM,50)
        document.settings.laneWarningM = 201
        XCTAssertThrowsError(try Backup.validate(document))
    }
    private let plane = LaneLocalPlane(origin: .init(lat: 35,lon: -79))
    private func at(_ x: Double,_ y: Double) -> GeoPoint { plane.unproject(.init(x: x,y: y)) }
    private func line(_ points: (Double,Double)...) -> [GeoPoint] { points.map { at($0.0,$0.1) } }
    private var left: [GeoPoint] { line((-50,0),(-50,500)) }
    private var right: [GeoPoint] { line((50,0),(50,500)) }
    private var back: [GeoPoint] { line((-100,520),(100,520)) }
    private func shape() throws -> LaneShape { try .init(leftDrawn: left,rightDrawn: right,backstopDrawn: back) }
    private func fix(_ guide: inout LaneGuideState,_ t: Double,_ x: Double,_ y: Double,_ accuracy: Double = 5) -> LaneDecision {
        guide.update(position: at(x,y),accuracy: accuracy,fixTime: t)
    }
    func testSignedOffsetsAndInsideSilence() throws {
        let s = try shape(), r = s.read(at(0,250))
        XCTAssertEqual(try XCTUnwrap(r.left),-50,accuracy: 0.2)
        XCTAssertEqual(try XCTUnwrap(r.right),-50,accuracy: 0.2)
        XCTAssertEqual(try XCTUnwrap(r.backstop),-270,accuracy: 0.2)
        var g = LaneGuideState(shape: s), cadence = LaneCueCadence()
        for y in stride(from: 0,through: 500,by: 25) {
            let d = fix(&g,Double(y),Double(y%3-1)*30,Double(y))
            XCTAssertEqual(d.state,.inside); XCTAssertFalse(d.changed); XCTAssertFalse(d.backInside)
            XCTAssertNil(d.warning); XCTAssertNil(cadence.next(decision: d,now: Double(y)))
        }
    }
    func testCrossingsRequireTwoDistinctNewFixesAndBackstopWins() throws {
        var g = LaneGuideState(shape: try shape())
        XCTAssertEqual(fix(&g,1,-80,100).state,.inside)
        XCTAssertEqual(fix(&g,1,-80,100).state,.inside)
        XCTAssertEqual(fix(&g,0,-80,100).state,.inside)
        XCTAssertEqual(fix(&g,2,-80,105).state,.outLeft)
        XCTAssertEqual(fix(&g,3,-80,560).state,.outLeft)
        XCTAssertEqual(fix(&g,4,-80,561).state,.overshot)
        XCTAssertEqual(fix(&g,5,-80,480).state,.overshot)
        let back = fix(&g,6,-80,470)
        XCTAssertEqual(back.state,.outLeft); XCTAssertFalse(back.backInside)
    }
    func testRightCrossingAndReentryHysteresis() throws {
        var g = LaneGuideState(shape: try shape())
        _ = fix(&g,1,70,100)
        XCTAssertEqual(fix(&g,2,70,110).state,.outRight)
        for (i,x) in [50.0,48,45].enumerated() { XCTAssertEqual(fix(&g,Double(i+3),x,120).state,.outRight) }
        let back = fix(&g,6,44,130)
        XCTAssertTrue(back.changed); XCTAssertTrue(back.backInside); XCTAssertEqual(back.state,.inside)
        XCTAssertFalse(fix(&g,7,30,140).backInside)
    }
    func testAccuracyJitterAndPoorFixReset() throws {
        var g = LaneGuideState(shape: try shape())
        for (i,x) in [-58.0,-42,-55,-47,-57.9,-44,-50,-52,-41,-57].enumerated() {
            XCTAssertEqual(fix(&g,Double(i),x,100).state,.inside)
        }
        _ = fix(&g,20,-80,100)
        _ = fix(&g,21,-80,100,80)
        XCTAssertEqual(fix(&g,22,-80,100).state,.inside)
        XCTAssertEqual(fix(&g,23,-80,100).state,.outLeft)
        XCTAssertEqual(fix(&g,24,0,100,.nan).state,.outLeft)
        var loose = LaneGuideState(shape: try shape()), tight = loose
        _ = fix(&loose,1,-62,100,10); XCTAssertEqual(fix(&loose,2,-62,105,10).state,.inside)
        _ = fix(&tight,1,-62,100,4); XCTAssertEqual(fix(&tight,2,-62,105,4).state,.outLeft)
    }
    func testAlternatingExcursionsDoNotConfirm() throws {
        var g = LaneGuideState(shape: try shape())
        for i in 0..<10 { XCTAssertEqual(fix(&g,Double(i),i%2 == 0 ? -80 : -30,200).state,.inside) }
    }
    func testBendsFollowActualLineAndVertexBisector() throws {
        let s = try LaneShape(leftDrawn: line((-50,0),(-50,200),(-150,300),(-150,500)),rightDrawn: right,backstopDrawn: back)
        XCTAssertLessThan(try XCTUnwrap(s.read(at(-100,270)).left),0)
        XCTAssertLessThan(try XCTUnwrap(s.read(at(-140,320)).left),0)
        XCTAssertEqual(try XCTUnwrap(s.read(at(-130,240)).left),40/sqrt(2),accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(s.read(at(-170,400)).left),20,accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(s.read(at(-160,300)).left),10,accuracy: 0.3)
        let p = LanePlanePolyline([.init(x: -50,y: 0),.init(x: -50,y: 300),.init(x: -200,y: 250)],extendStart: false,extendEnd: true)
        let corner = p.offset(.init(x: -40,y: 302))
        XCTAssertTrue(corner.inDomain); XCTAssertEqual(-corner.distance,hypot(10,2),accuracy: 1e-6)
        XCTAssertGreaterThan(p.offset(.init(x: -60,y: 296)).distance,0)
    }
    func testReversedAndSwappedDrawingsHaveSameGroundMeaning() throws {
        let original = try shape()
        let reversed = try LaneShape(leftDrawn: Array(left.reversed()),rightDrawn: right,backstopDrawn: Array(back.reversed()))
        let swapped = try LaneShape(leftDrawn: right,rightDrawn: Array(left.reversed()),backstopDrawn: back)
        XCTAssertFalse(original.leftWasDrawnAsRight); XCTAssertTrue(swapped.leftWasDrawnAsRight)
        for (x,y) in [(0.0,100.0),(-80,300),(70,50),(0,560),(-60,530)] {
            let a = original.read(at(x,y))
            for other in [reversed,swapped] {
                let b = other.read(at(x,y))
                for role in LaneLimit.allCases { XCTAssertEqual(try XCTUnwrap(a[role]),try XCTUnwrap(b[role]),accuracy: 0.05) }
            }
        }
    }
    func testWalkingSouthSwapsLeftAndRight() throws {
        let s = try LaneShape(leftDrawn: left,rightDrawn: right,backstopDrawn: line((-100,-20),(100,-20)))
        var g = LaneGuideState(shape: s)
        _ = fix(&g,1,80,300)
        XCTAssertEqual(fix(&g,2,80,290).state,.outLeft)
    }
    func testStartsAndExtendedLimits() throws {
        let s = try shape()
        XCTAssertNil(s.read(at(-80,-40)).left)
        XCTAssertNil(s.read(at(80,-40)).right)
        XCTAssertNotNil(s.read(at(0,0)).left)
        let short = try LaneShape(leftDrawn: line((-50,0),(-50,400)),rightDrawn: right,backstopDrawn: back)
        XCTAssertEqual(try XCTUnwrap(short.read(at(-70,470)).left),20,accuracy: 0.2)
        let beyond = try LaneShape(leftDrawn: line((-115,0),(-115,600)),rightDrawn: line((115,0),(115,600)),backstopDrawn: line((-185,560),(215,560)))
        XCTAssertEqual(try XCTUnwrap(beyond.read(at(0,300)).left),-115,accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(beyond.read(at(130,300)).right),15,accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(beyond.read(at(0,580)).backstop),20,accuracy: 0.3)
    }
    func testWarningOncePerApproachAndRearming() throws {
        var config = LaneGuideConfiguration(); config.warningMeters = 25
        var g = LaneGuideState(shape: try shape(),configuration: config)
        XCTAssertNil(fix(&g,1,0,100).warning)
        XCTAssertNil(fix(&g,2,-30,105).warning)
        XCTAssertEqual(fix(&g,3,-31,110).warning,.left)
        XCTAssertNil(fix(&g,4,-32,115).warning)
        XCTAssertNil(fix(&g,5,-18,130).warning)
        XCTAssertNil(fix(&g,6,0,140).warning)
        _ = fix(&g,7,-30,150)
        XCTAssertEqual(fix(&g,8,-30,155).warning,.left)
        _ = fix(&g,9,0,480); _ = fix(&g,10,0,505)
        XCTAssertEqual(fix(&g,11,0,506).warning,.backstop)
    }
    func testUnusableShapesRejectWithActionableReasons() throws {
        XCTAssertThrowsError(try LaneShape(leftDrawn: line((-50,0),(50,500)),rightDrawn: line((50,0),(-50,500)),backstopDrawn: back))
        XCTAssertThrowsError(try LaneShape(leftDrawn: left,rightDrawn: right,backstopDrawn: line((0,-10),(0,600))))
        XCTAssertThrowsError(try LaneShape(leftDrawn: [at(0,0)],rightDrawn: right,backstopDrawn: back))
        XCTAssertThrowsError(try LaneShape(leftDrawn: left,rightDrawn: right,backstopDrawn: [.init(lat: .nan,lon: 0),at(0,0)]))
        XCTAssertThrowsError(try LaneShape(leftDrawn: left,rightDrawn: right,backstopDrawn: [at(0,0),at(0,0)]))
        XCTAssertThrowsError(try LaneShape(leftDrawn: [],rightDrawn: [],backstopDrawn: []))
    }
    func testDatelineAndShadingOutline() throws {
        let p = LaneLocalPlane(origin: .init(lat: -17,lon: 179.9997))
        func d(_ x: Double,_ y: Double) -> GeoPoint { p.unproject(.init(x: x,y: y)) }
        let s = try LaneShape(leftDrawn: [d(-50,0),d(-50,500)],rightDrawn: [d(50,0),d(50,500)],backstopDrawn: [d(-100,520),d(100,520)])
        XCTAssertLessThan(d(50,0).lon,0)
        XCTAssertEqual(try XCTUnwrap(s.read(d(70,250)).right),20,accuracy: 0.5)
        let short = try LaneShape(leftDrawn: line((-50,0),(-50,400)),rightDrawn: right,backstopDrawn: back)
        let ring = short.outline().map(plane.project)
        XCTAssertEqual(ring.count,4)
        for (i,expected) in [(-50.0,0.0),(-50,520),(50,520),(50,0)].enumerated() {
            XCTAssertEqual(ring[i].x,expected.0,accuracy: 0.2); XCTAssertEqual(ring[i].y,expected.1,accuracy: 0.2)
        }
    }
    func testVisibleLimitsReachBackstopAndBentBackstopKeepsItsVertices() throws {
        let short = try LaneShape(leftDrawn: line((-150,0),(-150,200)),rightDrawn: right,backstopDrawn: back)
        let display = short.mapLines()
        XCTAssertEqual(plane.project(try XCTUnwrap(display.left.last)).y,520,accuracy: 0.2)
        XCTAssertEqual(plane.project(try XCTUnwrap(display.backstop.first)).x,-150,accuracy: 0.2)
        XCTAssertEqual(plane.project(try XCTUnwrap(display.backstop.last)).x,100,accuracy: 0.2)
        let bent = try LaneShape(leftDrawn: left,rightDrawn: right,backstopDrawn: line((-100,520),(0,560),(100,520)))
        let ring = bent.outline().map(plane.project)
        XCTAssertEqual(ring.count,5)
        XCTAssertEqual(ring[2].x,0,accuracy: 0.2); XCTAssertEqual(ring[2].y,560,accuracy: 0.2)
        XCTAssertLessThan(try XCTUnwrap(bent.read(at(0,550)).backstop),0)
        XCTAssertGreaterThan(try XCTUnwrap(bent.read(at(0,580)).backstop),0)
        let creek = try LaneShape(leftDrawn: line((-50,0),(-50,200),(-150,300),(-150,500)),rightDrawn: right,backstopDrawn: back)
        let visible = creek.mapLines().left.map(plane.project)
        XCTAssertEqual(visible.count,4)
        XCTAssertEqual(visible[1].x,-50,accuracy: 0.2); XCTAssertEqual(visible[1].y,200,accuracy: 0.2)
        XCTAssertEqual(visible[2].x,-150,accuracy: 0.2); XCTAssertEqual(visible[2].y,300,accuracy: 0.2)
    }
    func testCueCadencePatternsAndReturnToSilence() {
        var c = LaneCueCadence()
        func d(_ state: LaneState,_ changed: Bool = false,_ back: Bool = false,_ warning: LaneLimit? = nil) -> LaneDecision {
            .init(state: state,changed: changed,backInside: back,warning: warning,reading: nil)
        }
        XCTAssertNil(c.next(decision: d(.inside),now: 0))
        XCTAssertEqual(c.next(decision: d(.outLeft,true),now: 1),.turnRight)
        XCTAssertNil(c.next(decision: d(.outLeft),now: 2))
        XCTAssertEqual(c.next(decision: d(.outLeft),now: 3.5),.turnRight)
        XCTAssertEqual(c.next(decision: d(.outRight,true),now: 3.75),.turnLeft)
        XCTAssertEqual(c.next(decision: d(.inside,true,true),now: 4),.backInside)
        for t in stride(from: 4.25,through: 20,by: 0.25) { XCTAssertNil(c.next(decision: d(.inside),now: t)) }
        XCTAssertEqual(c.next(decision: d(.overshot,true),now: 21),.overshot)
        XCTAssertNil(c.next(decision: d(.overshot),now: 24))
        XCTAssertEqual(c.next(decision: d(.overshot),now: 25),.overshot)
        XCTAssertEqual(c.next(decision: d(.inside,false,false,.right),now: 26),.turnLeft)
        XCTAssertNil(c.next(decision: d(.inside),now: 30))
        XCTAssertEqual(LanePulse.turnRight.waveform,[0,70,90,70])
        XCTAssertEqual(LanePulse.turnLeft.waveform,[0,300])
        XCTAssertEqual(LanePulse.overshot.waveform,[0,300,200,300,200,300])
        XCTAssertEqual(LanePulse.backInside.waveform,[0,50])
    }
}
