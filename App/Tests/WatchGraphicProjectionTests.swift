import MapKit
import XCTest
@testable import MGRSGPS

final class WatchGraphicProjectionTests: XCTestCase {
    func testDateLineLegKeepsItsShortGeometryAndEveryBendInBothDirections() {
        let source = [CGPoint(x:980,y:20),CGPoint(x:20,y:40),CGPoint(x:50,y:10)]
        let forward = WatchGraphicProjection.continuous(source,worldWidth:1000,centerX:100)
        XCTAssertEqual(forward,[CGPoint(x:-20,y:20),CGPoint(x:20,y:40),CGPoint(x:50,y:10)])
        let reverse = WatchGraphicProjection.continuous(Array(source.reversed()),worldWidth:1000,centerX:100)
        XCTAssertEqual(reverse,Array(forward.reversed()))
        XCTAssertEqual(source[0].x,980,"Projection must not mutate the cached geographic scene")
        XCTAssertEqual(WatchGraphicProjection.continuous([.init(x:500,y:2)],worldWidth:1000,centerX:0),[.init(x:-500,y:2)])
    }
    func testNativeMercatorScaleProjectsARealDateLineCrossingLocally() {
        let width = MKMapSize.world.width
        let center = MKMapPoint(CLLocationCoordinate2D(latitude:10,longitude:179.99))
        let mapWidth = width/360 * 0.1
        let screenWidth = 162.0
        let coordinates = [179.97,179.99,-179.99,-179.97]
        let raw = coordinates.map { longitude -> CGPoint in
            let point = MKMapPoint(CLLocationCoordinate2D(latitude:10,longitude:longitude))
            return .init(x:(point.x-center.x)/mapWidth*screenWidth+screenWidth/2,y:80)
        }
        let result = WatchGraphicProjection.continuous(raw,worldWidth:width/mapWidth*screenWidth,centerX:screenWidth/2)
        XCTAssertEqual(result.count,4)
        for (i,point) in result.enumerated() {
            XCTAssertEqual(point.x,48.6+Double(i)*32.4,accuracy:0.0001)
            XCTAssertEqual(point.y,80)
        }
    }
    func testInvalidProjectionCannotPublishNaNOrWorldSpanningGeometry() {
        for width in [CGFloat.zero,-1,.infinity,.nan] {
            XCTAssertTrue(WatchGraphicProjection.continuous([.zero],worldWidth:width,centerX:0).isEmpty)
        }
        XCTAssertTrue(WatchGraphicProjection.continuous([.init(x:CGFloat.nan,y:1)],worldWidth:1000,centerX:0).isEmpty)
        XCTAssertTrue(WatchGraphicProjection.continuous([.init(x:1,y:CGFloat.infinity)],worldWidth:1000,centerX:0).isEmpty)
        XCTAssertTrue(WatchGraphicProjection.continuous([.init(x:CGFloat.greatestFiniteMagnitude,y:0)],worldWidth:1000,centerX:-CGFloat.greatestFiniteMagnitude).isEmpty)
    }
}
