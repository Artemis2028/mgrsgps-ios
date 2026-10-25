import GridFixCore
import UIKit
import XCTest
@testable import MGRSGPS

private final class TileNetworkFixture: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var calls = 0
    static var png = Data()
    static var fail = false
    static var hold = false
    private var loading: Task<Void, Never>?
    static func held() -> Bool { lock.lock(); defer { lock.unlock() }; return hold }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "map-fixture.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.calls += 1; let bytes = Self.png, fail = Self.fail; Self.lock.unlock()
        if fail { client?.urlProtocol(self,didFailWithError: URLError(.notConnectedToInternet)); return }
        loading = Task {
            do {
                while Self.held() { try await Task.sleep(nanoseconds: 10_000_000) }
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: request.url!,statusCode: 200,httpVersion: "HTTP/1.1",headerFields: ["Content-Type":"image/png","Cache-Control":"public, max-age=86400"])!
                client?.urlProtocol(self,didReceive: response,cacheStoragePolicy: .allowed)
                client?.urlProtocol(self,didLoad: bytes); client?.urlProtocolDidFinishLoading(self)
            } catch {}
        }
    }
    override func stopLoading() { loading?.cancel(); loading = nil }
}

@MainActor
final class MapLayerIntegrationTests: XCTestCase {
    private var png: Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256,height: 256),format: format).pngData { context in UIColor.green.setFill(); context.fill(CGRect(x: 0,y: 0,width: 256,height: 256)) }
    }
    private var layer: RasterLayer { RasterLayer(key: "usgs",label: "Fixture USGS",attribution: "Synthetic test",template: "https://map-fixture.test/{z}/{x}/{y}.png",maxZoom: 3,maxDownloadZoom: 3,bulkDownload: true) }
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    private func config() -> URLSessionConfiguration {
        TileNetworkFixture.lock.lock(); TileNetworkFixture.calls = 0; TileNetworkFixture.png = png; TileNetworkFixture.fail = false; TileNetworkFixture.hold = false; TileNetworkFixture.lock.unlock()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TileNetworkFixture.self]; return config
    }
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(10)
        while !condition() && Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition())
        if !condition() { throw URLError(.timedOut) }
    }
    func testDownloadReopenAndOfflineOnlyLookupNeverUseNetwork() async throws {
        let dir = try directory(), model = MapLayerStore(directory: dir,installPipeline: false,catalog: [layer],configuration: config())
        let plan = try TileDownloadPlan(bounds: .init(south: 38.89,north: 38.90,west: -77.04,east: -77.03),currentZoom: 3,layer: layer)
        model.startDownload(plan: plan,name: "Patrol area")
        try await wait { model.activeDownload == nil && model.savedMaps.first?.complete == true }
        let reloaded = MapLayerStore(directory: dir,installPipeline: false,catalog: [layer],configuration: config())
        reloaded.setOfflineOnly(true)
        let data = try await reloaded.pipeline.fetch(layer,tile: plan.tiles[0])
        XCTAssertEqual(data,png)
        XCTAssertEqual(TileNetworkFixture.calls,0)
        do { _ = try await reloaded.pipeline.fetch(layer,tile: .init(z: 3,x: 7,y: 0)); XCTFail("An offline miss must fail without network") } catch {}
        XCTAssertEqual(TileNetworkFixture.calls,0)
    }
    private func holdResponses(_ value: Bool) {
        TileNetworkFixture.lock.lock(); TileNetworkFixture.hold = value; TileNetworkFixture.lock.unlock()
    }
    func testCallerCancellationDoesNotCancelOwnedDownloadAndCompletionIsDurable() async throws {
        let dir = try directory(), model = MapLayerStore(directory: dir, installPipeline: false, catalog: [layer], configuration: config())
        let plan = try TileDownloadPlan(bounds: .init(south: 38.89, north: 38.90, west: -77.04, east: -77.03), currentZoom: 3, layer: layer)
        holdResponses(true); defer { holdResponses(false); model.pauseDownload() }
        let caller = Task { @MainActor in
            model.startDownload(plan: plan, name: "Owned area")
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        try await wait { TileNetworkFixture.calls > 0 && model.activeDownload != nil && !model.savedMaps.isEmpty }
        let id = try XCTUnwrap(model.savedMaps.first?.id)
        caller.cancel(); _ = try? await caller.value
        XCTAssertNotNil(model.activeDownload)
        XCTAssertFalse(try XCTUnwrap(model.savedMaps.first).complete)
        holdResponses(false)
        try await wait { model.activeDownload == nil && model.savedMaps.first?.complete == true }
        let reopened = try MapTileLibrary(directory: dir)
        XCTAssertEqual(reopened.maps.count, 1); XCTAssertEqual(reopened.maps.first?.id, id)
        XCTAssertTrue(try XCTUnwrap(reopened.maps.first).complete)
        for tile in plan.tiles { XCTAssertEqual(try reopened.data(for: tile, mapID: id), png) }
        let offline = MapLayerStore(directory: dir, installPipeline: false, catalog: [layer], configuration: config())
        offline.setOfflineOnly(true)
        for tile in plan.tiles { let bytes = try await offline.pipeline.fetch(layer, tile: tile); XCTAssertEqual(bytes, png) }
        XCTAssertEqual(TileNetworkFixture.calls, 0)
    }
    func testExplicitPauseOfPendingDownloadRemainsPartialAndResumeFinishesSameArea() async throws {
        let dir = try directory(), model = MapLayerStore(directory: dir, installPipeline: false, catalog: [layer], configuration: config())
        let plan = try TileDownloadPlan(bounds: .init(south: 38.89, north: 38.90, west: -77.04, east: -77.03), currentZoom: 3, layer: layer)
        holdResponses(true); defer { holdResponses(false); model.pauseDownload() }
        model.startDownload(plan: plan, name: "Paused area")
        try await wait { TileNetworkFixture.calls > 0 && model.savedMaps.count == 1 }
        let id = model.savedMaps[0].id
        model.pauseDownload()
        try await wait { model.activeDownload == nil }
        XCTAssertFalse(model.savedMaps[0].complete)
        XCTAssertEqual(model.message, "Download paused. Saved tiles are kept.")
        XCTAssertFalse(try XCTUnwrap(MapTileLibrary(directory: dir).maps.first).complete)
        holdResponses(false); model.resume(model.savedMaps[0])
        try await wait { model.activeDownload == nil && model.savedMaps[0].complete }
        XCTAssertEqual(model.savedMaps.count, 1); XCTAssertEqual(model.savedMaps[0].id, id)
    }
    func testImportCopySurvivesSourceRemovalAndPreferenceRelaunch() async throws {
        let dir = try directory(), file = dir.appendingPathComponent("Training.mbtiles")
        let db = try MapTileArchive(url: file,create: true)
        try db.setMetadata(["format":"png", "bounds":"-180,-85,180,85"]); try db.put(png,tile: .init(z: 0,x: 0,y: 0))
        let model = MapLayerStore(directory: dir,installPipeline: false,catalog: [layer],configuration: config())
        await model.importMap(file)
        let map = try XCTUnwrap(model.selectedMap)
        model.setGrid(false); model.setOfflineOnly(true)
        try FileManager.default.removeItem(at: file)
        let reopened = MapLayerStore(directory: dir,installPipeline: false,catalog: [layer],configuration: config())
        XCTAssertEqual(reopened.selectedMap?.id,map.id); XCTAssertFalse(reopened.preferences.gridEnabled); XCTAssertTrue(reopened.preferences.offlineOnly)
        let data = try await reopened.pipeline.data(for: URL(string: "https://tiles.gridfix.invalid/local/\(map.id)/0/0/0?effect=day")!)
        XCTAssertEqual(data.0,png); XCTAssertEqual(TileNetworkFixture.calls,0)
        await reopened.delete(map)
        XCTAssertNil(reopened.selectedMap); XCTAssertTrue(reopened.savedMaps.isEmpty)
    }
    func testDownloadFailureKeepsPartialAreaAndRetryFinishesSameId() async throws {
        let dir = try directory(), model = MapLayerStore(directory: dir,installPipeline: false,catalog: [layer],configuration: config())
        let plan = try TileDownloadPlan(bounds: .init(south: 38,north: 39,west: -78,east: -77),currentZoom: 3,layer: layer)
        TileNetworkFixture.fail = true
        model.startDownload(plan: plan,name: "Retry me")
        try await wait { model.activeDownload == nil && !model.savedMaps.isEmpty }
        let map = model.savedMaps[0]
        XCTAssertFalse(map.complete)
        TileNetworkFixture.fail = false; model.resume(map)
        try await wait { model.activeDownload == nil && model.savedMaps[0].complete }
        XCTAssertEqual(model.savedMaps[0].id,map.id); XCTAssertEqual(model.savedMaps.count,1)
    }
    func testNightAndShadowTransformsMatchAndroidChannels() throws {
        let input = png
        let night = try MapTilePipeline.filtered(input,effect: "night")
        let shadow = try MapTilePipeline.filtered(input,effect: "shadow")
        func pixel(_ data: Data) throws -> [UInt8] {
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            var rgba = [UInt8](repeating: 0,count: 4)
            let success = rgba.withUnsafeMutableBytes { buffer -> Bool in
                guard let c = CGContext(data: buffer.baseAddress,width: 1,height: 1,bitsPerComponent: 8,bytesPerRow: 4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                c.draw(image,in: CGRect(x: 0,y: 0,width: 1,height: 1)); return true
            }
            XCTAssertTrue(success); return rgba
        }
        let red = try pixel(night)
        XCTAssertEqual(red[1],0); XCTAssertEqual(red[2],0); XCTAssertEqual(Double(red[0]),87,accuracy: 3)
        let black = try pixel(shadow)
        XCTAssertEqual(black[0],0); XCTAssertEqual(black[1],0); XCTAssertEqual(black[2],0)
    }
    func testBundledGridGlyphsRemainAvailableWithoutNetwork() async throws {
        let model = MapLayerStore(directory: try directory(),installPipeline: false,catalog: [layer],configuration: config())
        model.setOfflineOnly(true)
        let bytes = try await model.pipeline.data(for: URL(string: "https://tiles.gridfix.invalid/fonts/Open%20Sans%20Semibold/0-255.pbf")!)
        XCTAssertGreaterThan(bytes.0.count,1000); XCTAssertEqual(TileNetworkFixture.calls,0)
    }

    func testOfflineOverzoomUsesCorrectSavedParentWithoutNetwork() async throws {
        let dir = try directory(), library = try MapTileLibrary(directory: dir)
        let plan = try TileDownloadPlan(bounds: .init(south: 38.89,north: 38.90,west: -77.04,east: -77.03),currentZoom: 3,layer: layer)
        let map = try library.begin(plan,name: "Overzoom",layer: layer)
        for tile in plan.tiles { try library.store(png,tile: tile,in: map.id) }
        try library.finish(map.id)
        let pipeline = MapTilePipeline(directory: dir,library: library,layers: [layer],configuration: config())
        pipeline.offlineOnly = true
        let parent = plan.tiles[0]
        let data = try await pipeline.fetch(layer,tile: .init(z: parent.z + 1,x: parent.x * 2,y: parent.y * 2))
        XCTAssertEqual(UIImage(data: data)?.cgImage?.width,128)
        XCTAssertEqual(TileNetworkFixture.calls,0)
    }
    func testFailedDownloadDoesNotSaveOverzoomedParentAsNewDetail() async throws {
        let dir = try directory(), library = try MapTileLibrary(directory: dir)
        let bounds = MapBounds(south: 38.89,north: 38.90,west: -77.04,east: -77.03)
        let coarsePlan = try TileDownloadPlan(bounds: bounds,currentZoom: 3,layer: layer)
        let coarse = try library.begin(coarsePlan,name: "Overview",layer: layer)
        for tile in coarsePlan.tiles { try library.store(png,tile: tile,in: coarse.id) }
        try library.finish(coarse.id)
        let detailed = RasterLayer(key: layer.key,label: layer.label,attribution: layer.attribution,
                                   template: layer.template,maxZoom: 4,maxDownloadZoom: 4,bulkDownload: true)
        let model = MapLayerStore(directory: dir,installPipeline: false,catalog: [detailed],configuration: config())
        let plan = try TileDownloadPlan(bounds: bounds,currentZoom: 4,layer: detailed)
        TileNetworkFixture.fail = true
        model.startDownload(plan: plan,name: "Detail")
        try await wait { model.activeDownload == nil && model.savedMaps.count == 2 }
        let map = try XCTUnwrap(model.savedMaps.first { $0.name == "Detail" })
        XCTAssertFalse(map.complete)
        let reopened = try MapTileLibrary(directory: dir)
        XCTAssertNil(try reopened.data(for: plan.tiles[0],mapID: map.id))
        XCTAssertGreaterThan(TileNetworkFixture.calls,0)
    }

    func testContourTileOrientationAndElevationsAreGeographicallyCorrect() throws {
        var pixels = [UInt8](repeating: 0,count: 256 * 256 * 4)
        for y in 0..<256 { for x in 0..<256 {
            let offset = (y * 256 + x) * 4
            pixels[offset] = 128; pixels[offset + 1] = UInt8(y); pixels[offset + 3] = 255
        } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 256,height: 256,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: 1024,
                                         space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent))
        let data = try XCTUnwrap(UIImage(cgImage: image).pngData())
        let tile = MapTile(z: 13,x: 2000,y: 3000)
        let features = try ContourMapOverlay.features(data,tile: tile,interval: 10)
        let label = try XCTUnwrap(features.first { ($0["properties"] as? [String: Any])?["text"] as? String == "50" })
        let point = try XCTUnwrap((label["geometry"] as? [String: Any])?["coordinates"] as? [Double])
        XCTAssertEqual(point[1],MapTile.latitude(3000 + 50.5 / 256,zoom: 13),accuracy: 1e-6)
    }
}
