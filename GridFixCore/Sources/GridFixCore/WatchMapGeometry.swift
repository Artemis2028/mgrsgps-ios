import Foundation

/// Local Web Mercator geometry, matching the phone tactical canvas and boundary geometry.
public enum WatchMapGeometry {
    public static func crossesDateline(_ points: [GeoPoint], closed: Bool) -> Bool {
        guard let first = points.first, let last = points.last else { return false }
        return zip(points, points.dropFirst()).contains { abs($0.lon - $1.lon) > 180 }
            || (closed && abs(first.lon - last.lon) > 180)
    }

    /// Clockwise sector from first ray to second ray, at the larger projected radius.
    /// Reject unsupported polar/dateline sectors rather than draw a world-spanning polygon.
    public static func sectorOutline(_ points: [GeoPoint]) -> [GeoPoint]? {
        guard points.count >= 3, points.prefix(3).allSatisfy(WatchMapSnapshot.validCoordinate) else { return nil }
        let origin = points[0], radius = 6_378_137.0, rad = Double.pi / 180
        func northing(_ lat: Double) -> Double { radius * log(tan(Double.pi / 4 + lat * rad / 2)) }
        let y0 = northing(origin.lat)
        func vector(_ p: GeoPoint) -> (x: Double, y: Double) {
            (TerrainGeometry.wrap(p.lon - origin.lon) * rad * radius, northing(p.lat) - y0)
        }
        let a = vector(points[1]), b = vector(points[2]), r = max(hypot(a.x, a.y), hypot(b.x, b.y))
        guard r.isFinite, r > 0 else { return nil }
        let start = atan2(a.x, a.y), end = atan2(b.x, b.y)
        var sweep = end - start
        while sweep <= 0 { sweep += 2 * .pi }
        var outline = [origin]
        for i in 0...32 {
            let angle = start + sweep * Double(i) / 32
            let x = r * sin(angle), y = r * cos(angle)
            outline.append(.init(lat: (2 * atan(exp((y0 + y) / radius)) - .pi / 2) / rad,
                                 lon: TerrainGeometry.wrap(origin.lon + x / radius / rad)))
        }
        guard outline.allSatisfy(WatchMapSnapshot.validCoordinate), !crossesDateline(outline, closed: true) else { return nil }
        return outline
    }
}
