import GridFixCore
import MapLibre

@MainActor
final class NavigationLaneMapOverlay {
    private var source: MLNShapeSource?
    private var shape: MLNShape?
    private weak var style: MLNStyle?
    private var previous: [NavLane] = []
    private var previousGraphics: [Backup.Graphic] = []
    private var previousWaypoints:[Waypoint] = []
    private var previousFolders: [FolderInfo] = []
    private var previousDraft: NavLane?
    private var previousNight: Bool?
    private(set) var points: [GeoPoint] = []
    func install(_ style: MLNStyle) {
        guard source == nil else { return }
        self.style = style
        let source = MLNShapeSource(identifier: "nav-lanes",shape: shape,options: nil)
        self.source = source; style.addSource(source)
        let fill = MLNFillStyleLayer(identifier: "nav-lane-fill",source: source)
        fill.predicate = NSPredicate(format: "kind == %@","area")
        fill.fillColor = NSExpression(forConstantValue: UIColor.systemGreen); fill.fillOpacity = NSExpression(forConstantValue: 0.12)
        style.addLayer(fill)
        for role in LaneLimit.allCases {
            let line = MLNLineStyleLayer(identifier: "nav-lane-"+role.rawValue,source: source)
            line.predicate = NSPredicate(format: "kind == %@",role.rawValue)
            line.lineColor = NSExpression(forConstantValue: role == .backstop ? UIColor.systemRed : UIColor.systemOrange)
            line.lineWidth = NSExpression(forConstantValue: 3)
            if role != .backstop { line.lineDashPattern = NSExpression(forConstantValue: [3,2]) }
            style.addLayer(line)
        }
        for role in LaneLimit.allCases {
            let labels = MLNSymbolStyleLayer(identifier: "nav-lane-labels-"+role.rawValue,source: source)
            labels.predicate = NSPredicate(format: "kind == %@ AND role == %@","label",role.rawValue)
            labels.text = NSExpression(forKeyPath: "name"); labels.textFontSize = NSExpression(forConstantValue: 12)
            labels.maximumTextWidth = NSExpression(forConstantValue: 10)
            labels.textAnchor = NSExpression(forConstantValue: role == .left ? "right" : (role == .right ? "left" : "bottom"))
            labels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: role == .backstop ? 0 : (role == .left ? -0.5 : 0.5),dy: role == .backstop ? -1.5 : 0)))
            labels.textAllowsOverlap = NSExpression(forConstantValue: true)
            labels.textColor = NSExpression(forConstantValue: UIColor.white)
            labels.textHaloColor = NSExpression(forConstantValue: UIColor.black); labels.textHaloWidth = NSExpression(forConstantValue: 1.5)
            style.addLayer(labels)
        }
        let night = previousNight ?? false; previousNight = nil
        update(lanes: previous,draft: previousDraft,graphics: previousGraphics,folders: previousFolders,waypoints:previousWaypoints,night: night)
    }
    func update(lanes: [NavLane],draft: NavLane?,graphics: [Backup.Graphic],folders: [FolderInfo],waypoints:[Waypoint],night: Bool) {
        guard waypoints != previousWaypoints || lanes != previous || draft != previousDraft || graphics != previousGraphics || folders != previousFolders || night != previousNight else { return }
        previousWaypoints=waypoints
        previous = lanes; previousDraft = draft; previousGraphics = graphics; previousFolders = folders; previousNight = night
        var features: [[String:Any]] = []
        points = []
        var visible = lanes.filter { lane in
            lane.visible && lane.id != draft?.id && folders.first(where: { $0.name.caseInsensitiveCompare(lane.folder) == .orderedSame })?.visible != false
        }
        if let draft { visible.append(draft) }
        for lane in visible {
            let resolved = try? NavLanes.resolve(lane,graphics: graphics,waypoints:waypoints)
            let display = resolved?.shape.mapLines()
            if let resolved,let first = resolved.shape.outline().first {
                let ring = resolved.shape.outline()
                let coordinates = (ring+[first]).map { [first.lon+(($0.lon-first.lon+540).truncatingRemainder(dividingBy: 360))-180,$0.lat] }
                features.append(["type":"Feature","properties":["kind":"area"],"geometry":["type":"Polygon","coordinates":[coordinates]]])
            }
            for (role,line) in [(LaneLimit.left,lane.left),(.right,lane.right),(.backstop,lane.backstop)] {
                let drawn = NavLanes.points(line,graphics: graphics)
                guard let points = display.map({ role == .left ? $0.left : (role == .right ? $0.right : $0.backstop) }) ?? drawn else { continue }
                self.points += points
                let segments = FieldMapGeometry.lineSegments(points)
                features.append(["type":"Feature","properties":["kind":role.rawValue],"geometry":["type":"MultiLineString","coordinates":segments.map { $0.map { [$0.lon,$0.lat] } }]])
                let lengths = zip(points,points.dropFirst()).map { a,b in Geodesy.navInfo(fromLat: a.lat,fromLon: a.lon,toLat: b.lat,toLon: b.lon).distanceMeters }
                var remaining = lengths.reduce(0,+)/2, point = points[0]
                for i in lengths.indices {
                    if remaining <= lengths[i] {
                        let fraction = lengths[i] > 0 ? remaining/lengths[i] : 0
                        let a = points[i], b = points[i+1], delta = ((b.lon-a.lon+540).truncatingRemainder(dividingBy: 360))-180
                        point = .init(lat: a.lat+(b.lat-a.lat)*fraction,lon: ((a.lon+delta*fraction+540).truncatingRemainder(dividingBy: 360))-180)
                        break
                    }
                    remaining -= lengths[i]
                }
                let prefix = role == .left ? "L" : (role == .right ? "R" : "BS")
                let orientedLine = resolved?.shape.leftWasDrawnAsRight == true && role != .backstop ? (role == .left ? lane.right : lane.left) : line
                let text = prefix+" · "+NavLanes.label(orientedLine,graphics: graphics,fallback: lane.name.isEmpty ? "Lane" : lane.name)
                features.append(["type":"Feature","properties":["kind":"label","role":role.rawValue,"name":text],"geometry":["type":"Point","coordinates":[point.lon,point.lat]]])
            }
        }
        if let bytes = try? JSONSerialization.data(withJSONObject: ["type":"FeatureCollection","features":features]) {
            shape = try? MLNShape(data: bytes,encoding: String.Encoding.utf8.rawValue); source?.shape = shape
        }
        (style?.layer(withIdentifier: "nav-lane-fill") as? MLNFillStyleLayer)?.fillColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor.systemGreen)
        for role in LaneLimit.allCases { (style?.layer(withIdentifier: "nav-lane-labels-"+role.rawValue) as? MLNSymbolStyleLayer)?.textColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor.white) }
        for role in [LaneLimit.left,.right] {
            (style?.layer(withIdentifier: "nav-lane-"+role.rawValue) as? MLNLineStyleLayer)?.lineColor = NSExpression(forConstantValue: night ? UIColor.systemRed : UIColor.systemOrange)
        }
    }
}
