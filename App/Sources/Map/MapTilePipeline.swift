import CoreImage
import GridFixCore
import ImageIO
import MapLibre
import UIKit

/// MapLibre requests synthetic HTTPS URLs through a dedicated URLProtocol.
/// Original provider responses live in URLCache (respecting HTTP headers), while
/// deliberate downloads and MBTiles are read from app-owned SQLite archives.
final class MapTilePipeline: @unchecked Sendable {
    let library: MapTileLibrary?
    let layers: [RasterLayer]
    let session: URLSession
    private let terrainSession: URLSession
    let terrainCache: TerrainTileCache
    private let cache: URLCache
    private let lock = NSLock()
    private var onlyOffline = false
    private static let imageContext = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    init(directory: URL, library: MapTileLibrary?, layers: [RasterLayer], configuration: URLSessionConfiguration? = nil) {
        self.library = library; self.layers = layers
        cache = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: Int(MapTileLibrary.cacheLimit), directory: directory.appendingPathComponent("BrowseMapCache"))
        let config = configuration ?? URLSessionConfiguration.default
        config.urlCache = cache; config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 25; config.httpMaximumConnectionsPerHost = 4
        config.httpAdditionalHeaders = ["User-Agent": "GridFix-iOS/0.1 (MGRS GPS map client)"]
        session = URLSession(configuration: config)
        let terrainConfig = (configuration?.copy() as? URLSessionConfiguration) ?? URLSessionConfiguration.ephemeral
        terrainConfig.urlCache = nil; terrainConfig.timeoutIntervalForRequest = 8
        terrainConfig.timeoutIntervalForResource = 16
        terrainConfig.httpAdditionalHeaders = config.httpAdditionalHeaders
        terrainSession = URLSession(configuration: terrainConfig)
        terrainCache = TerrainTileCache(directory: directory, pinnedBytes: { library?.elevationBytes ?? 0 })
        adjustCacheBudget()
    }
    var offlineOnly: Bool {
        get { lock.lock(); defer { lock.unlock() }; return onlyOffline }
        set {
            lock.lock(); onlyOffline = newValue; lock.unlock()
            if newValue { session.getAllTasks { $0.forEach { $0.cancel() } }; terrainSession.getAllTasks { $0.forEach { $0.cancel() } } }
        }
    }
    func adjustCacheBudget() { cache.diskCapacity = max(0, Int(MapTileLibrary.cacheLimit - (library?.downloadedBytes ?? 0))) }
    func clearBrowseCache() { cache.removeAllCachedResponses() }
    func install() {
        MapTileURLProtocol.pipeline = self
        let config = URLSessionConfiguration.default
        config.protocolClasses = [MapTileURLProtocol.self]
        config.urlCache = nil // synthetic URLs must not bypass Offline only or pinning
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = config
    }
    func fetch(_ layer: RasterLayer, tile: MapTile, allowNetwork: Bool = true, allowParentFallback: Bool = true) async throws -> Data {
        guard tile.valid else { throw URLError(.badURL) }
        if let data = library?.pinnedTile(tile, layerKey: layer.key) { return data }
        if layer.key == "dem", let cached = terrainCache.read(tile) { return cached }
        guard let url = layer.url(for: tile) else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        if offlineOnly || !allowNetwork {
            if layer.key == "dem" { throw URLError(.notConnectedToInternet) }
            if let cached = cache.cachedResponse(for: request), MapTileArchive.rasterFormat(cached.data) != nil { return cached.data }
            if allowParentFallback, let parent = parentTile(tile, layer: layer) { return parent }
            throw URLError(.notConnectedToInternet)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await (layer.key == "dem" ? terrainSession : session).data(for: request) }
        catch { if allowParentFallback, layer.key != "dem", let parent = parentTile(tile, layer: layer) { return parent }; throw error }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 4 * 1024 * 1024, MapTileArchive.rasterFormat(data) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 1024, height <= 1024 else { throw URLError(.cannotDecodeContentData) }
        if layer.key == "dem" { try? terrainCache.store(data, tile: tile) }
        return data
    }
    /// A 256 px source is addressed one level above MapLibre's 512 px camera
    /// zoom. Crop saved ancestors when offline/overzoomed instead of leaving
    /// a fully downloaded Android-style area blank at the next display level.
    private func parentTile(_ tile: MapTile, layer: RasterLayer) -> Data? {
        guard tile.z > 0, layer.key != "dem" else { return nil }
        for delta in 1...min(tile.z, 6) {
            let factor = 1 << delta
            let parent = MapTile(z: tile.z - delta, x: tile.x / factor, y: tile.y / factor)
            guard let data = library?.pinnedTile(parent, layerKey: layer.key), let image = UIImage(data: data)?.cgImage else { continue }
            let size = Double(image.width) / Double(factor)
            let rect = CGRect(x: Double(tile.x % factor) * size, y: Double(tile.y % factor) * size, width: size, height: size)
            if size >= 1, let cropped = image.cropping(to: rect) { return UIImage(cgImage: cropped).pngData() }
        }
        return nil
    }
    func data(for url: URL) async throws -> (Data, String) {
        let path = url.pathComponents.filter { $0 != "/" }
        if path.first == "fonts", path.count == 3 {
            if path[2] == "0-255.pbf", let file = Bundle.main.url(forResource: "0-255", withExtension: "pbf") {
                return (try Data(contentsOf: file), "application/x-protobuf")
            }
            guard let remote = URL(string: "https://demotiles.maplibre.org/font/" + path[1...].joined(separator: "/").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else { throw URLError(.badURL) }
            let request = URLRequest(url: remote)
            if offlineOnly {
                guard let cached = cache.cachedResponse(for: request) else { throw URLError(.notConnectedToInternet) }
                return (cached.data, "application/x-protobuf")
            }
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2 * 1024 * 1024 else { throw URLError(.badServerResponse) }
            return (data, "application/x-protobuf")
        }
        guard path.count == 5, let z = Int(path[2]), let x = Int(path[3]), let y = Int(path[4]), MapTile(z: z, x: x, y: y).valid else { throw URLError(.badURL) }
        let tile = MapTile(z: z, x: x, y: y)
        let data: Data
        if path[0] == "local" {
            guard let local = try library?.data(for: tile, mapID: path[1]) else { throw URLError(.fileDoesNotExist) }
            data = local
        } else if path[0] == "online", let layer = (layers + [MapCatalog.elevation]).first(where: { $0.key == path[1] }) {
            data = try await fetch(layer, tile: tile)
        } else { throw URLError(.badURL) }
        let effect = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "effect" })?.value ?? "day"
        guard effect != "day" else { return (data, "image/" + (MapTileArchive.rasterFormat(data) ?? "png")) }
        return (try Self.filtered(data, effect: effect), "image/png")
    }
    static func filtered(_ data: Data, effect: String) throws -> Data {
        guard let input = CIImage(data: data), input.extent.width <= 1024, input.extent.height <= 1024 else { throw URLError(.cannotDecodeContentData) }
        let shadow = effect == "shadow"
        let image = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": shadow ? CIVector(x: 0,y: 0,z: 0,w: 0) : CIVector(x: 0.42,y: 0.34,z: 0.14,w: 0),
            "inputGVector": CIVector(x: 0,y: 0,z: 0,w: 0), "inputBVector": CIVector(x: 0,y: 0,z: 0,w: 0),
            "inputAVector": shadow ? CIVector(x: -0.235,y: -0.235,z: -0.235,w: 0) : CIVector(x: 0,y: 0,z: 0,w: 1),
            "inputBiasVector": CIVector(x: 0,y: 0,z: 0,w: shadow ? 180.0 / 255 : 0)
        ])
        guard let cg = imageContext.createCGImage(image, from: input.extent), let data = UIImage(cgImage: cg).pngData() else { throw URLError(.cannotDecodeContentData) }
        return data
    }
}

final class MapTileURLProtocol: URLProtocol, @unchecked Sendable {
    // Installed before any MapLibre session exists; each app process owns one pipeline.
    static var pipeline: MapTilePipeline?
    private var loadingTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "tiles.gridfix.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let pipeline = Self.pipeline else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        loadingTask = Task {
            do {
                let (data, mime) = try await pipeline.data(for: url)
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Cache-Control": "no-store"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
            } catch { if !Task.isCancelled { client?.urlProtocol(self, didFailWithError: error) } }
        }
    }
    override func stopLoading() { loadingTask?.cancel() }
}
