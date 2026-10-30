import XCTest
@testable import MGRSGPS

final class WaypointLabelLayoutTests: XCTestCase {
    private let viewport = CGRect(x: 0,y: 0,width: 390,height: 844)
    func testNavigationTargetWinsCollisionRegardlessOfInputOrder() {
        let candidates: [WaypointLabelLayout.Candidate] = [
            .init(id: "a",rect: CGRect(x: 40,y: 100,width: 90,height: 20),priority: false),
            .init(id: "target",rect: CGRect(x: 70,y: 110,width: 90,height: 20),priority: true),
            .init(id: "clear",rect: CGRect(x: 250,y: 100,width: 60,height: 20),priority: false)
        ]
        XCTAssertEqual(WaypointLabelLayout.visible(candidates,in: viewport),["target","clear"])
        XCTAssertEqual(WaypointLabelLayout.visible(Array(candidates.reversed()),in: viewport),["target","clear"])
    }
    func testBoundaryCollisionAndStableOrdinaryPriority() {
        let candidates: [WaypointLabelLayout.Candidate] = [
            .init(id: "b",rect: CGRect(x: 64,y: 64,width: 60,height: 20),priority: false),
            .init(id: "a",rect: CGRect(x: 6,y: 62,width: 60,height: 20),priority: false),
            .init(id: "c",rect: CGRect(x: 130,y: 64,width: 60,height: 20),priority: false)
        ]
        XCTAssertEqual(WaypointLabelLayout.visible(candidates,in: viewport),["a","c"])
    }
    func testClippedAndInvalidCaptionsAreOmittedWithoutConsumingSpace() {
        let candidates: [WaypointLabelLayout.Candidate] = [
            .init(id: "clipped",rect: CGRect(x: -1,y: 50,width: 50,height: 20),priority: true),
            .init(id: "zero",rect: .zero,priority: true),
            .init(id: "infinite",rect: .infinite,priority: true),
            .init(id: "valid",rect: CGRect(x: 1,y: 50,width: 50,height: 20),priority: false)
        ]
        XCTAssertEqual(WaypointLabelLayout.visible(candidates,in: viewport),["valid"])
    }
    func testThousandsOfNoncollidingCaptionsHaveNoCountCap() {
        var candidates: [WaypointLabelLayout.Candidate] = []
        for i in 0..<5000 {
            let x = CGFloat(i % 100) * 80
            let y = CGFloat(i / 100) * 40
            let rect = CGRect(x: x,y: y,width: 60,height: 20)
            candidates.append(.init(id: String(i),rect: rect,priority: false))
        }
        XCTAssertEqual(WaypointLabelLayout.visible(candidates,in: CGRect(x: 0,y: 0,width: 8000,height: 2000)).count,5000)
    }
}
