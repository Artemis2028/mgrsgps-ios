import GridFixCore
import MapLibre

@MainActor
final class BoundaryMapOverlay {
    private let identifier: String
    private let drawArea: Bool
    init(identifier: String = "boundary", drawArea: Bool = true) { self.identifier = identifier; self.drawArea = drawArea }
    private var source: MLNShapeSource?
    private weak var style: MLNStyle?
    private var vertices: [BoundaryVertexAnnotation] = []
    private var previous: [GeoPoint] = []
    private var editing = false
    private var previousClosed = true
    private var previousInsertion = true
    func install(style: MLNStyle) {
        guard source == nil else { return }
        self.style = style
        let source = MLNShapeSource(identifier: "\(identifier)-area",shape: nil,options: nil)
        self.source = source; style.addSource(source)
        let fill = MLNFillStyleLayer(identifier: "\(identifier)-inside",source: source)
        fill.predicate = NSPredicate(format: "kind == %@","area")
        fill.fillColor = NSExpression(forConstantValue: UIColor.systemGreen)
        fill.fillOpacity = NSExpression(forConstantValue: 0.12); style.addLayer(fill)
        let line = MLNLineStyleLayer(identifier: "\(identifier)-lines",source: source)
        line.predicate = NSPredicate(format: "kind == %@","line")
        line.lineWidth = NSExpression(forConstantValue: 4); style.addLayer(line)
        redraw(previous,editing: editing)
    }
    func update(points: [GeoPoint], editing: Bool, selected: Int?, night: Bool, map: MLNMapView, closed: Bool = true, allowInsertion: Bool = true) {
        if previous != points || self.editing != editing || previousClosed != closed || previousInsertion != allowInsertion {
            previousClosed = closed; previousInsertion = allowInsertion
            previous = points; self.editing = editing; redraw(points,editing: editing)
            map.removeAnnotations(vertices); vertices = []
            if editing {
                vertices = points.enumerated().map { BoundaryVertexAnnotation(index: $0.offset,point: $0.element,owner: identifier) }
                if allowInsertion && points.count >= 2 {
                    let count = closed ? points.count : points.count-1
                    for i in 0..<count {
                        let a = points[i], b = points[(i+1)%points.count]
                        let delta = ((b.lon-a.lon+540).truncatingRemainder(dividingBy: 360))-180
                        let lon = ((a.lon+delta/2+540).truncatingRemainder(dividingBy: 360))-180
                        let latA = min(85.05112878,max(-85.05112878,a.lat)) * Double.pi/180
                        let latB = min(85.05112878,max(-85.05112878,b.lat)) * Double.pi/180
                        let y = (log(tan(Double.pi/4+latA/2))+log(tan(Double.pi/4+latB/2)))/2
                        let latitude = (2*atan(exp(y))-Double.pi/2)*180/Double.pi
                        let point = GeoPoint(lat: latitude,lon: lon)
                        vertices.append(BoundaryVertexAnnotation(index: i,point: point,owner: identifier,isMidpoint: true))
                    }
                }
                map.addAnnotations(vertices)
            }
        }
        let color = night ? UIColor.systemRed : UIColor.systemOrange
        (style?.layer(withIdentifier: "\(identifier)-lines") as? MLNLineStyleLayer)?.lineColor = NSExpression(forConstantValue: color)
        (style?.layer(withIdentifier: "\(identifier)-inside") as? MLNFillStyleLayer)?.fillColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor.systemGreen)
        for vertex in vertices {
            if let view = map.view(for: vertex) as? BoundaryVertexView { view.configure(index: vertex.index,selected: !vertex.isMidpoint && selected == vertex.index,night: night,owner: identifier,isMidpoint: vertex.isMidpoint) }
        }
    }
    private func redraw(_ points: [GeoPoint],editing: Bool) {
        var features: [[String: Any]] = []
        if drawArea && points.count >= 2 {
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
    let owner: String
    let isMidpoint: Bool
    init(index: Int,point: GeoPoint,owner: String = "boundary",isMidpoint: Bool = false) {
        self.index = index; self.owner = owner; self.isMidpoint = isMidpoint; super.init()
        coordinate = CLLocationCoordinate2D(latitude: point.lat,longitude: point.lon)
        title = "\(owner.capitalized) point \(index + 1)"
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
    func configure(index: Int, selected: Bool,night: Bool,owner: String = "boundary",isMidpoint: Bool = false) {
        label.frame = isMidpoint ? CGRect(x: 12,y: 12,width: 20,height: 20) : CGRect(x: 6,y: 6,width: 32,height: 32)
        label.layer.cornerRadius = isMidpoint ? 10 : 16
        label.text = isMidpoint ? "+" : "\(index+1)"; label.textColor = selected ? .black : (night ? .systemRed : .white)
        label.backgroundColor = selected ? (night ? .systemRed : .systemOrange) : .black
        label.layer.borderWidth = 2; label.layer.borderColor = (night ? UIColor.systemRed : UIColor.systemOrange).cgColor
        accessibilityLabel = isMidpoint ? "Add point on segment \(index+1)" : "\(owner.capitalized) point \(index+1)"
        accessibilityIdentifier = "\(owner)-\(isMidpoint ? "midpoint" : "point")-\(index)"
        accessibilityValue = isMidpoint ? "Long-press and drag to add a point. Double-tap to insert here." : (selected ? "Selected. Drag to move. Add point inserts after this point." : "Tap to select. Long-press and drag to move.")
    }
}
