import GridFixCore
import UIKit
import XCTest
@testable import MGRSGPS

@MainActor
final class FieldOverlayPreparationTests: XCTestCase {
    private func document(count: Int = 2) -> Backup.Document {
        let id = UUID().uuidString.lowercased()
        return Backup.Document(tracks: [.init(id: id,name: "Patrol",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: count)],
                               trackFiles: [id: Data(String(repeating: "24 54 0\n",count: count).utf8)])
    }
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !predicate(),Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(predicate())
    }
    func testHiddenReplacementWinsEvenWhenOldWorkerIgnoresCancellation() async throws {
        let gate = MapPreparationGate(); defer { gate.release() }
        let overlay = FieldOverlay(prepare: gate.prepare)
        var counts: [Int] = []
        overlay.onChange = { _,tracks,_ in XCTAssertTrue(Thread.isMainThread); counts.append(tracks) }
        overlay.update(document: document(),folders: [],night: false)
        try await wait { gate.entered }
        overlay.update(document: Backup.Document(),folders: [],night: true)
        XCTAssertTrue(overlay.points.isEmpty)
        try await wait { !overlay.preparing }
        gate.release(); try await wait { gate.finished }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(overlay.tracks,0); XCTAssertTrue(overlay.points.isEmpty)
        XCTAssertTrue(counts.allSatisfy { $0 == 0 },"The old noncooperative worker must not restore hidden geometry")
    }
    func testLargeLogPreparesOffMainAndThemeUpdatesReuseIt() async throws {
        let counter = MapPreparationCounter()
        let overlay = FieldOverlay { document,folders in
            XCTAssertFalse(Thread.isMainThread); counter.next()
            return try FieldMapGeometry.prepareOverlay(document: document,folders: folders)
        }
        let source = document(count: 300_001),start = Date()
        overlay.update(document: source,folders: [],night: false)
        XCTAssertLessThan(Date().timeIntervalSince(start),0.2)
        var pulses = 0,maximumGap = 0.0,last = Date()
        while overlay.preparing {
            try await Task.sleep(nanoseconds: 5_000_000)
            maximumGap = max(maximumGap,Date().timeIntervalSince(last)); last = Date(); pulses += 1
        }
        XCTAssertNil(overlay.error); XCTAssertEqual(overlay.tracks,1)
        XCTAssertLessThanOrEqual(overlay.points.count,6); XCTAssertGreaterThan(pulses,1)
        XCTAssertLessThan(maximumGap,0.25)
        overlay.update(document: source,folders: [],night: true)
        XCTAssertEqual(counter.count,1); XCTAssertFalse(overlay.preparing)
        let attachment = XCTAttachment(string: "Main pulses: \(pulses); maximum gap: \(maximumGap)")
        attachment.name = "map-track-worker-benchmark"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFailureClearsOldStateAndExplicitRetryCanPrepareSameDocument() async throws {
        let counter = MapPreparationCounter(),source = document()
        let overlay = FieldOverlay { document,folders in
            if counter.next() == 1 { throw CocoaError(.fileReadCorruptFile) }
            return try FieldMapGeometry.prepareOverlay(document: document,folders: folders)
        }
        overlay.update(document: source,folders: [],night: false)
        try await wait { !overlay.preparing }
        XCTAssertNotNil(overlay.error); XCTAssertTrue(overlay.points.isEmpty)
        overlay.update(document: source,folders: [],night: true)
        XCTAssertEqual(counter.count,1,"GPS/theme refresh must not spin a failed preparation")
        overlay.update(document: source,folders: [],night: true,retryToken: UUID())
        try await wait { !overlay.preparing }
        XCTAssertNil(overlay.error); XCTAssertEqual(overlay.tracks,1); XCTAssertEqual(counter.count,2)
    }
    func testReleasedOverlayCannotBeRetainedOrPublishedByHeldWorker() async throws {
        let gate = MapPreparationGate(); defer { gate.release() }
        var overlay: FieldOverlay? = FieldOverlay(prepare: gate.prepare)
        weak var weakOverlay = overlay
        var tracks: [Int] = []
        overlay?.onChange = { _,count,_ in tracks.append(count) }
        overlay?.update(document: document(),folders: [],night: false)
        try await wait { gate.entered }
        overlay?.cancel(); overlay = nil
        XCTAssertNil(weakOverlay)
        gate.release(); try await wait { gate.finished }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(tracks.allSatisfy { $0 == 0 })
    }
}

private final class MapPreparationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    @discardableResult func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
private final class MapPreparationGate: @unchecked Sendable {
    private let counter = MapPreparationCounter(),lock = NSLock(),semaphore = DispatchSemaphore(value: 0)
    private var started = false,done = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return started }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return done }
    func release() { semaphore.signal() }
    func prepare(_ document: Backup.Document,_ folders: [FolderInfo]) throws -> FieldMapGeometry.OverlaySnapshot {
        XCTAssertFalse(Thread.isMainThread)
        let first = counter.next() == 1
        let result = try FieldMapGeometry.prepareOverlay(document: document,folders: folders)
        if first {
            lock.lock(); started = true; lock.unlock()
            guard semaphore.wait(timeout: .now()+15) == .success else { throw CancellationError() }
            lock.lock(); done = true; lock.unlock()
        }
        return result
    }
}

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
    func testWorkerStartupPreservesImportedTilesPreferencesAndNoNetworkPolicy() async throws {
        let dir = try directory(),library = try MapTileLibrary(directory: dir)
        let source = dir.appendingPathComponent("Saved CAFÉ.mbtiles")
        let archive = try MapTileArchive(url: source,create: true)
        try archive.setMetadata(["name":"Saved CAFÉ","format":"png","bounds":"-180,-85,180,85"])
        try archive.put(png,tile: .init(z: 0,x: 0,y: 0))
        let saved = try library.importFile(source)
        var preferences = MapLayerStore.Preferences()
        preferences.baseLayer = "mbtiles:"+saved.id; preferences.offlineOnly = true
        preferences.gridEnabled = false; preferences.hasCamera = true
        preferences.latitude = 35.1; preferences.longitude = -79; preferences.zoom = 12
        let prefsURL = dir.appendingPathComponent("map-prefs-v1.json")
        let bytes = try JSONEncoder().encode(preferences); try bytes.write(to: prefsURL)
        let libraryURL = dir.appendingPathComponent("OfflineMaps/library.json"),libraryBytes = try Data(contentsOf: libraryURL)
        let catalog = [layer],configuration = config()
        let prepared = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return MapLayerStore.prepareStartup(directory: dir,catalog: catalog,configuration: configuration)
        }.value
        let model = try MapLayerStore(startup: prepared,installPipeline: false)
        XCTAssertEqual(model.preferences,preferences); XCTAssertEqual(model.selectedMap,saved)
        XCTAssertTrue(model.pipeline.offlineOnly); XCTAssertNil(model.loadError)
        let tile = URL(string: "https://tiles.gridfix.invalid/local/\(saved.id)/0/0/0")!
        let (data,_) = try await model.pipeline.data(for: tile)
        XCTAssertEqual(data,png); XCTAssertEqual(TileNetworkFixture.calls,0)
        do { _ = try await model.pipeline.fetch(layer,tile: .init(z: 3,x: 7,y: 0)); XCTFail("Offline startup must prohibit network") } catch {}
        XCTAssertEqual(TileNetworkFixture.calls,0)
        XCTAssertEqual(try Data(contentsOf: prefsURL),bytes)
        XCTAssertEqual(try Data(contentsOf: libraryURL),libraryBytes)
    }
    func testPreparedMapStartupRejectsNewReplacedAndRemovedSourceFiles() async throws {
        let dir = try directory(),catalog = [layer]
        let missing = await Task.detached { MapLayerStore.prepareStartup(directory: dir,catalog: catalog) }.value
        let file = dir.appendingPathComponent("map-prefs-v1.json")
        try JSONEncoder().encode(MapLayerStore.Preferences()).write(to: file,options: .atomic)
        XCTAssertThrowsError(try MapLayerStore(startup: missing,installPipeline: false))
        let beforeReplacement = await Task.detached { MapLayerStore.prepareStartup(directory: dir,catalog: catalog) }.value
        var changed = MapLayerStore.Preferences(); changed.offlineOnly = true
        try JSONEncoder().encode(changed).write(to: file,options: .atomic)
        XCTAssertThrowsError(try MapLayerStore(startup: beforeReplacement,installPipeline: false))
        let beforeRemoval = await Task.detached { MapLayerStore.prepareStartup(directory: dir,catalog: catalog) }.value
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try MapLayerStore(startup: beforeRemoval,installPipeline: false))
        let beforeCatalog = await Task.detached { MapLayerStore.prepareStartup(directory: dir,catalog: catalog) }.value
        try Data("[]".utf8).write(to: dir.appendingPathComponent("OfflineMaps/library.json"))
        XCTAssertThrowsError(try MapLayerStore(startup: beforeCatalog,installPipeline: false))
    }
    func testDamagedCatalogIsKeptAndCannotBecomeWritableEmptyLibrary() async throws {
        let dir = try directory(),folder = dir.appendingPathComponent("OfflineMaps")
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("library.json"),bytes = Data("damaged CAFÉ catalog".utf8)
        try bytes.write(to: file)
        let catalog = [layer]
        let prepared = await Task.detached { MapLayerStore.prepareStartup(directory: dir,catalog: catalog) }.value
        let model = try MapLayerStore(startup: prepared,installPipeline: false)
        XCTAssertNotNil(model.loadError); XCTAssertTrue(model.savedMaps.isEmpty)
        await model.importMap(dir.appendingPathComponent("absent.mbtiles"))
        XCTAssertNotNil(model.message); XCTAssertEqual(try Data(contentsOf: file),bytes)
        let plan = try TileDownloadPlan(bounds: .init(south: 38.89,north: 38.90,west: -77.04,east: -77.03),currentZoom: 3,layer: layer)
        model.startDownload(plan: plan,name: "Cannot replace damaged catalog")
        XCTAssertNil(model.activeDownload); XCTAssertEqual(try Data(contentsOf: file),bytes)
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
    func testUpdateRefetchesPinnedTilesAndFailedPausedRefreshResumesAfterRelaunch() async throws {
        let dir = try directory(), model = MapLayerStore(directory: dir, installPipeline: false, catalog: [layer], configuration: config())
        let plan = try TileDownloadPlan(bounds: .init(south: 38.89, north: 38.90, west: -77.04, east: -77.03), currentZoom: 3, layer: layer)
        model.startDownload(plan: plan, name: "Original area")
        try await wait { model.activeDownload == nil && model.savedMaps.first?.complete == true }
        let id = model.savedMaps[0].id, old = png
        TileNetworkFixture.fail = true
        model.refreshArea(model.savedMaps[0])
        try await wait { model.activeDownload == nil && model.savedMaps[0].refreshPending == true }
        XCTAssertFalse(model.savedMaps[0].complete)
        let library = try MapTileLibrary(directory: dir)
        for tile in plan.tiles { XCTAssertEqual(try library.data(for: tile, mapID: id), old) }
        let reopened = MapLayerStore(directory: dir, installPipeline: false, catalog: [layer], configuration: config())
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let blue = UIGraphicsImageRenderer(size: .init(width: 256, height: 256), format: format).pngData { context in UIColor.blue.setFill(); context.fill(.init(x: 0, y: 0, width: 256, height: 256)) }
        TileNetworkFixture.lock.lock(); TileNetworkFixture.png = blue; TileNetworkFixture.lock.unlock()
        holdResponses(true); defer { holdResponses(false); reopened.pauseDownload() }
        reopened.resume(reopened.savedMaps[0])
        try await wait { TileNetworkFixture.calls > 0 && reopened.activeDownload != nil }
        reopened.pauseDownload(); try await wait { reopened.activeDownload == nil }
        XCTAssertEqual(reopened.savedMaps[0].refreshPending, true)
        let renamed = await reopened.rename(reopened.savedMaps[0], name: "Renamed CAFÉ")
        XCTAssertTrue(renamed); XCTAssertEqual(reopened.savedMaps[0].refreshPending, true)
        TileNetworkFixture.calls = 0; holdResponses(false)
        reopened.resume(reopened.savedMaps[0])
        try await wait { reopened.activeDownload == nil && reopened.savedMaps[0].complete }
        XCTAssertEqual(TileNetworkFixture.calls, plan.tiles.count, "Update must contact the provider even with every old tile pinned")
        XCTAssertEqual(reopened.savedMaps.count, 1); XCTAssertEqual(reopened.savedMaps[0].id, id)
        XCTAssertNil(reopened.savedMaps[0].refreshPending)
        XCTAssertEqual(reopened.savedMaps[0].name, "Renamed CAFÉ")
        let final = try MapTileLibrary(directory: dir)
        for tile in plan.tiles { XCTAssertEqual(try final.data(for: tile, mapID: id), blue) }
        try await wait { reopened.areaDetails[id]?.tiles == plan.tiles.count }
        XCTAssertGreaterThan(reopened.areaDetails[id]?.bytes ?? 0, 0)
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
