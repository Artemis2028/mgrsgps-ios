import GridFixCore
import MapLibre
import UIKit
import XCTest
@testable import MGRSGPS

@MainActor
final class MapLassoOverlayTests: XCTestCase {
    private final class Pan: UIPanGestureRecognizer {
        var phase: UIGestureRecognizer.State = .possible
        var point = CGPoint.zero
        override var state: UIGestureRecognizer.State { get { phase } set { phase = newValue } }
        override func location(in view: UIView?) -> CGPoint { point }
    }
    func testNativePanLoopProjectsSelectsAndCancelledGestureCannotPublish() async throws {
        let style = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
        try Data(#"{"version":8,"sources":{},"layers":[]}"#.utf8).write(to: style)
        defer { try? FileManager.default.removeItem(at: style) }
        let map = MLNMapView(frame: CGRect(x: 0,y: 0,width: 400,height: 600),styleURL: style)
        map.setCenter(.init(latitude: 24.4539,longitude: 54.3773),zoomLevel: 16,animated: false)
        let overlay = MapLassoOverlay(frame: map.bounds); overlay.map = map; map.addSubview(overlay)
        overlay.waypoints = [.init(id: "inside",name: "Inside",lat: 24.4539,lon: 54.3773),
                             .init(id: "outside",name: "Outside",lat: 24.4639,lon: 54.3773)]
        overlay.update(active: true,selection: nil,night: false,selectVisibleRequest: nil,finishLoopRequest: nil)
        let centre = map.convert(CLLocationCoordinate2D(latitude: 24.4539,longitude: 54.3773),toPointTo: overlay)
        XCTAssertTrue(centre.x.isFinite && centre.y.isFinite)
        let gesture = Pan(), selector = NSSelectorFromString("pan:")
        var received: [LibrarySelection] = []; overlay.onSelect = { received.append($0) }
        func send(_ phase: UIGestureRecognizer.State,_ x: Double,_ y: Double) {
            gesture.phase = phase; gesture.point = .init(x: centre.x+x,y: centre.y+y)
            overlay.perform(selector,with: gesture)
        }
        send(.began,-40,-40); send(.changed,40,-40); send(.cancelled,40,40)
        XCTAssertTrue(received.isEmpty); XCTAssertTrue(overlay.loop.isEmpty)
        send(.began,-40,-40); send(.changed,40,-40); send(.changed,40,40); send(.changed,-40,40); send(.ended,-40,-40)
        XCTAssertEqual(received.count,1); XCTAssertEqual(received.first?.waypoints,["inside"])
        XCTAssertTrue(overlay.loop.isEmpty)
        // Further drags cannot replace a reviewed selection until Again.
        send(.began,-100,-100); send(.changed,100,-100); send(.ended,0,100)
        XCTAssertEqual(received.count,1)
        overlay.update(active: false,selection: nil,night: true,selectVisibleRequest: nil,finishLoopRequest: nil)
        XCTAssertFalse(overlay.isUserInteractionEnabled); XCTAssertTrue(overlay.isHidden)
        send(.began,0,0); XCTAssertTrue(overlay.loop.isEmpty)
        // A deferred Select visible from an old presentation must not select
        // into a newly reopened lasso on the next UI turn.
        overlay.update(active: true,selection: nil,night: false,selectVisibleRequest: UUID(),finishLoopRequest: nil)
        overlay.update(active: false,selection: nil,night: false,selectVisibleRequest: nil,finishLoopRequest: nil)
        overlay.update(active: true,selection: nil,night: false,selectVisibleRequest: nil,finishLoopRequest: nil)
        let drained = expectation(description: "queued UI requests drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained],timeout: 3)
        XCTAssertEqual(received.count,1)
    }
}
