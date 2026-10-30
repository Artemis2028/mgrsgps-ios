import GridFixCore
import MapLibre

@MainActor
final class FieldOverlay {
    private var source: MLNShapeSource?
    private weak var style: MLNStyle?
    private var previous: Backup.Document?
    private var previousFolders: [FolderInfo] = []
    private var previousRetry: UUID?
    private var shape: MLNShape?
    private(set) var points: [GeoPoint] = []
    private(set) var preparing = false
    private(set) var error: String?
    private(set) var routes = 0,tracks = 0
    var onChange: ((Int, Int, Bool) -> Void)?
    var onStatus: ((Bool,String?) -> Void)?
    private var generation = UUID()
    private var operation: Task<Void,Never>?
    private var nightMode = false
    private let prepare: @Sendable (Backup.Document,[FolderInfo]) throws -> FieldMapGeometry.OverlaySnapshot

    init(prepare: @escaping @Sendable (Backup.Document,[FolderInfo]) throws -> FieldMapGeometry.OverlaySnapshot = { try FieldOverlay.prepareSnapshot($0,$1) }) {
        self.prepare = prepare
    }
    nonisolated static func prepareSnapshot(_ document: Backup.Document,_ folders: [FolderInfo]) throws -> FieldMapGeometry.OverlaySnapshot {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTesting"),args.contains("-uiTestHoldMapGeometry") {
            let gate = FileManager.default.temporaryDirectory.appendingPathComponent("mgrsgps-ui-tests/hold-map-geometry")
            while FileManager.default.fileExists(atPath: gate.path) { try Task.checkCancellation(); Thread.sleep(forTimeInterval: 0.01) }
        }
        #endif
        return try FieldMapGeometry.prepareOverlay(document: document,folders: folders)
    }

    func install(into style: MLNStyle) {
        guard self.style !== style else { return }
        self.style = style
        let source = MLNShapeSource(identifier: "field-data", shape: shape, options: nil)
        style.addSource(source); self.source = source
        let fill = MLNFillStyleLayer(identifier: "field-areas", source: source)
        fill.fillColor = NSExpression(forConstantValue: UIColor.systemBlue)
        fill.fillOpacity = NSExpression(forConstantValue: 0.12)
        style.addLayer(fill)
        for (kind, color) in [("route", UIColor.systemOrange), ("track", .systemBlue), ("graphic", .systemPurple)] {
            let layer = MLNLineStyleLayer(identifier: "field-\(kind)", source: source)
            layer.predicate = NSPredicate(format: "kind == %@", kind)
            layer.lineColor = NSExpression(forConstantValue: color)
            layer.lineWidth = NSExpression(forConstantValue: 3)
            style.addLayer(layer)
        }
        let labels = MLNSymbolStyleLayer(identifier: "field-labels", source: source)
        labels.predicate = NSPredicate(format: "kind == %@", "label")
        labels.text = NSExpression(forKeyPath: "name")
        labels.textFontNames = NSExpression(forConstantValue: ["Open Sans Semibold"])
        labels.textFontSize = NSExpression(forConstantValue: 12)
        labels.textColor = NSExpression(forConstantValue: UIColor.white)
        labels.textHaloColor = NSExpression(forConstantValue: UIColor.black)
        labels.textHaloWidth = NSExpression(forConstantValue: 1.5)
        style.addLayer(labels)
        applyPalette()
    }

    func update(document: Backup.Document, folders: [FolderInfo], night: Bool,retryToken: UUID? = nil) {
        nightMode = night
        if previous != document || previousFolders != folders || previousRetry != retryToken {
            previous = document; previousFolders = folders; previousRetry = retryToken
            operation?.cancel(); generation = UUID(); let token = generation
            preparing = true; error = nil
            // Hide/delete changes must remove the old drawing immediately.
            shape = nil; source?.shape = nil; points = []; routes = 0; tracks = 0
            Task { @MainActor [weak self] in
                guard let self,self.generation == token,self.preparing else { return }
                self.onStatus?(true,nil); self.onChange?(0,0,false)
            }
            let builder = prepare
            let worker = Task.detached(priority: .userInitiated) { try builder(document,folders) }
            operation = Task { [weak self] in
                do {
                    let snapshot = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                    guard let self,self.generation == token,!Task.isCancelled else { return }
                    // Only the bounded drawing preview enters MapLibre on Main.
                    let shape = try MLNShape(data: snapshot.data,encoding: String.Encoding.utf8.rawValue)
                    self.shape = shape; self.source?.shape = shape; self.points = snapshot.points
                    self.routes = snapshot.routes; self.tracks = snapshot.tracks; self.preparing = false; self.operation = nil
                    self.onStatus?(false,nil); self.onChange?(snapshot.routes,snapshot.tracks,!snapshot.points.isEmpty)
                } catch {
                    guard let self,self.generation == token,!Task.isCancelled else { return }
                    self.preparing = false; self.operation = nil
                    self.error = "Saved map data could not be drawn. Retry or check Routes & tracks."
                    self.onStatus?(false,self.error); self.onChange?(0,0,false)
                }
            }
        }
        applyPalette()
    }
    private func applyPalette() {
        for (kind, color) in [("route", UIColor.systemOrange), ("track", .systemBlue), ("graphic", .systemPurple)] {
            (style?.layer(withIdentifier: "field-\(kind)") as? MLNLineStyleLayer)?.lineColor = NSExpression(forConstantValue: nightMode ? UIColor.systemRed : color)
        }
        (style?.layer(withIdentifier: "field-areas") as? MLNFillStyleLayer)?.fillColor = NSExpression(forConstantValue: nightMode ? UIColor.systemRed : UIColor.systemBlue)
        (style?.layer(withIdentifier: "field-labels") as? MLNSymbolStyleLayer)?.textColor = NSExpression(forConstantValue: nightMode ? UIColor.systemRed : UIColor.white)
    }
    func cancel() {
        generation = UUID(); operation?.cancel(); operation = nil; previous = nil
        preparing = false; error = nil; shape = nil; source?.shape = nil; points = []; routes = 0; tracks = 0
    }
    deinit { operation?.cancel() }
}
