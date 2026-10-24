import GridFixCore
import ImageIO
import UIKit
import XCTest
@testable import MGRSGPS

private final class DEMNetworkFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var bytes = Data()
    private static var requests = 0
    static func configure(_ data: Data) { lock.lock(); defer { lock.unlock() }; bytes = data; requests = 0 }
    static func count() -> Int { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "s3.amazonaws.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests += 1; let data = Self.bytes; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!,statusCode: 200,httpVersion: "HTTP/1.1",headerFields: ["Content-Type":"image/png"])!
        client?.urlProtocol(self,didReceive: response,cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self,didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class TerrainIntegrationTests: XCTestCase {
    private func encodedTile() throws -> Data {
        var pixels = [UInt8](repeating: 0,count: 256*256*4)
        for y in 0..<256 { for x in 0..<256 { let i = (y*256+x)*4; pixels[i] = 128; pixels[i+1] = y < 128 ? 20 : 200; pixels[i+2] = x < 128 ? 128 : 0; pixels[i+3] = 255 } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 256,height: 256,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: 256*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent))
        return try XCTUnwrap(UIImage(cgImage: image).pngData())
    }
    private func pipeline() throws -> MapTilePipeline {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DEMNetworkFixture.self]
        return MapTilePipeline(directory: dir,library: nil,layers: [],configuration: config)
    }
    func testEncodedTerrainKeepsNorthSouthOrientationAndOfflineCacheNeedsNoNetwork() async throws {
        let data = try encodedTile(), pipeline = try pipeline()
        DEMNetworkFixture.configure(data)
        let raster = try TerrainSampler.Raster.decode(data)
        XCTAssertEqual(raster.heights[0],20.5); XCTAssertEqual(raster.heights[255*256],200.5)
        let tile = MapTile(z: 13,x: 4000,y: 3000)
        try pipeline.terrainCache.store(data,tile: tile); pipeline.offlineOnly = true
        let sampler = TerrainSampler(pipeline: pipeline)
        let north = GeoPoint(lat: MapTile.latitude(3000.25,zoom: 13),lon: MapTile.longitude(4000.5,zoom: 13))
        let south = GeoPoint(lat: MapTile.latitude(3000.75,zoom: 13),lon: north.lon)
        let a = await sampler.elevation(north), b = await sampler.elevation(south)
        XCTAssertEqual(a,20); XCTAssertEqual(b,200); XCTAssertEqual(DEMNetworkFixture.count(),0)
    }
    func testOfflineMissCanRecoverImmediatelyWhenNetworkIsEnabledAndNewSamplerReusesDisk() async throws {
        let data = try encodedTile(), pipeline = try pipeline(), point = GeoPoint(lat: 24,lon: 54)
        DEMNetworkFixture.configure(data); pipeline.offlineOnly = true
        let sampler = TerrainSampler(pipeline: pipeline)
        let missing = await sampler.elevation(point); XCTAssertNil(missing); XCTAssertEqual(DEMNetworkFixture.count(),0)
        pipeline.offlineOnly = false
        let found = await sampler.elevation(point); XCTAssertNotNil(found); XCTAssertEqual(DEMNetworkFixture.count(),1)
        pipeline.offlineOnly = true
        let reopened = TerrainSampler(pipeline: pipeline), again = await reopened.elevation(point)
        XCTAssertEqual(again,found); XCTAssertEqual(DEMNetworkFixture.count(),1)
    }
    func testAbsentTerrainProducesNoSightOrViewshedAndCancellationCannotPublish() async throws {
        let pipeline = try pipeline(); pipeline.offlineOnly = true
        let session = TerrainSession(sampler: TerrainSampler(pipeline: pipeline))
        session.check(observer: .init(lat: 24,lon: 54),target: .init(lat: 24.01,lon: 54),observerHeight: 2,targetHeight: 2)
        for _ in 0..<100 { if !session.busy { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(session.busy); XCTAssertNil(session.sight); XCTAssertNotNil(session.error)
        session.shade(observer: .init(lat: 24,lon: 54),height: 2,radius: 2000) { XCTFail("No data must not publish a shade") }
        session.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(session.busy); XCTAssertNil(session.viewshed)
    }
    func testViewshedPaletteHatchesUnknownAndUsesRedFamilyAtNight() async throws {
        let result = try await TerrainAnalysis.viewshed(observer: .init(lat: 24,lon: 54),radius: 1000,size: 32,rays: 128,elevation: { p in p.lon > 54.001 ? nil : 100 })
        let shade = try XCTUnwrap(result)
        for night in [false,true] {
            let image = try XCTUnwrap(TerrainViewshedRenderer.image(shade,night: night))
            let cg = try XCTUnwrap(image.cgImage), data = try XCTUnwrap(cg.dataProvider?.data)
            let bytes = Array(data as Data)
            XCTAssertTrue(stride(from: 3,to: bytes.count,by: 4).contains { bytes[$0] == 0 })
            XCTAssertTrue(stride(from: 3,to: bytes.count,by: 4).contains { bytes[$0] > 0 })
            if night { for i in stride(from: 0,to: bytes.count,by: 4) where bytes[i+3] > 0 { XCTAssertGreaterThan(bytes[i],bytes[i+1]); XCTAssertGreaterThan(bytes[i],bytes[i+2]) } }
            let attachment = XCTAttachment(image: image); attachment.name = night ? "viewshed-raster-night" : "viewshed-raster-day"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
