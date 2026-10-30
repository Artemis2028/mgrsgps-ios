import Foundation

/// Android map/Lasso.kt: a screen-space loop, closed implicitly. A graphic is
/// selected by its stored vertices, not by its bounding box or crossing edges.
public enum MapLasso {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double,y: Double) { self.x = x; self.y = y }
    }
    public static func contains(_ point: Point,in loop: [Point]) -> Bool {
        Shape(loop).contains(point)
    }
    private struct Shape {
        let points: [Point]
        let minX: Double, maxX: Double, minY: Double, maxY: Double
        init(_ loop: [Point]) {
            points = loop.count >= 3 && loop.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) ? loop : []
            minX = points.map(\.x).min() ?? 0; maxX = points.map(\.x).max() ?? 0
            minY = points.map(\.y).min() ?? 0; maxY = points.map(\.y).max() ?? 0
        }
        func contains(_ point: Point) -> Bool {
            guard !points.isEmpty,point.x.isFinite,point.y.isFinite,
                  point.x >= minX,point.x <= maxX,point.y >= minY,point.y <= maxY else { return false }
            var inside = false, j = points.count-1
            for i in points.indices {
                let a = points[i], b = points[j]
                if (a.y > point.y) != (b.y > point.y),
                   point.x < (b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
                j = i
            }
            return inside
        }
    }
    public static func select(loop: [Point],waypoints: [Waypoint],graphics: [Backup.Graphic],folders: [FolderInfo],
                              project: (GeoPoint) -> Point) -> LibrarySelection {
        let hidden = Set(folders.filter { !$0.visible }.map { $0.name.lowercased() })
        let shape = Shape(loop)
        var result = LibrarySelection()
        for point in waypoints where point.visible && !point.id.hasPrefix("tak:") && !hidden.contains(point.folder.lowercased()) {
            if shape.contains(project(.init(lat: point.lat,lon: point.lon))) { result.waypoints.insert(point.id) }
        }
        for graphic in graphics where graphic.visible && !hidden.contains(graphic.folder.lowercased()) {
            if graphic.points.contains(where: { shape.contains(project(.init(lat: $0.lat,lon: $0.lon))) }) { result.graphics.insert(graphic.id) }
        }
        return result
    }
}
