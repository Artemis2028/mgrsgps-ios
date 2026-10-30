import XCTest
@testable import GridFixCore

final class BoundaryTests: XCTestCase {
    private func p(_ x: Double,_ y: Double) -> GeoPoint { GeoPoint(lat: y / 111_319.49,lon: x / 111_319.49) }
    private var square: [GeoPoint] { [p(0,0),p(100,0),p(100,100),p(0,100)] }
    func testStraightPerimeterDistanceAndBothWindingDirections() throws {
        for vertices in [square,Array(square.reversed())] {
            let g = try BoundaryGeometry(vertices: vertices)
            XCTAssertEqual(try XCTUnwrap(g.signedDistance(to: p(50,50))),50,accuracy: 0.02)
            XCTAssertEqual(try XCTUnwrap(g.signedDistance(to: p(150,50))),-50,accuracy: 0.02)
            XCTAssertEqual(try XCTUnwrap(g.signedDistance(to: p(50,0))),0,accuracy: 0.02)
            XCTAssertLessThan(try XCTUnwrap(g.signedDistance(to: p(150,150))),-70)
        }
    }
    func testKinkConcavityAndEndBackstop() throws {
        let g = try BoundaryGeometry(vertices: [p(0,0),p(100,0),p(100,40),p(40,40),p(40,100),p(0,100)])
        XCTAssertGreaterThan(try XCTUnwrap(g.signedDistance(to: p(20,80))),0)
        XCTAssertLessThan(try XCTUnwrap(g.signedDistance(to: p(80,80))),0)
        XCTAssertLessThan(try XCTUnwrap(g.signedDistance(to: p(20,120))),0)
        XCTAssertLessThan(try XCTUnwrap(g.signedDistance(to: p(-20,20))),0)
    }
    func testDatelineBoundaryDoesNotEncloseTheOtherSideOfWorld() throws {
        let v = [GeoPoint(lat: 10,lon: 179.99),GeoPoint(lat: 10,lon: -179.99),GeoPoint(lat: 10.02,lon: -179.99),GeoPoint(lat: 10.02,lon: 179.99)]
        let g = try BoundaryGeometry(vertices: v)
        XCTAssertGreaterThan(try XCTUnwrap(g.signedDistance(to: .init(lat: 10.01,lon: 180))),0)
        XCTAssertGreaterThan(try XCTUnwrap(g.signedDistance(to: .init(lat: 10.01,lon: -180))),0)
        XCTAssertLessThan(try XCTUnwrap(g.signedDistance(to: .init(lat: 10.01,lon: 0))),0)
    }
    func testInvalidAndSelfTouchingPerimetersAreRejected() {
        let invalid: [[GeoPoint]] = [[],[p(0,0),p(1,1)], [p(0,0),p(100,100),p(100,0),p(0,100)],
            [p(0,0),p(100,0),p(20,0),p(0,100)], [p(0,0),p(100,0),p(100,100),p(50,0),p(0,100)],
            [p(0,0),p(0,0),p(100,100)], [p(0,0),p(1,0),p(1,1)],
            [p(0,0),p(200_000,0),p(0,200_000)], [.init(lat: .nan,lon: 0),p(100,0),p(0,100)],
            [.init(lat: 89,lon: 0),.init(lat: 89,lon: 1),.init(lat: 88,lon: 0)]]
        for vertices in invalid { XCTAssertThrowsError(try BoundaryGeometry(vertices: vertices)) }
    }
    func testConfirmedExitOnlyOnceAndReentryRearms() throws {
        var d = try BoundaryCrossingDetector(vertices: square)
        func sample(_ x: Double,_ y: Double,_ t: Double) -> BoundaryCrossingDetector.Result {
            d.update(point: p(x,y),accuracy: 2,timestamp: t,now: t)
        }
        XCTAssertEqual(sample(50,50,0),.confirming(.inside))
        XCTAssertEqual(sample(50,50,2),.inside)
        XCTAssertEqual(sample(150,50,3),.confirming(.outside))
        XCTAssertEqual(sample(150,50,5),.exited)
        XCTAssertEqual(sample(160,80,6),.outside)
        XCTAssertEqual(sample(50,50,7),.confirming(.inside))
        XCTAssertEqual(sample(50,50,9),.inside)
        XCTAssertEqual(sample(50,150,10),.confirming(.outside))
        XCTAssertEqual(sample(50,150,12),.exited)
    }
    func testStartingOutsideNeverBuzzesUntilAnInsideThenExitTransition() throws {
        var d = try BoundaryCrossingDetector(vertices: square)
        XCTAssertEqual(d.update(point: p(150,50),accuracy: 2,timestamp: 1,now: 1),.confirming(.outside))
        XCTAssertEqual(d.update(point: p(150,50),accuracy: 2,timestamp: 3,now: 3),.outside)
        XCTAssertEqual(d.update(point: p(170,50),accuracy: 2,timestamp: 5,now: 5),.outside)
    }
    func testAccuracyOverlapAndEdgeJitterCannotConfirmExit() throws {
        var d = try BoundaryCrossingDetector(vertices: square)
        _ = d.update(point: p(50,50),accuracy: 2,timestamp: 0,now: 0)
        _ = d.update(point: p(50,50),accuracy: 2,timestamp: 2,now: 2)
        for i in 3...20 {
            let r = d.update(point: p(i % 2 == 0 ? 99 : 101,50),accuracy: 5,timestamp: Double(i),now: Double(i))
            XCTAssertEqual(r,.edge)
        }
        XCTAssertEqual(d.stableSide,.inside)
    }
    func testInvalidStaleReorderedAndGappedFixesDoNotProduceCrossings() throws {
        var d = try BoundaryCrossingDetector(vertices: square)
        _ = d.update(point: p(50,50),accuracy: 2,timestamp: 0,now: 0)
        _ = d.update(point: p(50,50),accuracy: 2,timestamp: 2,now: 2)
        XCTAssertEqual(d.update(point: p(150,50),accuracy: 40,timestamp: 4,now: 4),.unknown)
        XCTAssertEqual(d.update(point: p(150,50),accuracy: 2,timestamp: 4,now: 20),.unknown)
        XCTAssertEqual(d.update(point: p(150,50),accuracy: 2,timestamp: 1,now: 2),.unknown)
        XCTAssertEqual(d.update(point: p(150,50),accuracy: 2,timestamp: 20,now: 20),.confirming(.outside))
        XCTAssertEqual(d.update(point: p(150,50),accuracy: 2,timestamp: 40,now: 40),.confirming(.outside))
        XCTAssertEqual(d.update(point: p(150,50),accuracy: 2,timestamp: 42,now: 42),.exited)
    }
    func testEverySideAndClosingBackstopCanTriggerAnExit() throws {
        for outside in [p(-20,50),p(120,50),p(50,-20),p(50,120)] {
            var d = try BoundaryCrossingDetector(vertices: square)
            _ = d.update(point: p(50,50),accuracy: 2,timestamp: 1,now: 1)
            _ = d.update(point: p(50,50),accuracy: 2,timestamp: 3,now: 3)
            _ = d.update(point: outside,accuracy: 2,timestamp: 4,now: 4)
            XCTAssertEqual(d.update(point: outside,accuracy: 2,timestamp: 6,now: 6),.exited)
        }
    }
}
