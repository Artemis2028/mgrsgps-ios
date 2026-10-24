import GridFixCore
import MapLibre

@MainActor
final class RasterMapLayers {
    private var previous = ""
    func update(style: MLNStyle, store: MapLayerStore, night: Bool) {
        let local = store.selectedMap
        let key = "\(store.preferences.baseLayer)|\(night)|\(store.preferences.hillshade)|\(store.preferences.offlineOnly)|\(store.revision)"
        guard key != previous else { return }
        previous = key
        for id in ["map-shadows", "map-base"] {
            if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
            if let source = style.source(withIdentifier: id) { style.removeSource(source) }
        }
        let selected = store.selectedLayer
        add(style: style, id: "map-base", path: local.map { "local/\($0.id)" } ?? "online/\(selected.key)",
            tileSize: local?.tileSize ?? selected.tileSize, maxZoom: local?.maxZoom ?? selected.maxZoom,
            attribution: local?.attribution ?? selected.attribution, effect: night ? "night" : "day", revision: store.revision)
        if store.preferences.hillshade, local == nil, store.layers.contains(where: { $0.key == "hillshade" }) {
            add(style: style, id: "map-shadows", path: "online/hillshade", tileSize: 256, maxZoom: 16,
                attribution: "Esri, USGS, NASA", effect: "shadow", revision: store.revision)
        }
    }
    private func attributionURL(path: String) -> URL? {
        guard path.hasPrefix("online/") else { return nil }
        switch path {
        case "online/usgs", "online/usgs_img": return URL(string: "https://www.usgs.gov/programs/national-geospatial-program/national-map")
        case "online/streets", "online/topo":
            #if DEBUG
            let key = Bundle.main.object(forInfoDictionaryKey: "GridFixEsriKey") as? String ?? ""
            if key.isEmpty || key.hasPrefix("$(") {
                return URL(string: path == "online/topo" ? "https://opentopomap.org/about" : "https://www.openstreetmap.org/copyright")
            }
            #endif
            fallthrough
        default: return URL(string: "https://www.esri.com/en-us/legal/terms/data-attributions")
        }
    }
    private func add(style: MLNStyle, id: String, path: String, tileSize: Int, maxZoom: Int, attribution: String, effect: String, revision: Int) {
        let source = MLNRasterTileSource(identifier: id, tileURLTemplates: ["https://tiles.gridfix.invalid/\(path)/{z}/{x}/{y}?effect=\(effect)&v=\(revision)"], options: [.tileSize: tileSize, .minimumZoomLevel: 0, .maximumZoomLevel: maxZoom,
            .attributionInfos: [MLNAttributionInfo(title: NSAttributedString(string: attribution), url: attributionURL(path: path))]])
        style.addSource(source)
        let layer = MLNRasterStyleLayer(identifier: id, source: source)
        layer.rasterFadeDuration = NSExpression(forConstantValue: 0)
        if id == "map-shadows", let base = style.layer(withIdentifier: "map-base") {
            style.insertLayer(layer, above: base)
        } else if let firstOverlay = style.layers.first(where: { $0.identifier != "background" }) {
            // Keep the base below contours as well as all field/grid overlays,
            // including when it is replaced after those layers are installed.
            style.insertLayer(layer, below: firstOverlay)
        } else { style.addLayer(layer) }
    }
}
