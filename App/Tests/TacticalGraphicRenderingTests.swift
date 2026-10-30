import CryptoKit
import GridFixCore
import UIKit
import XCTest
@testable import MGRSGPS

@MainActor
final class TacticalGraphicRenderingTests: XCTestCase {
    private func render(_ type: String, night: Bool = false, name: String = "ALPHA", points: [CGPoint]? = nil, numberRouteLegs: Bool = true, routeLegLabels: [String]? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 280,height: 190),format: format).image { r in
            UIColor(night ? .black : .white).setFill(); r.fill(CGRect(x: 0,y: 0,width: 280,height: 190))
            let fallback: [CGPoint]
            if type == "ring" { fallback = [.init(x: 140,y: 105),.init(x: 195,y: 105)] }
            else if GraphicTypes.fixedPoints(type) == 1 { fallback = [.init(x: 130,y: 105)] }
            else { fallback = [.init(x: 45,y: 125),.init(x: 135,y: 70),.init(x: 220,y: 125)] }
            let vertices = points ?? fallback
            let coordinates = vertices.enumerated().map { Backup.GraphicPoint(lat: 24+Double($0.offset)*0.001,lon: 54+Double($0.offset)*0.001) }
            let graphic = Backup.Graphic(id: type,name: name,type: type,points: coordinates,affiliation: "friendly",echelon: "bn")
            TacticalGraphicCanvas.draw(graphic,points: vertices,in: r.cgContext,night: night,lightLines: false,numberRouteLegs:numberRouteLegs,routeLegLabels:routeLegLabels)
        }
    }
    func testEveryAndroidGraphicTypeRendersAndContactSheets() {
        var signatures = Set<String>()
        for type in GraphicTypes.all {
            let image = render(type.key)
            signatures.insert(SHA256.hash(data: image.pngData()!).description)
        }
        XCTAssertEqual(signatures.count,30)
        for night in [false,true] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let sheet = UIGraphicsImageRenderer(size: CGSize(width: 840,height: 2100),format: format).image { r in
                (night ? UIColor.black : .white).setFill(); r.fill(CGRect(x: 0,y: 0,width: 840,height: 2100))
                for (i,type) in GraphicTypes.all.enumerated() {
                    let x = CGFloat(i%3)*280, y = CGFloat(i/3)*210
                    render(type.key,night: night,name: "ALPHA").draw(at: CGPoint(x: x,y: y))
                    (type.label as NSString).draw(at: CGPoint(x: x+8,y: y+185),withAttributes: [.font:UIFont.monospacedSystemFont(ofSize: 11,weight: .bold),.foregroundColor:night ? UIColor.systemRed : .black])
                }
            }
            let attachment = XCTAttachment(image: sheet); attachment.name = night ? "tactical-graphics-night" : "tactical-graphics-day"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testDoctrinePresentationsDifferFromOrdinaryLinesAndLongRoutesRetainLastVertices() {
        for type in ["axis","doa","flot","wire","lane","obstacle_line","screen_l","guard_l","cover_l"] {
            XCTAssertNotEqual(render(type,name: "").pngData(),render("phase_line",name: "").pngData(),type)
        }
        var points = (0..<70).map { CGPoint(x: 30+Double($0),y: 100) }; points.append(CGPoint(x: 250,y: 150))
        XCTAssertNotEqual(render("route",points: points).pngData(),render("route",points: Array(points.prefix(64))).pngData())
    }
    func testSimplifiedWatchRoutesCanSuppressFalseOriginalLegNumbers() throws {
        func ink(_ image: UIImage) throws -> Int {
            let cg = try XCTUnwrap(image.cgImage)
            var bytes = [UInt8](repeating:255,count:280*190*4)
            let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data:buffer.baseAddress,width:280,height:190,bitsPerComponent:8,bytesPerRow:280*4,
                                              space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cg,in:CGRect(x:0,y:0,width:280,height:190)); return true
            }
            XCTAssertTrue(ok)
            var count = 0
            for y in 105..<121 { for x in 137..<162 {
                let i = (y*280+x)*4
                if min(bytes[i],bytes[i+1],bytes[i+2]) < 240 { count += 1 }
            } }
            return count
        }
        let points = [CGPoint(x:45,y:125),CGPoint(x:220,y:125)]
        XCTAssertGreaterThan(try ink(render("route",name:"",points:points)),0)
        XCTAssertEqual(try ink(render("route",name:"",points:points,numberRouteLegs:false)),0,
                       "A thinned watch segment can span several phone legs; never renumber it as a single original leg")
    }
    func testOriginalLegRangesUseSharedRendererWithoutRenumberingThePhone() {
        let points = [CGPoint(x:45,y:125),CGPoint(x:220,y:125)]
        for night in [false,true] {
            let numbered = render("route",night:night,name:"",points:points)
            let ranged = render("route",night:night,name:"",points:points,routeLegLabels:["1–499"])
            let absent = render("route",night:night,name:"",points:points,numberRouteLegs:false)
            XCTAssertNotEqual(numbered.pngData(),ranged.pngData()); XCTAssertNotEqual(absent.pngData(),ranged.pngData())
            XCTAssertEqual(absent.pngData(),render("route",night:night,name:"",points:points,routeLegLabels:[]).pngData())
        }
    }
    func testOffscreenObstacleDecorationDoesNotWalkMillionsOfInvisibleMarks() {
        let start = Date()
        _ = render("wire",points: [.init(x: -1e8,y: 80),.init(x: 1e8,y: 80)])
        XCTAssertLessThan(Date().timeIntervalSince(start),1)
    }
}
