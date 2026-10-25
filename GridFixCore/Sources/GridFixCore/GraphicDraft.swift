import Foundation

/// Editable control measure; unrelated to the permitted-area crossing monitor.
public struct GraphicDraft: Equatable, Sendable {
    public var graphic: Backup.Graphic
    public private(set) var original: Backup.Graphic?
    public var selected: Int?
    public init(type: String) {
        graphic = .init(id: UUID().uuidString.lowercased(), name: GraphicTypes.label(type), type: type, points: [], createdAt: Int64(Date().timeIntervalSince1970 * 1000))
    }
    public init(_ graphic: Backup.Graphic) { self.graphic = graphic; original = graphic }
    public var vertices: [GeoPoint] { graphic.points.map { .init(lat: $0.lat, lon: $0.lon) } }
    public var canAppend: Bool { graphic.points.count < (GraphicTypes.fixedPoints(graphic.type) ?? 4096) }
    public var validationMessage: String? {
        if graphic.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a name." }
        if graphic.points.count < GraphicTypes.minPoints(graphic.type) { return "Place at least \(GraphicTypes.minPoints(graphic.type)) points." }
        if let count = GraphicTypes.fixedPoints(graphic.type), graphic.points.count != count { return "This graphic uses exactly \(count) points." }
        if graphic.points.contains(where: { !$0.lat.isFinite || !$0.lon.isFinite || abs($0.lat) > 85.05112878 || abs($0.lon) > 180 }) { return "A point is outside map coverage." }
        if graphic.points.count > 1, zip(graphic.points, graphic.points.dropFirst()).contains(where: { $0 == $1 }) { return "Move or remove consecutive duplicate points." }
        return nil
    }
    public mutating func append(_ p: GeoPoint) {
        guard canAppend else { return }; graphic.points.append(.init(lat: p.lat, lon: normalized(p.lon))); selected = graphic.points.count - 1
    }
    public mutating func move(_ index: Int, to p: GeoPoint) {
        guard graphic.points.indices.contains(index) else { return }; graphic.points[index] = .init(lat: p.lat, lon: normalized(p.lon))
    }
    public mutating func insert(_ p: GeoPoint) {
        guard canAppend, let selected, graphic.points.indices.contains(selected) else { return }
        graphic.points.insert(.init(lat: p.lat, lon: normalized(p.lon)), at: selected + 1); self.selected = selected + 1
    }
    public mutating func removeSelected() {
        guard let selected, graphic.points.indices.contains(selected) else { return }; graphic.points.remove(at: selected); self.selected = nil
    }
    public var saved: Backup.Graphic {
        var result = graphic; result.name = graphic.name.trimmingCharacters(in: .whitespacesAndNewlines); result.folder = Folders.canonical(result.folder); return result
    }
    private func normalized(_ lon: Double) -> Double { ((lon + 540).truncatingRemainder(dividingBy: 360)) - 180 }
}

public extension GraphicTypes {
    static func fixedPoints(_ type: String) -> Int? {
        switch type { case "ring": return 2; case "sector": return 3; case "trp", "checkpoint", "dp", "text", "roadblock": return 1; default: return nil }
    }
    static func labelPrefix(_ type: String) -> String {
        ["phase_line":"PL ", "objective":"OBJ ", "aa":"AA ", "lz":"LZ ", "pz":"PZ ", "bp":"BP ", "ea":"EA ", "nai":"NAI ", "tai":"TAI ", "trp":"TRP ", "checkpoint":"CP ", "dp":"DP "][type] ?? ""
    }
    static func placementHint(_ type: String) -> String {
        switch type {
        case "ring": return "Place the centre, then the range edge."
        case "sector": return "Place the apex, left limit, then right limit. The sector sweeps clockwise."
        case "flot": return "Trace the forward line. Scallops face left of the drawing direction, toward the enemy."
        case "lane": return "Trace the cleared lane’s centreline."
        case "boundary": return "Draw an open tactical boundary line. This graphic does not monitor crossings."
        default: return fixedPoints(type) == 1 ? "Tap the map to place the graphic." : "Tap to draw. Hold and drag a point or line to reshape it."
        }
    }
}

public extension Backup.Graphic {
    /// Extents for Android's screen-space Mercator circles. Sectors use the
    /// enclosing circle so both limits and the full outer arc fit on screen.
    var mapExtentPoints: [GeoPoint] {
        let points = self.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) }
        guard (type == "ring" && points.count >= 2) || (type == "sector" && points.count >= 3), let center = points.first else { return points }
        func mercatorY(_ lat: Double) -> Double { log(tan(Double.pi/4 + min(85.05112878,max(-85.05112878,lat)) * Double.pi/360)) / (2 * Double.pi) }
        let cy = mercatorY(center.lat)
        var radius = 0.0
        for point in points.dropFirst().prefix(type == "ring" ? 1 : 2) {
            let dx = ((point.lon-center.lon+540).truncatingRemainder(dividingBy: 360)-180)/360
            radius = max(radius,hypot(dx,mercatorY(point.lat)-cy))
        }
        return points + [(radius,0.0),(-radius,0.0),(0.0,radius),(0.0,-radius)].map { dx,dy in
            let lat = (2*atan(exp((cy+dy)*2*Double.pi))-Double.pi/2)*180/Double.pi
            let lon = ((center.lon+dx*360+540).truncatingRemainder(dividingBy: 360))-180
            return GeoPoint(lat: max(-85.05112878,min(85.05112878,lat)),lon: lon)
        }
    }
}
