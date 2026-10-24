import GridFixCore
import MapLibre

@MainActor
final class FieldOverlay {
    private var source: MLNShapeSource?
    private weak var style: MLNStyle?
    private var previous: Backup.Document?
    private var previousFolders: [FolderInfo] = []
    private var shape: MLNShape?
    private(set) var points: [GeoPoint] = []
    var onChange: ((Int, Int, Bool) -> Void)?

    func install(into style: MLNStyle) {
        guard source == nil else { return }
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
    }

    func update(document: Backup.Document, folders: [FolderInfo], night: Bool) {
        if previous != document || previousFolders != folders {
            previous = document; previousFolders = folders
            do {
                let snapshot = try FieldMapGeometry.geoJSON(document: document, folders: folders)
                var tracks = document; tracks.graphics = []
                let trackSnapshot = try FieldMapGeometry.geoJSON(document: tracks, folders: folders)
                shape = try MLNShape(data: trackSnapshot.data, encoding: String.Encoding.utf8.rawValue)
                let hidden = Set(folders.filter { !$0.visible }.map { $0.name.lowercased() })
                points = snapshot.points + document.graphics.filter { $0.visible && !hidden.contains($0.folder.lowercased()) }.flatMap(\.mapExtentPoints)
                source?.shape = shape
                DispatchQueue.main.async { [weak self] in self?.onChange?(snapshot.routes, snapshot.tracks, !snapshot.points.isEmpty) }
            } catch { NSLog("[field-overlay] \(error)") }
        }
        for (kind, color) in [("route", UIColor.systemOrange), ("track", .systemBlue), ("graphic", .systemPurple)] {
            (style?.layer(withIdentifier: "field-\(kind)") as? MLNLineStyleLayer)?.lineColor = NSExpression(forConstantValue: night ? UIColor.systemRed : color)
        }
        (style?.layer(withIdentifier: "field-areas") as? MLNFillStyleLayer)?.fillColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor.systemBlue)
        (style?.layer(withIdentifier: "field-labels") as? MLNSymbolStyleLayer)?.textColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor.white)
    }
}
