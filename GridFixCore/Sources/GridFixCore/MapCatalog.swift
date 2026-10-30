import Foundation

public struct RasterLayer: Equatable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let attribution: String
    public let template: String
    public let tileSize: Int
    public let maxZoom: Int
    public let maxDownloadZoom: Int
    public let bulkDownload: Bool
    public let bytesPerTile: Int
    public init(key: String, label: String, attribution: String, template: String, tileSize: Int = 256,
                maxZoom: Int = 16, maxDownloadZoom: Int = 15, bulkDownload: Bool = false, bytesPerTile: Int = 20 * 1024) {
        self.key = key; self.label = label; self.attribution = attribution; self.template = template
        self.tileSize = tileSize; self.maxZoom = maxZoom; self.maxDownloadZoom = maxDownloadZoom
        self.bulkDownload = bulkDownload; self.bytesPerTile = bytesPerTile
    }
    public func url(for tile: MapTile) -> URL? {
        URL(string: template.replacingOccurrences(of: "{z}", with: "\(tile.z)").replacingOccurrences(of: "{x}", with: "\(tile.x)").replacingOccurrences(of: "{y}", with: "\(tile.y)"))
    }
}

public enum MapCatalog {
    public static func layers(esriKey: String = "", development: Bool = false) -> [RasterLayer] {
        let key = esriKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasKey = !key.isEmpty && !key.hasPrefix("$(")
        let token = hasKey ? "?token=\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" : ""
        let attr = "Powered by Esri · © Esri, TomTom, Garmin, OpenStreetMap contributors"
        let staticBase = "https://static-map-tiles-api.arcgis.com/arcgis/rest/services/static-basemap-tiles-service/v1/arcgis/"
        let imageBase = hasKey ? "https://ibasemaps-api.arcgis.com/arcgis/rest/services/" : "https://server.arcgisonline.com/ArcGIS/rest/services/"
        let usgs = [
            RasterLayer(key: "usgs", label: "USGS Topo (US only)", attribution: "USGS The National Map", template: "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}", tileSize: 256, maxZoom: 16, maxDownloadZoom: 15, bulkDownload: true, bytesPerTile: 32 * 1024),
            RasterLayer(key: "usgs_img", label: "USGS Imagery (US only)", attribution: "USGS The National Map", template: "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}", tileSize: 256, maxZoom: 16, maxDownloadZoom: 16, bulkDownload: true, bytesPerTile: 24 * 1024)
        ]
        guard hasKey || development else { return usgs }
        return [
            RasterLayer(key: "streets", label: "Streets", attribution: hasKey ? attr : "© OpenStreetMap contributors", template: hasKey ? staticBase + "streets/static/tile/{z}/{y}/{x}" + token : "https://tile.openstreetmap.org/{z}/{x}/{y}.png", tileSize: hasKey ? 512 : 256, maxZoom: hasKey ? 22 : 19, maxDownloadZoom: 16, bulkDownload: false, bytesPerTile: 20 * 1024),
            RasterLayer(key: "topo", label: "Topographic", attribution: hasKey ? attr : "© OpenStreetMap contributors, SRTM · OpenTopoMap (CC-BY-SA)", template: hasKey ? staticBase + "outdoor/static/tile/{z}/{y}/{x}" + token : "https://tile.opentopomap.org/{z}/{x}/{y}.png", tileSize: hasKey ? 512 : 256, maxZoom: hasKey ? 22 : 17, maxDownloadZoom: 15, bulkDownload: false, bytesPerTile: 20 * 1024),
            RasterLayer(key: "sat", label: "Satellite", attribution: "Powered by Esri · Esri, Maxar, Earthstar Geographics", template: imageBase + "World_Imagery/MapServer/tile/{z}/{y}/{x}" + token, tileSize: 256, maxZoom: 19, maxDownloadZoom: 17, bulkDownload: false, bytesPerTile: 20 * 1024)
        ] + usgs + [RasterLayer(key: "hillshade", label: "Hillshade", attribution: "Powered by Esri · Esri, USGS, NASA", template: imageBase + "Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}" + token, tileSize: 256, maxZoom: 16, maxDownloadZoom: 14, bulkDownload: false, bytesPerTile: 20 * 1024)]
    }
    public static let elevation = RasterLayer(key: "dem", label: "Elevation", attribution: "Mapzen · AWS Terrain Tiles", template: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png", tileSize: 256, maxZoom: 13, maxDownloadZoom: 13, bulkDownload: true, bytesPerTile: 150 * 1024)
}

public struct MapBounds: Codable, Equatable, Sendable {
    public var south: Double, north: Double, west: Double, east: Double
    public init(south: Double, north: Double, west: Double, east: Double) {
        self.south = south; self.north = north; self.west = west; self.east = east
    }
    public var valid: Bool { [south,north,west,east].allSatisfy(\.isFinite) && south < north && south >= -90 && north <= 90 && abs(west) <= 540 && abs(east) <= 540 }
}

public struct MapTile: Hashable, Codable, Sendable {
    public let z: Int, x: Int, y: Int
    public init(z: Int, x: Int, y: Int) { self.z = z; self.x = x; self.y = y }
    public var valid: Bool { (0...22).contains(z) && x >= 0 && y >= 0 && x < 1 << z && y < 1 << z }
    public var tmsRow: Int { (1 << z) - 1 - y }
    public static func longitude(_ x: Double, zoom: Int) -> Double { x / pow(2, Double(zoom)) * 360 - 180 }
    public static func latitude(_ y: Double, zoom: Int) -> Double { atan(sinh(.pi * (1 - 2 * y / pow(2, Double(zoom))))) * 180 / .pi }
}

public struct TileDownloadPlan: Equatable, Sendable {
    public let bounds: MapBounds
    public let layerKey: String
    public let minZoom: Int, maxZoom: Int
    public let tiles: [MapTile]
    public let estimatedBytes: Int64
    public init(bounds: MapBounds, currentZoom: Double, layer: RasterLayer, elevation: Bool = false) throws {
        guard bounds.valid, currentZoom.isFinite, layer.bulkDownload, (3...22).contains(layer.maxDownloadZoom) else { throw BackupError.notABackup("This layer does not support area downloads") }
        self.bounds = bounds; layerKey = layer.key
        minZoom = elevation ? 13 : min(layer.maxDownloadZoom, max(3, Int(min(22,max(0,currentZoom)).rounded(.down))))
        maxZoom = elevation ? 13 : min(layer.maxDownloadZoom, minZoom + 4)
        tiles = try Self.coverage(bounds, minZoom: minZoom, maxZoom: maxZoom, limit: elevation ? 400 : 12_000)
        estimatedBytes = Int64(tiles.count) * Int64(layer.bytesPerTile)
    }
    public static func coverage(_ bounds: MapBounds, minZoom: Int, maxZoom: Int, limit: Int) throws -> [MapTile] {
        guard bounds.valid, (0...22).contains(minZoom), (minZoom...22).contains(maxZoom), limit > 0 else { throw BackupError.notABackup("Invalid map area") }
        func normalized(_ lon: Double) -> Double { let v = (lon + 180).truncatingRemainder(dividingBy: 360); return (v < 0 ? v + 360 : v) - 180 }
        var result: [MapTile] = []
        for z in minZoom...maxZoom {
            let n = 1 << z
            func x(_ lon: Double) -> Int { min(n - 1, max(0, Int(floor((lon + 180) / 360 * Double(n))))) }
            func y(_ lat: Double) -> Int {
                let p = min(85.05112878, max(-85.05112878, lat)) * .pi / 180
                return min(n - 1, max(0, Int(floor((1 - asinh(tan(p)) / .pi) / 2 * Double(n)))))
            }
            let span = bounds.east - bounds.west
            let columns: [ClosedRange<Int>]
            if abs(span) >= 360 { columns = [0...(n - 1)] }
            else {
                let w = normalized(bounds.west), e = normalized(bounds.east)
                columns = w <= e ? [x(w)...x(e)] : [x(w)...(n - 1), 0...x(e)]
            }
            let rows = y(bounds.north)...y(bounds.south)
            // Check before allocating or enumerating a potentially world-sized box.
            let overlap = columns.count == 2 ? max(0, min(columns[0].upperBound, columns[1].upperBound) - max(columns[0].lowerBound, columns[1].lowerBound) + 1) : 0
            let count = (columns.reduce(0) { $0 + $1.count } - overlap) * rows.count
            guard count <= limit - result.count else { throw BackupError.notABackup("Area exceeds \(limit) tiles. Zoom in and try again; nothing downloaded.") }
            var seen = Set<MapTile>()
            for col in columns { for xx in col { for yy in rows {
                let tile = MapTile(z: z, x: xx, y: yy)
                if seen.insert(tile).inserted { result.append(tile) }
            } } }
        }
        return result
    }
}
