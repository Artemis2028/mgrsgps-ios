import XCTest
import ImageIO
import zlib
@testable import GridFixCore

final class WatchTerrainTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil)))
    }
    private func temporary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    private func center(x: Int = 5333, y: Int = 3521) -> (Double,Double) {
        (MapTile.latitude( Double(y)+128.5/256, zoom: 13),MapTile.longitude( Double(x)+128.5/256, zoom: 13))
    }
    func testSharedGoldenAllFiltersAndIndependentImageDecoder() throws {
        let png = try fixture("terrain-rgba.png"), raster = try WatchTerrainRaster(png: png)
        XCTAssertEqual(WatchTerrainManifest.hash(png),"59c258ba2b1e33867213820615571eb9527b736193e7260c53e437e1a0202b46")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData,nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        let provider = try XCTUnwrap(image.dataProvider), data = try XCTUnwrap(provider.data)
        let pixels = try XCTUnwrap(CFDataGetBytePtr(data))
        XCTAssertEqual(image.bitsPerPixel,32)
        for y in 0..<256 { for x in 0..<256 {
            let expected: Double? = y == 0 && x <= 2 ? nil : -25+Double(x)/4+Double(y)/8
            XCTAssertEqual(raster.elevation(x:x,y:y),expected)
            if let expected {
                let at = y*image.bytesPerRow+x*4
                XCTAssertEqual(Double(pixels[at])*256+Double(pixels[at+1])+Double(pixels[at+2])/256-32768,expected)
            }
        } }
        let rgb = try WatchTerrainRaster(png: fixture("terrain-rgb.png"))
        XCTAssertEqual(rgb.elevation(x:0,y:0),-25); XCTAssertEqual(rgb.elevation(x:1,y:0),-24.75)
        XCTAssertNil(rgb.elevation(x:2,y:0)); XCTAssertNil(rgb.elevation(x:-1,y:0)); XCTAssertNil(rgb.elevation(x:256,y:0))
    }
    func testMalformedCorpusAndExpansionLimits() throws {
        let names = try JSONDecoder().decode([String].self,from: fixture("terrain-invalid.json"))
        for name in names { XCTAssertThrowsError(try WatchTerrainRaster(png:fixture(name)),name) }
        XCTAssertThrowsError(try WatchTerrainRaster(png:Data(repeating:0,count:WatchTerrainRaster.maxBytes+1)))
    }
    func testManifestStrictnessAndCoverage() throws {
        let encoded = try fixture("terrain-manifest.json"), meta = try WatchTerrainManifest.decode(encoded)
        XCTAssertEqual(try WatchTerrainManifest.decode(meta.encoded()),meta)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        let invalid: [(String,Any)] = [("version",2),("revision",9_007_199_254_740_992 as Int64),("publishedAtMillis",9_007_199_254_740_992 as Int64),("revision",1.25),("x",8192),("y",-1),("z",12),("bytes",0),("source","bad/source\n"),("sha256","A"),("attribution","")]
        for (key,value) in invalid {
            var changed = object; changed[key] = value
            XCTAssertThrowsError(try WatchTerrainManifest.decode(JSONSerialization.data(withJSONObject:changed)),key)
        }
        var integral = object; integral["revision"] = 10.0
        XCTAssertEqual(try WatchTerrainManifest.decode(JSONSerialization.data(withJSONObject:integral)).revision,10)
        object["revision"] = 0; XCTAssertThrowsError(try WatchTerrainManifest.decode(JSONSerialization.data(withJSONObject:object)))
        let c = center(), p = try XCTUnwrap(WatchTerrainRaster.pixel(lat:c.0,lon:c.1))
        XCTAssertEqual(p.x,5333); XCTAssertEqual(p.y,3521); XCTAssertEqual(p.px,128); XCTAssertEqual(p.py,128)
        XCTAssertEqual(WatchTerrainRaster.pixel(lat:0,lon:180)?.x,0)
        XCTAssertEqual(WatchTerrainRaster.pixel(lat:0,lon:-180)?.x,0)
        for (lat,lon) in [(Double.nan,0.0),(86,0),(0,181),(0,Double.infinity)] { XCTAssertNil(WatchTerrainRaster.pixel(lat:lat,lon:lon)) }
    }
    func testAtomicRecordRelaunchSourceRevisionAndCorruption() throws {
        let dir = try temporary(), png = try fixture("terrain-rgba.png"), meta = try WatchTerrainManifest.decode(fixture("terrain-manifest.json"))
        let cache = try WatchTerrainCache(directory:dir), c = center()
        XCTAssertNil(cache.sample(source:meta.source,lat:c.0,lon:c.1))
        try cache.install(manifest:meta,png:png,expectedSource:meta.source)
        let sample = try XCTUnwrap(try WatchTerrainCache(directory:dir).sample(source:meta.source,lat:c.0,lon:c.1))
        XCTAssertEqual(sample.meters,23); XCTAssertEqual(sample.manifest,meta)
        XCTAssertNil(cache.sample(source:"other",lat:c.0,lon:c.1))
        XCTAssertNil(cache.sample(source:meta.source,lat:c.0,lon:c.1+1))
        try cache.install(manifest:meta,png:png,expectedSource:meta.source)
        XCTAssertThrowsError(try cache.install(manifest:meta,png:png,expectedSource:"other"))
        XCTAssertThrowsError(try cache.install(manifest:meta,png:Data(png.dropLast()),expectedSource:meta.source))
        for rev: Int64 in [9,10] {
            let changed = WatchTerrainManifest(source:meta.source,revision:rev,publishedAtMillis:meta.publishedAtMillis+1,x:meta.x,y:meta.y,png:png,attribution:meta.attribution)
            XCTAssertThrowsError(try cache.install(manifest:changed,png:png,expectedSource:meta.source))
        }
        XCTAssertEqual(cache.sample(source:meta.source,lat:c.0,lon:c.1)?.meters,23)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).first)
        var corrupt = try Data(contentsOf:file); corrupt[corrupt.count-1] ^= 1; try corrupt.write(to:file)
        XCTAssertNil(try WatchTerrainCache(directory:dir).sample(source:meta.source,lat:c.0,lon:c.1))
        try cache.install(manifest:meta,png:png,expectedSource:meta.source)
        XCTAssertEqual(cache.sample(source:meta.source,lat:c.0,lon:c.1)?.meters,23)
        try FileManager.default.removeItem(at:file)
        XCTAssertNil(cache.sample(source:meta.source,lat:c.0,lon:c.1))
    }
    func testRejectedTerrainReplacementPreservesWarmAndColdTileUntilValidNewRevision() throws {
        let dir = try temporary(), cache = try WatchTerrainCache(directory: dir)
        let png = try fixture("terrain-rgba.png")
        let meta = try WatchTerrainManifest.decode(fixture("terrain-manifest.json"))
        let c = center()
        try cache.install(manifest: meta, png: png, expectedSource: meta.source)
        XCTAssertEqual(cache.sample(source: meta.source, lat: c.0, lon: c.1)?.meters, 23)
        let record = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        let before = try Data(contentsOf: record)
        // A matching manifest/hash must not allow malformed raster data to
        // replace a valid tile; exercise decoder failure after envelope checks.
        let malformed = Data(png.dropLast())
        let invalid = WatchTerrainManifest(source: meta.source, revision: meta.revision + 1,
            publishedAtMillis: meta.publishedAtMillis + 1, x: meta.x, y: meta.y,
            png: malformed, attribution: meta.attribution)
        XCTAssertThrowsError(try cache.install(manifest: invalid, png: malformed, expectedSource: meta.source))
        let wrongSource = WatchTerrainManifest(source: "other-companion", revision: meta.revision + 2,
            publishedAtMillis: meta.publishedAtMillis + 2, x: meta.x, y: meta.y,
            png: png, attribution: meta.attribution)
        XCTAssertThrowsError(try cache.install(manifest: wrongSource, png: png, expectedSource: meta.source))
        let conflict = WatchTerrainManifest(source: meta.source, revision: meta.revision,
            publishedAtMillis: meta.publishedAtMillis + 3, x: meta.x, y: meta.y,
            png: png, attribution: meta.attribution)
        XCTAssertThrowsError(try cache.install(manifest: conflict, png: png, expectedSource: meta.source))
        XCTAssertEqual(try Data(contentsOf: record), before)
        for reader in [cache, try WatchTerrainCache(directory: dir)] {
            XCTAssertEqual(reader.sample(source: meta.source, lat: c.0, lon: c.1)?.manifest, meta)
            XCTAssertEqual(reader.sample(source: meta.source, lat: c.0, lon: c.1)?.meters, 23)
            XCTAssertNil(reader.sample(source: wrongSource.source, lat: c.0, lon: c.1))
        }
        let newer = WatchTerrainManifest(source: meta.source, revision: meta.revision + 1,
            publishedAtMillis: meta.publishedAtMillis + 4, x: meta.x, y: meta.y,
            png: png, attribution: "Updated synthetic provenance")
        try cache.install(manifest: newer, png: png, expectedSource: meta.source)
        for reader in [cache, try WatchTerrainCache(directory: dir)] {
            XCTAssertEqual(reader.sample(source: meta.source, lat: c.0, lon: c.1)?.manifest, newer)
            XCTAssertEqual(reader.sample(source: meta.source, lat: c.0, lon: c.1)?.meters, 23)
        }
    }
    func testQueuedCompletionCannotReplaceNewRequestStatusEvenBeforeRevisionPublication() {
        var owner = WatchTerrainOutboxOwner()
        let old = URL(fileURLWithPath: "/synthetic/outbox/old.png")
        owner.begin()
        let oldToken = owner.generation
        XCTAssertTrue(owner.register(old, generation: oldToken))
        // New Send supersedes the old request immediately. No successful new
        // manifest/revision publication is required: preparation may fail.
        owner.begin()
        let token = owner.generation
        XCTAssertNotEqual(token, oldToken)
        XCTAssertFalse(owner.consume(old), "Late completion must not overwrite preparing/error status")
        XCTAssertFalse(owner.register(old, generation: oldToken), "An old asynchronous fallback cannot queue under a newer request")
        let current = URL(fileURLWithPath: "/synthetic/outbox/current.png")
        XCTAssertTrue(owner.register(current, generation: token))
        XCTAssertTrue(owner.consume(current), "Current queued completion may update transport status")
        XCTAssertFalse(owner.consume(current), "Duplicate completion has no status ownership")
    }
    func testInactiveAndColdSessionCompletionsOnlyPermitIndependentFileCleanup() {
        let file = URL(fileURLWithPath: "/synthetic/outbox/queued.png")
        var owner = WatchTerrainOutboxOwner()
        XCTAssertTrue(owner.register(file, generation: owner.generation))
        owner.begin() // The bridge uses the same invalidation on session inactivity.
        XCTAssertFalse(owner.consume(file))
        var reopened = WatchTerrainOutboxOwner()
        XCTAssertFalse(reopened.consume(file), "Cold SDK transfer completion cannot claim an active Send")
        let unknown = URL(fileURLWithPath: "/synthetic/outbox/unknown.png")
        XCTAssertFalse(owner.consume(unknown))
    }
    func testTileCountAndByteBudgetsRetainNewestWithoutTouchingUnownedFiles() throws {
        let dir = try temporary(), cache = try WatchTerrainCache(directory:dir), png = try fixture("terrain-rgba.png")
        let keep = dir.appendingPathComponent("notes.txt"); try Data("keep".utf8).write(to:keep)
        for x in 5300..<5317 {
            let m = WatchTerrainManifest(source:"fixture",revision:1,publishedAtMillis:1,x:x,y:3521,png:png,attribution:"Synthetic")
            try cache.install(manifest:m,png:png,expectedSource:"fixture")
        }
        func records() throws -> [URL] { try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).filter { $0.pathExtension == "terrain" } }
        XCTAssertEqual(try records().count,16); XCTAssertTrue(FileManager.default.fileExists(atPath:keep.path))
        // A legal ancillary payload tests the aggregate byte cap using real valid PNGs.
        let payload = Data(repeating:0,count:3*1024*1024), type = Data("tEXt".utf8)
        var crcData = type; crcData.append(payload)
        let crc = crcData.withUnsafeBytes { UInt32(zlib.crc32(0,$0.bindMemory(to:Bytef.self).baseAddress,uInt(crcData.count))) }
        func be(_ n: UInt32) -> Data { Data([UInt8((n>>24)&255),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)]) }
        var padded = Data(png.prefix(33)); padded.append(be(UInt32(payload.count))); padded.append(crcData); padded.append(be(crc)); padded.append(png.dropFirst(33))
        for x in 5400..<5412 {
            let m = WatchTerrainManifest(source:"fixture",revision:1,publishedAtMillis:1,x:x,y:3521,png:padded,attribution:"Synthetic")
            try cache.install(manifest:m,png:padded,expectedSource:"fixture")
        }
        let files = try records(); let bytes = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(files.count,16); XCTAssertLessThanOrEqual(bytes,32*1024*1024)
        let c = center(x:5411); XCTAssertEqual(cache.sample(source:"fixture",lat:c.0,lon:c.1)?.meters,23)
    }
}
