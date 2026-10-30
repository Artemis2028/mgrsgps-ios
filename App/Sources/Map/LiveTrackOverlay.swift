import GridFixCore
import MapLibre

@MainActor
final class LiveTrackOverlay {
    private var source: MLNShapeSource?
    private var shape: MLNShape?
    private var previous: [GeoPoint] = []
    func install(into style: MLNStyle) {
        guard source == nil else { return }
        let source = MLNShapeSource(identifier: "recording", shape: shape, options: nil)
        self.source = source; style.addSource(source)
        let line = MLNLineStyleLayer(identifier: "recording-line", source: source)
        line.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
        line.lineWidth = NSExpression(forConstantValue: 4)
        style.addLayer(line)
        let head = MLNCircleStyleLayer(identifier: "recording-head", source: source)
        head.circleRadius = NSExpression(forConstantValue: 6)
        head.circleColor = NSExpression(forConstantValue: UIColor.systemRed)
        head.circleStrokeWidth = NSExpression(forConstantValue: 2)
        head.circleStrokeColor = NSExpression(forConstantValue: UIColor.black)
        style.addLayer(head)
    }
    func update(_ points: [GeoPoint]) {
        guard previous != points else { return }
        previous = points
        var features: [[String: Any]] = []
        if points.count >= 2 {
            features.append(["type": "Feature", "geometry": ["type": "MultiLineString", "coordinates": FieldMapGeometry.lineSegments(points).filter { $0.count >= 2 }.map { $0.map { [$0.lon, $0.lat] } }]])
        }
        if let last = points.last { features.append(["type": "Feature", "geometry": ["type": "Point", "coordinates": [last.lon, last.lat]]]) }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features])
            shape = try MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
            source?.shape = shape
        } catch { NSLog("[recording-overlay] \(error)") }
    }
}
