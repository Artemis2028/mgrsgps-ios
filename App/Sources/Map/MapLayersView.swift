import GridFixCore
import SwiftUI
import UniformTypeIdentifiers

struct MapLayersView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var maps: MapLayerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    let bounds: MapBounds
    let zoom: Double
    @State private var importing = false
    @State private var proposedPlan: TileDownloadPlan?
    @State private var planError: String?
    @State private var downloadName = ""
    @State private var deleting: SavedMap?
    var onShow: (SavedMap) -> Void
    private var palette: FieldPalette { FieldPalette(night: night) }
    var body: some View {
        NavigationStack {
            List {
                Section("Base map") {
                    ForEach(maps.layers) { layer in
                        Button { maps.setLayer(layer.key) } label: {
                            HStack { Text(layer.label); Spacer(); if maps.preferences.baseLayer == layer.key { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("layer-\(layer.key)")
                    }
                    #if !DEBUG
                    if maps.layers.count == 2 { Text("Global online layers aren't enabled in this build. USGS maps cover the United States; import an MBTiles map for other areas.").font(.footnote).foregroundStyle(palette.inkDim) }
                    #endif
                }
                Section("Map overlays") {
                    Toggle("\(settings.gridName) grid", isOn: Binding(get: { maps.preferences.gridEnabled }, set: maps.setGrid))
                    Toggle("Terrain shading", isOn: Binding(get: { maps.preferences.hillshade }, set: maps.setHillshade))
                        .disabled(maps.selectedMap != nil || !maps.layers.contains { $0.key == "hillshade" })
                    Toggle("Contour lines", isOn: Binding(get: { maps.preferences.contours }, set: maps.setContours))
                }
                Section {
                    Toggle("Offline only", isOn: Binding(get: { maps.preferences.offlineOnly }, set: maps.setOfflineOnly))
                    Text("Use saved areas, imported maps, and available browse-cache tiles without map network requests.")
                        .font(.footnote).foregroundStyle(palette.inkDim)
                    Button("Import MBTiles file…") { importing = true }.disabled(maps.isImporting).accessibilityIdentifier("import-mbtiles")
                    if maps.isImporting { ProgressView("Importing map…") }
                    if maps.selectedMap == nil {
                        Button("Download visible area for offline") { propose(maps.selectedLayer) }
                            .disabled(!maps.selectedLayer.bulkDownload || maps.preferences.offlineOnly || maps.activeDownload != nil)
                            .accessibilityIdentifier("download-map-area")
                        if !maps.selectedLayer.bulkDownload {
                            Text("This layer supports browse caching only. Area downloads are available for USGS Topo and USGS Imagery, which cover the US. Raster MBTiles work worldwide where your file has coverage.")
                                .font(.footnote).foregroundStyle(palette.inkDim)
                        }
                    }
                    Button("Download elevation for this area") { propose(MapCatalog.elevation) }
                        .disabled(maps.preferences.offlineOnly || maps.activeDownload != nil)
                } header: { Text("Offline maps") }
                if let plan = proposedPlan {
                    Section("Download this area") {
                        TextField("Area name", text: $downloadName)
                        Text("\(plan.tiles.count) tiles · zoom \(plan.minZoom)–\(plan.maxZoom) · about \(ByteCountFormatter.string(fromByteCount: plan.estimatedBytes, countStyle: .file))")
                            .font(.subheadline).accessibilityIdentifier("offline-estimate")
                        Text("Keep the app open while downloading. Leaving the app pauses the download; saved tiles are kept so it can resume.")
                            .font(.footnote).foregroundStyle(palette.inkDim)
                        Button("Download") { maps.startDownload(plan: plan, name: downloadName); proposedPlan = nil }
                            .accessibilityIdentifier("confirm-map-download")
                        Button("Cancel", role: .cancel) { proposedPlan = nil }
                    }
                }
                if let error = planError { Text(error).font(.footnote).foregroundStyle(palette.warn).accessibilityIdentifier("map-plan-error") }
                if let error = maps.loadError { Text(error).foregroundStyle(palette.warn) }
                if let message = maps.message { Text(message).font(.footnote).accessibilityIdentifier("map-operation-status") }
                if maps.activeDownload != nil {
                    Section("Downloading") {
                        Text("\(maps.downloadProgress) tiles saved").monospacedDigit()
                        Button("Pause download") { maps.pauseDownload() }
                    }
                }
                Section("Saved areas & imported maps") {
                    if maps.savedMaps.isEmpty { Text("No offline maps saved yet").font(.subheadline).foregroundStyle(palette.inkDim) }
                    ForEach(maps.savedMaps) { map in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(map.name).font(.headline)
                            Text("\(map.complete ? "Ready" : "Partial · resume to finish") · zoom \(map.minZoom)–\(map.maxZoom)")
                                .font(.caption).foregroundStyle(palette.inkDim)
                            HStack {
                                if map.layerKey != "dem" {
                                    Button("Show map") { maps.setLayer(map.imported ? "mbtiles:" + map.id : map.layerKey!); onShow(map); dismiss() }
                                        .accessibilityIdentifier("show-map-\(map.name)")
                                }
                                if !map.complete && !map.imported {
                                    Button("Resume") { maps.resume(map) }.disabled(maps.activeDownload != nil || maps.preferences.offlineOnly)
                                }
                                Spacer()
                                Button("Delete", role: .destructive) { deleting = map }
                                    .disabled(maps.activeDownload == map.id)
                            }.buttonStyle(.borderless)
                        }.padding(.vertical, 6)
                    }
                }
                Section {
                    Button("Clear browse cache") { maps.clearBrowseCache() }
                    Text("The map cache budget is 600 MB. Named offline areas are kept until you delete them; browse caching uses the remaining space. Imported MBTiles are separate. Elevation has a separate 300 MB budget.")
                        .font(.footnote).foregroundStyle(palette.inkDim)
                }
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .foregroundStyle(palette.ink).tint(palette.accent)
            .navigationTitle("Map layers").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                if case let .success(urls) = result, let url = urls.first { Task { await maps.importMap(url) } }
            }
            .alert("Delete saved map?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete", role: .destructive) { if let deleting { Task { await maps.delete(deleting) } }; deleting = nil }
                Button("Keep map", role: .cancel) { deleting = nil }
            } message: { Text("This removes the saved map from this device.") }
        }.fieldSheetAppearance()
    }
    private func propose(_ layer: RasterLayer) {
        do {
            let tileZoom = zoom + log2(512.0 / Double(layer.tileSize))
            proposedPlan = try TileDownloadPlan(bounds: bounds, currentZoom: tileZoom, layer: layer, elevation: layer.key == "dem")
            downloadName = layer.label; planError = nil
        } catch { proposedPlan = nil; planError = error.localizedDescription }
    }
}
