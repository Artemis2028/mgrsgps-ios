import Foundation
import GridFixCore
import MapLibre

/// Puts the MGRS grid on a MapLibre map.
///
/// All of the thinking is in `GridFixCore.MgrsGrid`, which is pure geometry and
/// has its own tests. This file is only the wiring: one GeoJSON source, four
/// style layers, and a rebuild when the camera settles. Keeping the split here
/// is deliberate — the Android overlay put the doctrine and the drawing in one
/// 606-line Canvas pass, and none of the doctrine could be tested.
@MainActor
final class GridOverlay {

    static let sourceID = "mgrs-grid"

    private weak var style: MLNStyle?
    private var source: MLNShapeSource?
    private var lastKey: String = ""

    /// What the readout shows: "1 km", "100 m", "GZD".
    private(set) var intervalLabel: String = "—"
    var onIntervalChange: ((String) -> Void)?

    var nightMode = false { didSet { applyColors() } }
    /// True over satellite imagery, where dark lines disappear.
    var lightLines = false { didSet { applyColors() } }

    // Blackout, matching the Android overlay.
    private var lineColor: UIColor {
        if nightMode { return UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1) }
        return lightLines ? .white : UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
    }
    private var gzdColor: UIColor {
        nightMode ? UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
                  : UIColor(red: 0.88, green: 0.71, blue: 0.35, alpha: 1)
    }
    private var haloColor: UIColor {
        (nightMode || lightLines) ? .black : .white
    }

    // MARK: - Style

    func install(into style: MLNStyle) {
        self.style = style
        let src = MLNShapeSource(identifier: Self.sourceID, shape: nil, options: nil)
        style.addSource(src)
        source = src

        // Fine metre grid, thinnest.
        let fine = MLNLineStyleLayer(identifier: "mgrs-fine", source: src)
        fine.predicate = NSPredicate(format: "kind == %@", "metre")
        fine.lineWidth = NSExpression(forConstantValue: 0.9)
        style.addLayer(fine)

        // 100 km squares, heavier.
        let square = MLNLineStyleLayer(identifier: "mgrs-square", source: src)
        square.predicate = NSPredicate(format: "kind == %@", "square")
        square.lineWidth = NSExpression(forConstantValue: 1.7)
        style.addLayer(square)

        // Grid zone designators, heaviest and in the accent colour — they are
        // the boundary a grid reference is meaningless across.
        let gzd = MLNLineStyleLayer(identifier: "mgrs-gzd", source: src)
        gzd.predicate = NSPredicate(format: "kind == %@", "gzd")
        gzd.lineWidth = NSExpression(forConstantValue: 2.2)
        style.addLayer(gzd)

        // Labels. Placed along the line, which is what a paper sheet does and
        // what survives map rotation; the Android version anchors them to the
        // screen edge instead and has to be switched off when the map turns.
        let labels = MLNSymbolStyleLayer(identifier: "mgrs-labels", source: src)
        labels.text = NSExpression(forKeyPath: "text")
        labels.textFontSize = NSExpression(forConstantValue: 12)
        labels.textFontNames = NSExpression(forConstantValue: ["Menlo-Bold", "Courier-Bold"])
        labels.textHaloWidth = NSExpression(forConstantValue: 1.6)
        labels.symbolPlacement = NSExpression(forConstantValue: "line")
        labels.textAllowsOverlap = NSExpression(forConstantValue: false)
        labels.textIgnoresPlacement = NSExpression(forConstantValue: false)
        style.addLayer(labels)

        applyColors()
    }

    private func applyColors() {
        guard let style else { return }
        for id in ["mgrs-fine", "mgrs-square"] {
            (style.layer(withIdentifier: id) as? MLNLineStyleLayer)?
                .lineColor = NSExpression(forConstantValue: lineColor)
        }
        (style.layer(withIdentifier: "mgrs-gzd") as? MLNLineStyleLayer)?
            .lineColor = NSExpression(forConstantValue: gzdColor)
        if let l = style.layer(withIdentifier: "mgrs-labels") as? MLNSymbolStyleLayer {
            l.textColor = NSExpression(forConstantValue: lineColor)
            l.textHaloColor = NSExpression(forConstantValue: haloColor)
        }
    }

    // MARK: - Refresh

    /// Rebuild for the current camera. Cheap to call on every camera-idle: it
    /// short-circuits when the viewport has not moved enough to change the
    /// geometry, which is most of the time while a finger is on the screen.
    func refresh(bounds: MLNCoordinateBounds, metersPerPoint: Double) {
        let key = String(format: "%.4f,%.4f,%.4f,%.4f,%.2f",
                         bounds.sw.latitude, bounds.sw.longitude,
                         bounds.ne.latitude, bounds.ne.longitude, metersPerPoint)
        guard key != lastKey else { return }
        lastKey = key

        // A margin so lines do not pop in at the edge during a pan.
        let latPad = (bounds.ne.latitude - bounds.sw.latitude) * 0.15
        let lonSpan = bounds.ne.longitude - bounds.sw.longitude
        let lonPad = (lonSpan > 0 ? lonSpan : lonSpan + 360.0) * 0.15

        let result = MgrsGrid.build(
            latSouth: max(bounds.sw.latitude - latPad, -80.0),
            latNorth: min(bounds.ne.latitude + latPad, 84.0),
            lonWest: bounds.sw.longitude - lonPad,
            lonEast: bounds.ne.longitude + lonPad,
            metersPerPoint: metersPerPoint
        )

        source?.shape = try? MLNShape(data: result.geoJSON(),
                                      encoding: String.Encoding.utf8.rawValue)

        if result.intervalLabel != intervalLabel {
            intervalLabel = result.intervalLabel
            onIntervalChange?(result.intervalLabel)
        }
    }
}
