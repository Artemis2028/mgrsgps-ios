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
    func preview(_ points: [GeoPoint]?) { redraw(points ?? previous,editing: editing,preview: points != nil) }
    private func redraw(_ points: [GeoPoint],editing: Bool,preview: Bool = false) {
        var features: [[String: Any]] = []
        if drawArea && points.count >= 2 {
            let closed = points.count >= 3 ? points + [points[0]] : points
            let segments = FieldMapGeometry.lineSegments(closed)
            features.append(["type":"Feature","properties":["kind":"line"],"geometry":["type":"MultiLineString","coordinates":segments.map { $0.map { [$0.lon,$0.lat] } }]])
            // Unwrap dateline polygons so the permitted fill stays local.
            if !preview, points.count >= 3, (try? BoundaryGeometry(vertices: points)) != nil {
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
        title = isMidpoint ? "Add point on \(owner) segment \(index+1)" : "\(owner.capitalized) point \(index+1)"
    }
    required init?(coder: NSCoder) { fatalError("Created by boundary editor") }
}
/// Transient geometry for a drag. The source remains unchanged until release.
struct BoundaryVertexPreview: Sendable {
    let source: [GeoPoint]
    let index: Int
    let midpoint: Bool
    var point: GeoPoint
    var points: [GeoPoint]? {
        guard source.indices.contains(index) else { return nil }
        var copy = source
        if midpoint { copy.insert(point,at: index+1) } else { copy[index] = point }
        return copy
    }
}

/// One accepted finger gesture owns its exact source and callback. Previewing
/// never edits the draft; cancellation/reuse restores only that source object.
@MainActor
final class BoundaryVertexDrag {
    private let annotation: BoundaryVertexAnnotation
    private let origin: CLLocationCoordinate2D
    private let commit: (CLLocationCoordinate2D) -> Void
    private(set) var active = true
    private let current: () -> Bool
    init(annotation: BoundaryVertexAnnotation,current: @escaping () -> Bool = { true },commit: @escaping (CLLocationCoordinate2D) -> Void) {
        self.annotation = annotation; origin = annotation.coordinate; self.current = current; self.commit = commit
    }
    func move(to coordinate: CLLocationCoordinate2D) {
        guard active else { return }; guard current() else { cancel(); return }; annotation.coordinate = coordinate
    }
    func finish(at coordinate: CLLocationCoordinate2D) {
        guard active else { return }; guard current() else { cancel(); return }; active = false
        annotation.coordinate = coordinate; commit(coordinate)
    }
    func cancel() {
        guard active else { return }; active = false; annotation.coordinate = origin
    }
}

final class BoundaryVertexView: MLNAnnotationView {
    private let label = UILabel()
    var onSelect: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: ((CLLocationCoordinate2D) -> Void)?
    var onDragPreview: ((CLLocationCoordinate2D) -> Void)?
    var onDragCancel: (() -> Void)?
    var dragIsCurrent: (() -> Bool)?
    private var drag: BoundaryVertexDrag?
    private weak var dragMap: MLNMapView?
    private var previousInteraction: (scroll: Bool,zoom: Bool,rotate: Bool)?
    private var grip = CGPoint.zero
    @objc private func selectVertex() { onSelect?() }
    override func accessibilityActivate() -> Bool { cancelDrag(); onSelect?(); return true }
    private func restoreMapInteraction() {
        if let previousInteraction {
            dragMap?.isScrollEnabled = previousInteraction.scroll; dragMap?.isZoomEnabled = previousInteraction.zoom; dragMap?.isRotateEnabled = previousInteraction.rotate
        }
        previousInteraction = nil; dragMap = nil
    }
    private func cancelDrag() {
        let hadDrag = drag != nil
        drag?.cancel(); drag = nil; restoreMapInteraction()
        if hadDrag { onDragCancel?() }
    }
    func cancelEditingDrag() { cancelDrag() }
    override func prepareForReuse() {
        cancelDrag(); onSelect = nil; onDragStart = nil; onDragEnd = nil; onDragPreview = nil; onDragCancel = nil; dragIsCurrent = nil
        super.prepareForReuse()
    }
    override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview == nil { cancelDrag() }
        super.willMove(toSuperview: newSuperview)
    }
    @objc private func moveVertex(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            guard gesture.numberOfTouches == 1 else { return }
            var parent = superview
            while parent != nil && !(parent is MLNMapView) { parent = parent?.superview }
            guard let map = parent as? MLNMapView,let annotation = annotation as? BoundaryVertexAnnotation,let commit = onDragEnd else { return }
            cancelDrag()
            let touch = gesture.location(in: map),anchor = map.convert(annotation.coordinate,toPointTo: map)
            grip = CGPoint(x: anchor.x-touch.x,y: anchor.y-touch.y)
            dragMap = map; previousInteraction = (map.isScrollEnabled,map.isZoomEnabled,map.isRotateEnabled)
            map.isScrollEnabled = false; map.isZoomEnabled = false; map.isRotateEnabled = false
            onDragStart?()
            drag = BoundaryVertexDrag(annotation: annotation,current: dragIsCurrent ?? { true },commit: commit)
            return
        }
        guard let map = dragMap,let drag else { return }
        guard dragIsCurrent?() ?? true else { cancelDrag(); return }
        let touch = gesture.location(in: map)
        let point = map.convert(CGPoint(x: touch.x+grip.x,y: touch.y+grip.y),toCoordinateFrom: map)
        switch gesture.state {
        case .changed:
            guard gesture.numberOfTouches == 1 else { cancelDrag(); return }
            drag.move(to: point); onDragPreview?(point)
        case .ended:
            // End interaction before publishing: publication can replace or
            // recycle this annotation view during the same run-loop turn.
            self.drag = nil; restoreMapInteraction(); drag.finish(at: point)
        case .cancelled,.failed: cancelDrag()
        default: break
        }
    }
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0,y: 0,width: 44,height: 44)
        label.frame = CGRect(x: 6,y: 6,width: 32,height: 32)
        label.textAlignment = .center; label.font = .monospacedSystemFont(ofSize: 15,weight: .bold)
        label.layer.cornerRadius = 16; label.clipsToBounds = true
        addSubview(label); isDraggable = false; isAccessibilityElement = true; accessibilityTraits = .button
        let hold = UILongPressGestureRecognizer(target: self,action: #selector(moveVertex(_:)))
        hold.minimumPressDuration = 0.45; hold.numberOfTouchesRequired = 1
        addGestureRecognizer(hold)
        let tap = UITapGestureRecognizer(target: self,action: #selector(selectVertex))
        tap.cancelsTouchesInView = false; tap.require(toFail: hold); addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("Created by boundary editor") }
    func configure(index: Int, selected: Bool,night: Bool,owner: String = "boundary",isMidpoint: Bool = false) {
        label.frame = isMidpoint ? CGRect(x: 12,y: 12,width: 20,height: 20) : CGRect(x: 6,y: 6,width: 32,height: 32)
        label.layer.cornerRadius = isMidpoint ? 10 : 16
        label.text = isMidpoint ? "+" : "\(index+1)"; label.textColor = selected ? .black : (night ? .systemRed : .white)
        label.backgroundColor = selected ? (night ? .systemRed : .systemOrange) : .black
        label.layer.borderWidth = 2; label.layer.borderColor = (night ? UIColor.systemRed : UIColor.systemOrange).cgColor
        accessibilityLabel = isMidpoint ? "Add point on \(owner) segment \(index+1)" : "\(owner.capitalized) point \(index+1)"
        accessibilityIdentifier = "\(owner)-\(isMidpoint ? "midpoint" : "point")-\(index)"
        accessibilityValue = isMidpoint ? "Long-press and drag to add a point. Double-tap to insert here." : (selected ? "Selected. Drag to move. Add point inserts after this point." : "Tap to select. Long-press and drag to move.")
    }
}
