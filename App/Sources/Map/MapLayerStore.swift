import GridFixCore
import SwiftUI

@MainActor
final class MapLayerStore: ObservableObject {
    struct Preferences: Codable, Equatable {
        var baseLayer = "topo", gridEnabled = true, hillshade = false, contours = false, offlineOnly = false
        var latitude = 24.4539, longitude = 54.3773, zoom = 6.5
        var hasCamera = false
    }
    @Published private(set) var preferences = Preferences()
    @Published private(set) var savedMaps: [SavedMap] = []
    @Published private(set) var message: String?
    @Published private(set) var loadError: String?
    @Published private(set) var activeDownload: String?
    @Published private(set) var downloadProgress = 0
    @Published private(set) var revision = 0
    struct AreaDetails: Sendable { let tiles: Int; let bytes: Int64 }
    @Published private(set) var areaDetails: [String: AreaDetails] = [:]
    private var detailGeneration = UUID()
    @Published var focusRequest: MapCameraRequest?
    @Published var laneRequest: LaneMapRequest?
    @Published var viewedTrackID: String?
    @Published private(set) var isImporting = false
    lazy var terrainSampler = TerrainSampler(pipeline: pipeline)
    let pipeline: MapTilePipeline
    let layers: [RasterLayer]
    private let library: MapTileLibrary?
    let styleURL: URL
    private let preferencesURL: URL
    private var downloadTask: Task<Void, Never>?
    private var cameraTask: Task<Void, Never>?

    init(directory: URL? = nil, installPipeline: Bool = true, catalog: [RasterLayer]? = nil, configuration: URLSessionConfiguration? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        preferencesURL = directory.appendingPathComponent("map-prefs-v1.json")
        styleURL = directory.appendingPathComponent("map-style-v1.json")
        let style: [String: Any] = ["version": 8, "name": "GridFix", "glyphs": "https://tiles.gridfix.invalid/fonts/{fontstack}/{range}.pbf", "sources": [:], "layers": [["id": "background", "type": "background", "paint": ["background-color": "#252a30"]]]]
        try? JSONSerialization.data(withJSONObject: style).write(to: styleURL, options: .atomic)
        #if DEBUG
        let development = true
        #else
        let development = false
        #endif
        layers = catalog ?? MapCatalog.layers(esriKey: Bundle.main.object(forInfoDictionaryKey: "GridFixEsriKey") as? String ?? "", development: development)
        do { library = try MapTileLibrary(directory: directory) }
        catch { library = nil; loadError = "Offline map files were kept: \(error.localizedDescription)" }
        pipeline = MapTilePipeline(directory: directory, library: library, layers: layers, configuration: configuration)
        if let data = try? Data(contentsOf: preferencesURL), let stored = try? JSONDecoder().decode(Preferences.self, from: data), stored.latitude.isFinite, stored.longitude.isFinite, stored.zoom.isFinite, (-85.05112878...85.05112878).contains(stored.latitude), (-180...180).contains(stored.longitude), (0...22).contains(stored.zoom) { preferences = stored }
        savedMaps = library?.maps ?? []
        if !layers.contains(where: { $0.key == preferences.baseLayer }) && !savedMaps.contains(where: { "mbtiles:" + $0.id == preferences.baseLayer }) { preferences.baseLayer = layers.first!.key }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") && (ProcessInfo.processInfo.arguments.contains("-uiTestOfflineMap") || ProcessInfo.processInfo.arguments.contains("-uiTestBoundaryMap") || ProcessInfo.processInfo.arguments.contains("-uiTestTerrain") || ProcessInfo.processInfo.arguments.contains("-uiTestTerrainNoData")), savedMaps.isEmpty, let library {
            // Synthetic data exercises the real MBTiles importer and renderer;
            // it never runs in Release or against normal field data.
            do {
                let file = directory.appendingPathComponent("Offline training map.mbtiles")
                let db = try MapTileArchive(url: file, create: true)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format)
                let png = renderer.pngData { context in
                    UIColor(red: 0.12, green: 0.42, blue: 0.30, alpha: 1).setFill(); context.fill(CGRect(x: 0,y: 0,width: 256,height: 256))
                    UIColor(red: 0.25, green: 0.65, blue: 0.45, alpha: 1).setFill()
                    for i in 0..<8 { context.fill(CGRect(x: i * 32,y: i * 32,width: 16,height: 16)) }
                }
                try db.setMetadata(["name":"Offline training map", "format":"png", "bounds":"-180,-85,180,85", "attribution":"Synthetic offline test map"])
                try db.put(png, tile: .init(z: 0,x: 0,y: 0))
                let map = try library.importFile(file)
                savedMaps = library.maps; preferences.baseLayer = "mbtiles:" + map.id
                preferences.offlineOnly = true; preferences.hasCamera = true; preferences.zoom = (ProcessInfo.processInfo.arguments.contains("-uiTestBoundaryMap") || ProcessInfo.processInfo.arguments.contains("-uiTestTerrain") || ProcessInfo.processInfo.arguments.contains("-uiTestTerrainNoData")) ? 16 : 1
                try JSONEncoder().encode(preferences).write(to: preferencesURL, options: .atomic)
                try? FileManager.default.removeItem(at: file)
            } catch { loadError = error.localizedDescription }
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") && ProcessInfo.processInfo.arguments.contains("-uiTestTerrain") {
            do { try TerrainTestFixture.seed(pipeline) } catch { loadError = error.localizedDescription }
        }
        #endif
        pipeline.offlineOnly = preferences.offlineOnly
        if installPipeline { pipeline.install() }
        refreshDetails()
    }
    var selectedMap: SavedMap? { savedMaps.first { "mbtiles:" + $0.id == preferences.baseLayer } }
    var selectedLayer: RasterLayer { layers.first { $0.key == preferences.baseLayer } ?? layers[0] }
    var layerName: String { selectedMap?.name ?? selectedLayer.label }
    func setLayer(_ key: String) { update { $0.baseLayer = key } }
    func setGrid(_ enabled: Bool) { update { $0.gridEnabled = enabled } }
    func setHillshade(_ enabled: Bool) { update { $0.hillshade = enabled } }
    func setContours(_ enabled: Bool) { update { $0.contours = enabled } }
    func setOfflineOnly(_ enabled: Bool) {
        if enabled { pauseDownload() }
        pipeline.offlineOnly = enabled; update { $0.offlineOnly = enabled }
    }
    func saveCamera(lat: Double, lon: Double, zoom: Double) {
        guard lat.isFinite, lon.isFinite, zoom.isFinite else { return }
        cameraTask?.cancel()
        cameraTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.update { $0.latitude = lat; $0.longitude = ((lon + 540).truncatingRemainder(dividingBy: 360)) - 180; $0.zoom = min(22,max(0,zoom)); $0.hasCamera = true }
        }
    }
    func importMap(_ url: URL) async {
        guard let library, !isImporting else { message = loadError; return }
        isImporting = true
        defer { isImporting = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let map = try await Task.detached(priority: .utility) { try library.importFile(url) }.value
            savedMaps = library.maps; revision += 1; refreshDetails(); setLayer("mbtiles:" + map.id); message = "Imported \(map.name)"
        } catch { message = "Import failed: \(error.localizedDescription)" }
    }
    func startDownload(plan: TileDownloadPlan, name: String) {
        guard activeDownload == nil, !preferences.offlineOnly, let library,
              let layer = (layers + [MapCatalog.elevation]).first(where: { $0.key == plan.layerKey }) else { return }
        activeDownload = "preparing"; message = nil
        downloadTask = Task {
            do {
                let map = try await Task.detached { try library.begin(plan, name: name, layer: layer) }.value
                savedMaps = library.maps
                await runDownload(map, tiles: plan.tiles, layer: layer)
            } catch { message = error.localizedDescription; activeDownload = nil }
        }
    }
    func resume(_ map: SavedMap) {
        guard activeDownload == nil, !preferences.offlineOnly, let library,
              let map = library.maps.first(where: { $0.id == map.id }), !map.imported,
              let layer = (layers + [MapCatalog.elevation]).first(where: { $0.key == map.layerKey }) else { return }
        activeDownload = "preparing"; message = nil
        downloadTask = Task {
            do {
                let tiles = try TileDownloadPlan.coverage(map.bounds, minZoom: map.minZoom, maxZoom: map.maxZoom, limit: map.layerKey == "dem" ? 400 : 12_000)
                await runDownload(map, tiles: tiles, layer: layer)
            } catch { message = error.localizedDescription; activeDownload = nil }
        }
    }
    func refreshArea(_ map: SavedMap) {
        guard activeDownload == nil, !preferences.offlineOnly, !map.imported, let library,
              let layer = (layers + [MapCatalog.elevation]).first(where: { $0.key == map.layerKey }), layer.bulkDownload else { return }
        activeDownload = "preparing"; message = nil
        downloadTask = Task {
            do {
                let updated = try await Task.detached { try library.beginRefresh(map.id) }.value
                savedMaps = library.maps
                let tiles = try TileDownloadPlan.coverage(updated.bounds, minZoom: updated.minZoom, maxZoom: updated.maxZoom, limit: updated.layerKey == "dem" ? 400 : 12_000)
                await runDownload(updated, tiles: tiles, layer: layer)
            } catch { message = error.localizedDescription; activeDownload = nil }
        }
    }
    func rename(_ map: SavedMap, name: String) async -> Bool {
        guard let library else { message = loadError ?? "Offline map storage is unavailable"; return false }
        do {
            try await Task.detached { try library.rename(map.id, name: name) }.value
            savedMaps = library.maps; revision += 1; refreshDetails(); message = "Area renamed"
            return true
        } catch { message = "Rename failed: " + error.localizedDescription; return false }
    }
    private func refreshDetails() {
        guard let library else { return }
        let token = UUID(); detailGeneration = token
        Task {
            let details = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: library.maps.map { ($0.id, AreaDetails(tiles: library.downloadedCount($0.id), bytes: library.bytes($0.id))) })
            }.value
            guard detailGeneration == token else { return }
            areaDetails = details
        }
    }
    private func runDownload(_ map: SavedMap, tiles: [MapTile], layer: RasterLayer) async {
        guard let library else { return }
        activeDownload = map.id; downloadProgress = 0
        var failed = 0
        for tile in tiles {
            if Task.isCancelled { break }
            do {
                let exists = try await Task.detached { try library.data(for: tile, mapID: map.id) != nil }.value
                if !exists || map.refreshPending == true {
                    let data = try await pipeline.fetch(layer, tile: tile, allowParentFallback: false, refresh: map.refreshPending == true)
                    try Task.checkCancellation()
                    try await Task.detached { try library.store(data, tile: tile, in: map.id) }.value
                    if layer.key == "dem" { pipeline.terrainCache.remove(tile) }
                }
                downloadProgress += 1
            } catch {
                if Task.isCancelled { break }
                failed += 1; message = "Tile download failed: \(error.localizedDescription). Saved tiles are kept; retry this area."
                // Avoid hammering a failed provider for every tile in a large box.
                break
            }
        }
        if Task.isCancelled { message = "Download paused. Saved tiles are kept." }
        else if failed == 0 {
            do { try await Task.detached { try library.finish(map.id) }.value; message = "Offline area saved" }
            catch { message = error.localizedDescription }
        }
        savedMaps = library.maps; revision += 1; refreshDetails(); pipeline.adjustCacheBudget(); activeDownload = nil
    }
    func pauseDownload() { downloadTask?.cancel() }
    func delete(_ map: SavedMap) async {
        guard activeDownload != map.id, activeDownload != "preparing", let library else { return }
        do {
            try await Task.detached { try library.delete(map.id) }.value
            savedMaps = library.maps; revision += 1; refreshDetails()
            if selectedMap == nil && preferences.baseLayer == "mbtiles:" + map.id { setLayer(layers[0].key) }
            pipeline.adjustCacheBudget()
        } catch { message = error.localizedDescription }
    }
    func clearBrowseCache() { pipeline.clearBrowseCache(); revision += 1; message = "Browse cache cleared. Saved offline maps were kept." }
    private func update(_ mutate: (inout Preferences) -> Void) {
        var next = preferences; mutate(&next)
        do { try JSONEncoder().encode(next).write(to: preferencesURL, options: .atomic); preferences = next }
        catch { message = "Map preference could not be saved: \(error.localizedDescription)" }
    }
}
