import CryptoKit
import GridFixCore
import UIKit
import XCTest
@testable import MGRSGPS

@MainActor
final class MilitarySymbolsTests: XCTestCase {
    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0,count: cg.width*cg.height*4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress,width: cg.width,height: cg.height,bitsPerComponent: 8,bytesPerRow: cg.width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            c.draw(cg,in: CGRect(x: 0,y: 0,width: cg.width,height: cg.height)); return true
        }
        XCTAssertTrue(success); return bytes
    }
    func testEntireAndroidUnitCatalogIsBundledAndMatchesSourceHashes() throws {
        XCTAssertEqual(MilitarySymbols.functions.count,124); XCTAssertEqual(MilitarySymbols.unitKeys.count,496)
        let file = try XCTUnwrap(Bundle.main.url(forResource: "military-symbol-manifest",withExtension: "json",subdirectory: "MilitarySymbols"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let hashes = try XCTUnwrap(manifest["files"] as? [String: String])
        XCTAssertEqual(hashes.count,496)
        for key in MilitarySymbols.unitKeys {
            let source = try XCTUnwrap(Bundle.main.url(forResource: key,withExtension: "png",subdirectory: "MilitarySymbols"),key)
            let hash = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x",$0) }.joined()
            XCTAssertEqual(hash,hashes[key+".png"],key)
            XCTAssertNotNil(MilitaryMarkerRenderer.unitImage(key,night: false),key)
        }
    }
    func testBlackBackgroundBecomesTransparentAndNightHasOnlyRed() throws {
        for key in ["nato_f_inf","nato_h_armor","nato_n_eng_cbt","nato_u_sf"] {
            let day = try pixels(XCTUnwrap(MilitaryMarkerRenderer.unitImage(key,night: false)))
            let night = try pixels(XCTUnwrap(MilitaryMarkerRenderer.unitImage(key,night: true)))
            XCTAssertTrue(stride(from: 3,to: day.count,by: 4).contains { day[$0] == 0 },key)
            XCTAssertTrue(stride(from: 3,to: day.count,by: 4).contains { day[$0] > 0 },key)
            for i in stride(from: 0,to: night.count,by: 4) { XCTAssertEqual(night[i+1],0); XCTAssertEqual(night[i+2],0); XCTAssertEqual(night[i+3],day[i+3]) }
        }
    }
    func testEveryTaskHasDistinctArtworkAndRotationChangesDirectionalTasks() throws {
        XCTAssertEqual(MilitarySymbols.tasks.count,20)
        for bitmapContext in [false,true] {
            var signatures = Set<String>()
            for entry in MilitarySymbols.tasks {
                let data = try XCTUnwrap(MilitaryMarkerRenderer.image(symbol: entry.key,bitmapContext: bitmapContext).pngData())
                signatures.insert(SHA256.hash(data: data).description)
            }
            XCTAssertEqual(signatures.count,20)
        }
        let normal = MilitaryMarkerRenderer.image(symbol: "task_sbf",rotation: 0).pngData()
        let turned = MilitaryMarkerRenderer.image(symbol: "task_sbf",rotation: 90).pngData()
        XCTAssertNotEqual(normal,turned)
        XCTAssertNotEqual(MilitaryMarkerRenderer.image(symbol: "nato_f_inf",echelon: "plt").pngData(),MilitaryMarkerRenderer.image(symbol: "nato_f_inf",echelon: "bn").pngData())
    }
    func testImportedCharactersRemainBlackAndLegible() throws {
        let code = MilGpsSymbols.encode(shape: .circle,character: "6")
        let plain = try pixels(MilitaryMarkerRenderer.image(symbol: "flag",metadata: .init(color: "yellow",milgpsSymbolCode: 1000)))
        let numbered = try pixels(MilitaryMarkerRenderer.image(symbol: "flag",metadata: .init(color: "yellow",milgpsSymbolCode: code)))
        XCTAssertNotEqual(plain,numbered)
        func blackPixelCount(_ bytes: [UInt8]) -> Int {
            var count = 0
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let opaque = bytes[i + 3] > 200
                let black = bytes[i] < 20 && bytes[i + 1] < 20 && bytes[i + 2] < 20
                if opaque && black { count += 1 }
            }
            return count
        }
        XCTAssertGreaterThan(blackPixelCount(numbered), blackPixelCount(plain))
    }
    func testRenderCatalogContactSheets() {
        var items = (MilitarySymbols.tasks + MilitarySymbols.basic).map { ($0.key,"none","") }
        for aff in ["f","h","n","u"] { for function in ["inf_abn","armor","eng_cbt"] { items.append(("nato_\(aff)_\(function)","none","")) } }
        for echelon in MilitarySymbols.echelons { items.append(("nato_f_inf","friendly",echelon.key)) }
        for bitmapContext in [false,true] {
        for night in [false,true] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600,height: 1200),format: format).image { context in
                UIColor.black.setFill(); context.fill(CGRect(x: 0,y: 0,width: 600,height: 1200))
                for (i,item) in items.enumerated() {
                    let x = Double(i%6)*100, y = Double(i/6)*120
                    MilitaryMarkerRenderer.image(symbol: item.0,affiliation: item.1,echelon: item.2,night: night,bitmapContext: bitmapContext).draw(in: CGRect(x: x+18,y: y+4,width: 64,height: 64))
                    ((item.0 + " " + item.2) as NSString).draw(in: CGRect(x: x+3,y: y+75,width: 94,height: 40),withAttributes: [.font:UIFont.monospacedSystemFont(ofSize: 9,weight: .regular),.foregroundColor:UIColor.white])
                }
            }
            let attachment = XCTAttachment(image: image); attachment.name = (bitmapContext ? "watch-bitmap-" : "phone-") + (night ? "military-catalog-night" : "military-catalog-day"); attachment.lifetime = .keepAlways; add(attachment)
        }
        }
    }
    func testWatchBitmapContextPreservesTaskOrientationFramesAndImportedArtwork() throws {
        let symbols = MilitarySymbols.tasks.map(\.key) + ["dot","diamond","nato_f_inf"]
        for symbol in symbols {
            let phone = try pixels(MilitaryMarkerRenderer.image(symbol: symbol,affiliation: "friendly",echelon: "plt",rotation: 90))
            let watch = try pixels(MilitaryMarkerRenderer.image(symbol: symbol,affiliation: "friendly",echelon: "plt",rotation: 90,bitmapContext: true))
            // Different color spaces may round RGB. Alpha must occupy the same pixels,
            // detecting a vertically flipped bitmap or misplaced UIKit text/image draw.
            for i in stride(from: 3,to: phone.count,by: 4) {
                XCTAssertLessThanOrEqual(abs(Int(phone[i])-Int(watch[i])),2,symbol)
            }
        }
        let plain = MilitaryMarkerRenderer.image(symbol: "dot",bitmapContext: true).pngData()
        let framed = MilitaryMarkerRenderer.image(symbol: "dot",affiliation: "hostile",bitmapContext: true).pngData()
        XCTAssertNotEqual(plain,framed)
        let code = MilGpsSymbols.encode(shape: .triangle,character: "6")
        let metadata = WaypointMetadata(color: "cyan",milgpsSymbolCode: code)
        let phone = try pixels(MilitaryMarkerRenderer.image(symbol: "flag",metadata: metadata))
        let watch = try pixels(MilitaryMarkerRenderer.image(symbol: "flag",metadata: metadata,bitmapContext: true))
        XCTAssertEqual(phone,watch)
        XCTAssertNotEqual(MilitaryMarkerRenderer.image(symbol: "task_abf",rotation: 0,bitmapContext: true).pngData(),
                          MilitaryMarkerRenderer.image(symbol: "task_abf",rotation: 90,bitmapContext: true).pngData())
        XCTAssertEqual(MilitaryMarkerRenderer.image(symbol: "task_abf",rotation: -90,bitmapContext: true).pngData(),
                       MilitaryMarkerRenderer.image(symbol: "task_abf",rotation: 270,bitmapContext: true).pngData())
        XCTAssertEqual(MilitaryMarkerRenderer.image(symbol: "task_abf",rotation: Double.greatestFiniteMagnitude,bitmapContext: true).pngData(),
                       MilitaryMarkerRenderer.image(symbol: "task_abf",rotation: Double.greatestFiniteMagnitude.truncatingRemainder(dividingBy:360),bitmapContext: true).pngData())
        XCTAssertEqual(MilitaryMarkerRenderer.image(symbol: "task_screen",rotation: 0,bitmapContext: true).pngData(),
                       MilitaryMarkerRenderer.image(symbol: "task_screen",rotation: 90,bitmapContext: true).pngData(),"Android letter badges remain upright")
    }
    func testUnknownSymbolsArePreservedAndDoNotMasqueradeAsFlag() {
        XCTAssertEqual(MilitarySymbols.label("legacy_custom"),"legacy_custom")
        XCTAssertNotEqual(MilitaryMarkerRenderer.image(symbol: "legacy_custom").pngData(),MilitaryMarkerRenderer.image(symbol: "flag").pngData())
        XCTAssertNotEqual(MilitaryMarkerRenderer.image(symbol: "legacy_custom",bitmapContext: true).pngData(),MilitaryMarkerRenderer.image(symbol: "flag",bitmapContext: true).pngData())
        XCTAssertEqual(MilitarySymbols.label("nato_h_inf_abn"),"Hostile Airborne infantry")
    }
}
