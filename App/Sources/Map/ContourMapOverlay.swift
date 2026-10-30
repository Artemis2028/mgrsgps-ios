import GridFixCore
import ImageIO
import MapLibre

@MainActor
final class ContourMapOverlay {
    private var source: MLNShapeSource?
    private var cache: [String: [[String: Any]]] = [:]
    private var work: Task<Void, Never>?
    private var previous = ""
    var onInterval: ((String) -> Void)?
    func install(style: MLNStyle) {
        guard source == nil else { return }
        let source = MLNShapeSource(identifier: "terrain-contours", shape: nil, options: nil)
        self.source = source; style.addSource(source)
        for major in [false,true] {
            let layer = MLNLineStyleLayer(identifier: major ? "contour-major" : "contour-minor", source: source)
            layer.predicate = NSPredicate(format: "major == %@", NSNumber(value: major))
            layer.lineWidth = NSExpression(forConstantValue: major ? 1.9 : 1.1)
            layer.lineOpacity = NSExpression(forConstantValue: major ? 0.84 : 0.59)
            if let grid = style.layer(withIdentifier: "mgrs-fine") { style.insertLayer(layer, below: grid) } else { style.addLayer(layer) }
        }
        let labels = MLNSymbolStyleLayer(identifier: "contour-labels", source: source)
        labels.predicate = NSPredicate(format: "kind == %@", "label")
        labels.text = NSExpression(forKeyPath: "text"); labels.textFontNames = NSExpression(forConstantValue: ["Open Sans Semibold"])
        labels.textFontSize = NSExpression(forConstantValue: 10.5); labels.textHaloWidth = NSExpression(forConstantValue: 1.3)
        style.addLayer(labels)
    }
    func refresh(map: MLNMapView, store: MapLayerStore, night: Bool) {
        guard let style = map.style, let source else { return }
        let enabled = store.preferences.contours
        for id in ["contour-major", "contour-minor", "contour-labels"] { style.layer(withIdentifier: id)?.isVisible = enabled }
        for id in ["contour-major", "contour-minor"] { (style.layer(withIdentifier: id) as? MLNLineStyleLayer)?.lineColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor(red: 148/255, green: 94/255, blue: 42/255, alpha: 1)) }
        if let labels = style.layer(withIdentifier: "contour-labels") as? MLNSymbolStyleLayer {
            labels.textColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor.brown)
            labels.textHaloColor = NSExpression(forConstantValue: night ? UIColor.black : UIColor.white)
        }
        let bounds = map.visibleCoordinateBounds
        let box = MapBounds(south: bounds.sw.latitude, north: bounds.ne.latitude, west: bounds.sw.longitude, east: bounds.ne.longitude)
        guard enabled, let interval = TerrainContours.interval(metersPerPoint: map.metersPerPoint(atLatitude: map.centerCoordinate.latitude)),
              let tiles = try? TileDownloadPlan.coverage(box, minZoom: 13, maxZoom: 13, limit: 72) else {
            work?.cancel(); previous = ""; source.shape = nil; onInterval?(enabled ? "Zoom in for contours" : ""); return
        }
        let key = "\(tiles)|\(interval)|\(store.preferences.offlineOnly)|\(store.revision)"
        guard previous != key else { return }; previous = key
        work?.cancel(); onInterval?("CI \(interval) m")
        work = Task {
            var features: [[String: Any]] = []
            for tile in tiles {
                if Task.isCancelled { return }
                let key = "\(tile.x)/\(tile.y)/\(interval)"
                if let existing = cache[key] { features += existing; continue }
                do {
                    let bytes = try await store.pipeline.fetch(MapCatalog.elevation, tile: tile)
                    let built = try await Task.detached(priority: .utility) { try Self.features(bytes, tile: tile, interval: interval) }.value
                    if cache.count >= 110 { cache.removeAll() }
                    cache[key] = built; features += built
                } catch { /* Missing terrain stays unknown; never invent elevations. */ }
            }
            guard !Task.isCancelled else { return }
            if let data = try? JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features]) {
                source.shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
            }
            if features.isEmpty { onInterval?("Contours unavailable · download elevation") }
        }
    }
    nonisolated static func features(_ data: Data, tile: MapTile, interval: Int) throws -> [[String: Any]] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == 256, image.height == 256 else { throw URLError(.cannotDecodeContentData) }
        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256)); return true
        }
        guard drawn else { throw URLError(.cannotDecodeContentData) }
        let elevations = stride(from: 0, to: pixels.count, by: 4).map { i in TerrainContours.elevation(red: pixels[i], green: pixels[i+1], blue: pixels[i+2]) ?? .nan }
        let levels = TerrainContours.build(elevations: elevations, width: 256, interval: interval)
        func coordinate(_ p: TerrainContours.Point) -> [Double] {
            [MapTile.longitude(Double(tile.x) + p.x / 256, zoom: tile.z), MapTile.latitude(Double(tile.y) + p.y / 256, zoom: tile.z)]
        }
        var result: [[String: Any]] = []
        for level in levels {
            result.append(["type": "Feature", "geometry": ["type": "MultiLineString", "coordinates": level.segments.map { [coordinate($0.a),coordinate($0.b)] }], "properties": ["major": level.major]])
            if let label = level.label { result.append(["type": "Feature", "geometry": ["type": "Point", "coordinates": coordinate(label)], "properties": ["kind": "label", "text": "\(level.elevation)"]]) }
        }
        return result
    }
}
