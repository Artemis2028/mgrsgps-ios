import Foundation

public struct BoundaryArea: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var vertices: [GeoPoint]
    public init(id: String = UUID().uuidString, name: String, vertices: [GeoPoint]) {
        self.id = id; self.name = name; self.vertices = vertices
    }
}

/// Edges are straight in Web Mercator, matching the map renderer. Distances
/// use the fix's local ground scale; boundaries are limited to local field areas.
public struct BoundaryGeometry: Sendable {
    private struct XY: Sendable { var x: Double, y: Double }
    private let origin: GeoPoint
    private let points: [XY]
    private static let radius = 6_378_137.0
    public init(vertices: [GeoPoint]) throws {
        guard (3...256).contains(vertices.count), vertices.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 80 && abs($0.lon) <= 180 }) else {
            throw BoundaryError.invalid("Use 3–256 points between 80°S and 80°N.")
        }
        origin = vertices[0]
        points = vertices.map { Self.project($0, origin: vertices[0]) }
        let scale = cos(origin.lat * .pi / 180)
        guard points.allSatisfy({ hypot($0.x,$0.y) * scale <= 100_000 }) else { throw BoundaryError.invalid("Keep the boundary within 100 km of its first point.") }
        var area = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            guard hypot(b.x-a.x,b.y-a.y) * scale >= 1 else { throw BoundaryError.invalid("Separate neighbouring points by at least one metre.") }
            area += a.x*b.y - b.x*a.y
            for j in points.indices where j > i + 1 && !(i == 0 && j == points.count - 1) {
                if Self.intersects(a,b,points[j],points[(j+1) % points.count]) { throw BoundaryError.invalid("Boundary lines must not cross or touch each other.") }
            }
            // Reject an adjacent edge that doubles back over its neighbour.
            let c = points[(i+2) % points.count]
            if abs(Self.cross(a,b,c)) < 1e-6 && (a.x-b.x)*(c.x-b.x)+(a.y-b.y)*(c.y-b.y) > 0 {
                throw BoundaryError.invalid("A boundary line cannot double back over itself.")
            }
        }
        guard abs(area) * scale * scale / 2 >= 25 else { throw BoundaryError.invalid("Draw an area of at least 25 square metres.") }
    }
    private static func project(_ p: GeoPoint, origin: GeoPoint) -> XY {
        let d = ((p.lon - origin.lon + 540).truncatingRemainder(dividingBy: 360)) - 180
        func y(_ lat: Double) -> Double { log(tan(.pi/4 + lat * .pi/360)) * radius }
        return XY(x: d * .pi/180 * radius, y: y(p.lat)-y(origin.lat))
    }
    private static func cross(_ a: XY, _ b: XY, _ c: XY) -> Double { (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) }
    private static func intersects(_ a: XY, _ b: XY, _ c: XY, _ d: XY) -> Bool {
        func contains(_ a: XY, _ b: XY, _ p: XY) -> Bool {
            abs(cross(a,b,p)) <= 1e-6 && p.x >= min(a.x,b.x)-1e-7 && p.x <= max(a.x,b.x)+1e-7 && p.y >= min(a.y,b.y)-1e-7 && p.y <= max(a.y,b.y)+1e-7
        }
        let abC = cross(a,b,c), abD = cross(a,b,d), cdA = cross(c,d,a), cdB = cross(c,d,b)
        return (abC * abD < 0 && cdA * cdB < 0) || contains(a,b,c) || contains(a,b,d) || contains(c,d,a) || contains(c,d,b)
    }
    /// Positive inside, negative outside, zero on the perimeter. Nil is unknown.
    public func signedDistance(to point: GeoPoint) -> Double? {
        guard point.lat.isFinite, point.lon.isFinite, abs(point.lat) <= 80, abs(point.lon) <= 180 else { return nil }
        let p = Self.project(point,origin: origin)
        var inside = false, nearest = Double.infinity
        for i in points.indices {
            let a = points[i], b = points[(i+1) % points.count]
            let dx = b.x-a.x, dy = b.y-a.y
            let t = min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/(dx*dx+dy*dy)))
            nearest = min(nearest,hypot(p.x-a.x-t*dx,p.y-a.y-t*dy))
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
        }
        let distance = nearest * cos(point.lat * .pi/180)
        return inside ? distance : -distance
    }
}

public enum BoundaryError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
}

/// No heading input and no cadence/heartbeat. A fresh, accurate uncertainty
/// circle must lie on one side for two seconds before a transition is confirmed.
public struct BoundaryCrossingDetector: Sendable {
    public enum Side: String, Sendable { case inside, outside }
    public enum Result: Equatable, Sendable { case unknown, edge, confirming(Side), inside, outside, exited }
    private let geometry: BoundaryGeometry
    public private(set) var stableSide: Side?
    private var candidate: Side?
    private var since: TimeInterval?
    private var lastTime: TimeInterval?
    public init(vertices: [GeoPoint]) throws { geometry = try BoundaryGeometry(vertices: vertices) }
    public mutating func update(point: GeoPoint, accuracy: Double, timestamp: TimeInterval, now: TimeInterval) -> Result {
        guard timestamp.isFinite, now.isFinite, now-timestamp >= -1, now-timestamp <= 10,
              accuracy.isFinite, (0...25).contains(accuracy), lastTime.map({ timestamp > $0 }) ?? true,
              let distance = geometry.signedDistance(to: point) else {
            candidate = nil; since = nil; return .unknown
        }
        if let lastTime, timestamp-lastTime > 10 { candidate = nil; since = nil }
        lastTime = timestamp
        guard abs(distance) > max(3,accuracy) else { candidate = nil; since = nil; return .edge }
        let side: Side = distance > 0 ? .inside : .outside
        if stableSide == side { candidate = nil; since = nil; return side == .inside ? .inside : .outside }
        if candidate != side { candidate = side; since = timestamp; return .confirming(side) }
        guard let since, timestamp-since >= 2 else { return .confirming(side) }
        let previous = stableSide
        stableSide = side; candidate = nil; self.since = nil
        if side == .outside && previous == .inside { return .exited }
        return side == .inside ? .inside : .outside
    }
}
