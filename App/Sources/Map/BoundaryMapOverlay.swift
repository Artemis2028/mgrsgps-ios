import GridFixCore
import MapLibre

@MainActor
final class BoundaryMapOverlay {
    private var source: MLNShapeSource?
    private weak var style: MLNStyle?
    private var vertices: [BoundaryVertexAnnotation] = []
    private var previous: [GeoPoint] = []
    private var editing = false
    func install(style: MLNStyle) {
        guard source == nil else { return }
        self.style = style
        let source = MLNShapeSource(identifier: "boundary-area",shape: nil,options: nil)
        self.source = source; style.addSource(source)
        let fill = MLNFillStyleLayer(identifier: "boundary-inside",source: source)
        fill.predicate = NSPredicate(format: "kind == %@","area")
        fill.fillColor = NSExpression(forConstantValue: UIColor.systemGreen)
        fill.fillOpacity = NSExpression(forConstantValue: 0.12); style.addLayer(fill)
        let line = MLNLineStyleLayer(identifier: "boundary-lines",source: source)
        line.predicate = NSPredicate(format: "kind == %@","line")
        line.lineWidth = NSExpression(forConstantValue: 4); style.addLayer(line)
        redraw(previous,editing: editing)
    }
    func update(points: [GeoPoint], editing: Bool, selected: Int?, night: Bool, map: MLNMapView) {
        if previous != points || self.editing != editing {
            previous = points; self.editing = editing; redraw(points,editing: editing)
            map.removeAnnotations(vertices); vertices = []
            if editing {
                vertices = points.enumerated().map { BoundaryVertexAnnotation(index: $0.offset,point: $0.element) }
                map.addAnnotations(vertices)
            }
        }
        let color = night ? UIColor.systemRed : UIColor.systemOrange
        (style?.layer(withIdentifier: "boundary-lines") as? MLNLineStyleLayer)?.lineColor = NSExpression(forConstantValue: color)
        (style?.layer(withIdentifier: "boundary-inside") as? MLNFillStyleLayer)?.fillColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor.systemGreen)
        for vertex in vertices {
            if let view = map.view(for: vertex) as? BoundaryVertexView { view.configure(index: vertex.index,selected: selected == vertex.index,night: night) }
        }
    }
    private func redraw(_ points: [GeoPoint],editing: Bool) {
        var features: [[String: Any]] = []
        if points.count >= 2 {
            let closed = points.count >= 3 ? points + [points[0]] : points
            let segments = FieldMapGeometry.lineSegments(closed)
            features.append(["type":"Feature","properties":["kind":"line"],"geometry":["type":"MultiLineString","coordinates":segments.map { $0.map { [$0.lon,$0.lat] } }]])
            // Unwrap dateline polygons so the permitted fill stays local.
            if points.count >= 3, (try? BoundaryGeometry(vertices: points)) != nil {
                let ref = points[0].lon
                let ring = (points + [points[0]]).map { p in [ref + ((p.lon-ref+540).truncatingRemainder(dividingBy: 360))-180,p.lat] }
                features.append(["type":"Feature","properties":["kind":"area"],"geometry":["type":"Polygon","coordinates":[ring]]])
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["type":"FeatureCollection","features":features]) {
            source?.shape = try? MLNShape(data: data,encoding: String.Encoding.utf8.rawValue)
        }
    }
}

final class BoundaryVertexAnnotation: MLNPointAnnotation {
    let index: Int
    init(index: Int,point: GeoPoint) {
        self.index = index; super.init()
        coordinate = CLLocationCoordinate2D(latitude: point.lat,longitude: point.lon)
        title = "Boundary point \(index + 1)"
    }
    required init?(coder: NSCoder) { fatalError("Created by boundary editor") }
}
final class BoundaryVertexView: MLNAnnotationView {
    private let label = UILabel()
    var onSelect: (() -> Void)?
    var onDragStart: (() -> Void)?
    @objc private func selectVertex() { onSelect?() }
    override func accessibilityActivate() -> Bool { onSelect?(); return true }
    var onDragEnd: ((CLLocationCoordinate2D) -> Void)?
    private var dragOrigin: CLLocationCoordinate2D?
    override func setDragState(_ dragState: MLNAnnotationViewDragState,animated: Bool) {
        if dragState == .starting { dragOrigin = annotation?.coordinate; onDragStart?() }
        super.setDragState(dragState,animated: animated)
        if dragState == .ending {
            DispatchQueue.main.async { [weak self] in
                guard let self, let point = self.annotation?.coordinate else { return }
                self.onDragEnd?(point)
            }
        } else if dragState == .canceling, let dragOrigin { (annotation as? MLNPointAnnotation)?.coordinate = dragOrigin }
    }
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0,y: 0,width: 44,height: 44)
        label.frame = CGRect(x: 6,y: 6,width: 32,height: 32)
        label.textAlignment = .center; label.font = .monospacedSystemFont(ofSize: 15,weight: .bold)
        label.layer.cornerRadius = 16; label.clipsToBounds = true
        addSubview(label); isDraggable = true; isAccessibilityElement = true; accessibilityTraits = .button
        let tap = UITapGestureRecognizer(target: self,action: #selector(selectVertex))
        tap.cancelsTouchesInView = false; addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("Created by boundary editor") }
    func configure(index: Int, selected: Bool,night: Bool) {
        label.text = "\(index+1)"; label.textColor = selected ? .black : (night ? .systemRed : .white)
        label.backgroundColor = selected ? (night ? .systemRed : .systemOrange) : .black
        label.layer.borderWidth = 2; label.layer.borderColor = (night ? UIColor.systemRed : UIColor.systemOrange).cgColor
        accessibilityLabel = "Boundary point \(index+1)"; accessibilityIdentifier = "boundary-point-\(index)"
        accessibilityValue = selected ? "Selected. Move or insert a kink after this point." : "Tap to select. Drag to move."
    }
}
