import Foundation

public struct LaneLine: Equatable, Sendable, Codable {
    public var points: [GeoPoint]
    public var graphicId: String?
    public var label: String
    public init(points: [GeoPoint] = [],graphicId: String? = nil,label: String = "") {
        self.points = points; self.graphicId = graphicId; self.label = label
    }
    private enum CodingKeys: String,CodingKey { case points,graphicId,label }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pairs = try c.decodeIfPresent([[Double]].self,forKey: .points) ?? []
        guard pairs.count <= 500, pairs.allSatisfy({ $0.count >= 2 && $0[0].isFinite && abs($0[0]) <= 90 && $0[1].isFinite && abs($0[1]) <= 180 }) else {
            throw LaneShapeError("Invalid lane points")
        }
        points = pairs.map { .init(lat: $0[0],lon: $0[1]) }
        let linked = try c.decodeIfPresent(String.self,forKey: .graphicId)
        graphicId = linked?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? linked : nil
        guard graphicId != nil || points.count >= 2 else { throw LaneShapeError("A lane line needs points or a linked line") }
        label = String((try c.decodeIfPresent(String.self,forKey: .label) ?? "").prefix(80))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points.map { [$0.lat,$0.lon] },forKey: .points)
        if let graphicId { try c.encode(graphicId,forKey: .graphicId) } else { try c.encodeNil(forKey: .graphicId) }
        try c.encode(label,forKey: .label)
    }
}

public struct NavLane: Equatable, Identifiable, Sendable, Codable {
    public enum Scope: String, Codable, Sendable { case checkpoint, route }
    public var id: String, name: String
    public var left: LaneLine, right: LaneLine, backstop: LaneLine
    public var scope: Scope
    public var targetId: String
    public var folder: String
    public var createdAt: Int64
    public var visible: Bool
    public init(id: String = UUID().uuidString.lowercased(),name: String,left: LaneLine,right: LaneLine,backstop: LaneLine,
                scope: Scope,targetId: String,folder: String = Folders.defaultFolder,createdAt: Int64 = 0,visible: Bool = true) {
        self.id = id; self.name = name; self.left = left; self.right = right; self.backstop = backstop
        self.scope = scope; self.targetId = targetId; self.folder = Folders.canonical(folder)
        self.createdAt = createdAt; self.visible = visible
    }
    private enum CodingKeys: String,CodingKey { case id,name,left,right,backstop,scope,targetId,folder,createdAt,visible }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self,forKey: .id)
        targetId = try c.decode(String.self,forKey: .targetId)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && id.utf16.count <= 64,
              !targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LaneShapeError("Invalid lane identity") }
        name = String((try c.decodeIfPresent(String.self,forKey: .name) ?? "").prefix(200))
        left = try c.decode(LaneLine.self,forKey: .left); right = try c.decode(LaneLine.self,forKey: .right)
        backstop = try c.decode(LaneLine.self,forKey: .backstop)
        scope = try c.decode(Scope.self,forKey: .scope)
        folder = Folders.canonical(try c.decodeIfPresent(String.self,forKey: .folder) ?? Folders.defaultFolder)
        createdAt = try c.decodeIfPresent(Int64.self,forKey: .createdAt) ?? 0
        visible = try c.decodeIfPresent(Bool.self,forKey: .visible) ?? true
    }
}

public struct ResolvedLane: Sendable {
    public let lane: NavLane
    public let shape: LaneShape
    public let left: [GeoPoint], right: [GeoPoint], backstop: [GeoPoint]
}

public enum NavLanes {
    public static func sanitizedDrawnPoints(_ points:[GeoPoint])->[GeoPoint] {
        points.filter {$0.lat.isFinite && $0.lon.isFinite}.map {
            var longitude=($0.lon+180).truncatingRemainder(dividingBy:360)
            if longitude<0 {longitude+=360}
            return .init(lat:min(90,max(-90,$0.lat)),lon:longitude-180)
        }
    }
    public static func canBeLimit(_ graphic: Backup.Graphic) -> Bool {
        !GraphicTypes.isArea(graphic.type) && graphic.points.count >= 2 && GraphicTypes.fixedPoints(graphic.type) == nil
    }
    /// Display visibility does not turn off guidance. A checkpoint lane wins
    /// over its route's lane, including when a newer route lane also matches.
    public static func forTarget(_ lanes: [NavLane],target: Waypoint?) -> NavLane? {
        guard let target else { return nil }
        let newest = lanes.sorted { $0.createdAt > $1.createdAt }
        return newest.first { $0.scope == .checkpoint && $0.targetId == target.id }
            ?? target.sourceRouteId.flatMap { route in newest.first { $0.scope == .route && $0.targetId == route } }
    }
    public static func points(_ line: LaneLine,graphics: [Backup.Graphic]) -> [GeoPoint]? {
        if let id = line.graphicId {
            guard let g = graphics.first(where: { $0.id == id }),g.points.count >= 2 else { return nil }
            return g.points.map { .init(lat: $0.lat,lon: $0.lon) }
        }
        return line.points.count >= 2 ? line.points : nil
    }
    public static func label(_ line: LaneLine,graphics: [Backup.Graphic],fallback: String) -> String {
        label(line,lookup: { id in graphics.first { $0.id == id } },fallback: fallback)
    }
    private static func label(_ line: LaneLine,lookup: (String) -> Backup.Graphic?,fallback: String) -> String {
        if let id = line.graphicId {
            guard let g = lookup(id) else { return fallback+" (line deleted)" }
            return g.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? GraphicTypes.label(g.type) : g.name
        }
        let trimmed = line.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
    public static func limitsSummary(_ lane: NavLane,graphics: [Backup.Graphic]) -> String {
        summary(lane,lookup: { id in graphics.first { $0.id == id } })
    }
    private static func summary(_ lane: NavLane,lookup: (String) -> Backup.Graphic?) -> String {
        "L: \(label(lane.left,lookup: lookup,fallback: "left limit")) · R: \(label(lane.right,lookup: lookup,fallback: "right limit")) · BS: \(label(lane.backstop,lookup: lookup,fallback: "backstop"))"
    }
    public static func objective(_ lane:NavLane,graphics:[Backup.Graphic],waypoints:[Waypoint])->GeoPoint? {
        if lane.scope == .route {return graphics.first {$0.id == lane.targetId}?.points.last.map {.init(lat:$0.lat,lon:$0.lon)}}
        return waypoints.first {$0.id == lane.targetId}.map {.init(lat:$0.lat,lon:$0.lon)}
    }
    public static func resolve(_ lane: NavLane,graphics: [Backup.Graphic],waypoints:[Waypoint] = []) throws -> ResolvedLane {
        guard let l = points(lane.left,graphics: graphics) else { throw LaneShapeError("The left limit's line is missing") }
        guard let r = points(lane.right,graphics: graphics) else { throw LaneShapeError("The right limit's line is missing") }
        guard let b = points(lane.backstop,graphics: graphics) else { throw LaneShapeError("The backstop's line is missing") }
        return try .init(lane: lane,shape: LaneShape(leftDrawn: l,rightDrawn: r,backstopDrawn: b,objective:objective(lane,graphics:graphics,waypoints:waypoints)),left: l,right: r,backstop: b)
    }
    public static func normalized(_ lane: NavLane,graphics: [Backup.Graphic],waypoints:[Waypoint] = []) throws -> (lane: NavLane,swapped: Bool) {
        let resolved = try resolve(lane,graphics: graphics,waypoints:waypoints)
        var saved = lane
        if resolved.shape.leftWasDrawnAsRight { saved.left = lane.right; saved.right = lane.left }
        return (saved,resolved.shape.leftWasDrawnAsRight)
    }
    public static func legLimits(route: Backup.Graphic,lanes: [NavLane],waypoints: [Waypoint],graphics: [Backup.Graphic]) -> [String?] {
        guard route.points.count >= 2 else { return [] }
        var routeLane: NavLane?, checkpoints: [String:NavLane] = [:], endpoints: [Int:Waypoint] = [:]
        for lane in lanes {
            if lane.scope == .route && lane.targetId == route.id {
                if routeLane == nil || routeLane!.createdAt < lane.createdAt { routeLane = lane }
            } else if lane.scope == .checkpoint {
                if checkpoints[lane.targetId] == nil || checkpoints[lane.targetId]!.createdAt < lane.createdAt { checkpoints[lane.targetId] = lane }
            }
        }
        for point in waypoints where point.sourceRouteId == route.id {
            if let index = point.sourceRoutePointIndex,endpoints[index] == nil { endpoints[index] = point }
        }
        let byID = Dictionary(graphics.map { ($0.id,$0) },uniquingKeysWith: { first,_ in first })
        var summaries: [String:String] = [:]
        return (1..<route.points.count).map { end in
            let checkpoint = endpoints[end].flatMap { checkpoints[$0.id] }
            return (checkpoint ?? routeLane).map { lane in
                if let value = summaries[lane.id] { return value }
                let value = summary(lane,lookup: { byID[$0] }); summaries[lane.id] = value; return value
            }
        }
    }
}
