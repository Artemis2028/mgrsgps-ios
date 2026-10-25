import Foundation

/// Complete lane geometry for read-only watch maps. Limits are never thinned:
/// an oversized, invalid or dateline-crossing lane is omitted as one item.
public struct WatchLaneOverlay: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var left: [GeoPoint]
    public var right: [GeoPoint]
    public var backstop: [GeoPoint]
    public var outline: [GeoPoint]
    public var leftLabel: String
    public var rightLabel: String
    public var backstopLabel: String
    public var isValid: Bool {
        !id.isEmpty && id.utf16.count <= 64 && name.count <= 80
        && [leftLabel,rightLabel,backstopLabel].allSatisfy { $0.count <= 80 }
        && [left,right,backstop].allSatisfy { (2...160).contains($0.count) && $0.allSatisfy(WatchMapSnapshot.validCoordinate) && !WatchMapGeometry.crossesDateline($0,closed:false) }
        && (3...256).contains(outline.count) && outline.allSatisfy(WatchMapSnapshot.validCoordinate)
        && !WatchMapGeometry.crossesDateline(outline,closed: true)
    }
    public static func labelPoint(_ points: [GeoPoint]) -> GeoPoint {
        guard let first = points.first else { return .init(lat: 0,lon: 0) }
        let distances = zip(points,points.dropFirst()).map { Geodesy.greatCircleMeters($0.lat,$0.lon,$1.lat,$1.lon) }
        var remaining = distances.reduce(0,+)/2
        for i in distances.indices {
            if remaining <= distances[i] {
                let fraction = distances[i] > 0 ? remaining/distances[i] : 0, a = points[i], b = points[i+1]
                return .init(lat: a.lat+(b.lat-a.lat)*fraction,lon: a.lon+(b.lon-a.lon)*fraction)
            }
            remaining -= distances[i]
        }
        return first
    }
    public static func build(_ lane: NavLane,graphics: [Backup.Graphic]) -> Self? {
        guard let resolved = try? NavLanes.resolve(lane,graphics: graphics) else { return nil }
        let lines = resolved.shape.mapLines(), swapped = resolved.shape.leftWasDrawnAsRight
        let value = Self(id: lane.id,name: String(lane.name.prefix(80)),left: lines.left,right: lines.right,backstop: lines.backstop,outline: resolved.shape.outline(),
                         leftLabel: String(NavLanes.label(swapped ? lane.right : lane.left,graphics: graphics,fallback: "Left limit").prefix(80)),
                         rightLabel: String(NavLanes.label(swapped ? lane.left : lane.right,graphics: graphics,fallback: "Right limit").prefix(80)),
                         backstopLabel: String(NavLanes.label(lane.backstop,graphics: graphics,fallback: "Backstop").prefix(80)))
        return value.isValid ? value : nil
    }
}
