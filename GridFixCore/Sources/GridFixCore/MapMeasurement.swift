import Foundation

/// Android MapScreen ruler and RouteGeometry.routePolygonMetrics policies.
public enum MapMeasurement {
    public struct Polygon: Equatable, Sendable {
        public let perimeter: Double
        public let area: Double
        public let zone: Int
        public let extrapolated: Bool
    }
    public static func polygon(_ points: [GeoPoint]) -> Polygon? {
        guard points.count >= 3, points.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 85.05112878 && abs($0.lon) <= 180 }) else { return nil }
        let first = points[0], zone = UTM.zone(lat: first.lat,lon: first.lon)
        let projected = points.map { UTM.forZone(lat: $0.lat,lon: $0.lon,zone: zone,north: first.lat >= 0) }
        let origin = projected[0]
        var perimeter = 0.0, twiceArea = 0.0
        for i in projected.indices {
            let a = projected[i], b = projected[(i+1)%projected.count]
            perimeter += hypot(b.easting-a.easting,b.northing-a.northing)
            twiceArea += (a.easting-origin.easting)*(b.northing-origin.northing)-(b.easting-origin.easting)*(a.northing-origin.northing)
        }
        guard perimeter.isFinite, twiceArea.isFinite else { return nil }
        return Polygon(perimeter: perimeter,area: abs(twiceArea)/2,zone: zone,extrapolated: points.contains { !(-80...84).contains($0.lat) })
    }
    public struct Ruler: Equatable, Sendable {
        public let distance: Double
        public let azimuth: Double?
        /// Android ruler's reciprocal azimuth, distinct from reverse geodesic bearings on route cards.
        public let backAzimuth: Double?
    }
    public static func ruler(from: GeoPoint,to: GeoPoint,northReference: Int,declination: Double?) -> Ruler {
        let leg = Geodesy.navInfo(fromLat: from.lat,fromLon: from.lon,toLat: to.lat,toLon: to.lon)
        let correction: Double?
        switch northReference {
        case 1: correction = declination
        case 2: correction = UTM.gridConvergence(lat: to.lat,lon: to.lon)
        default: correction = 0
        }
        let azimuth = correction.flatMap { value -> Double? in
            guard value.isFinite else { return nil }
            return ((leg.bearingTrue-value).truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)
        }
        return Ruler(distance: leg.distanceMeters,azimuth: azimuth,backAzimuth: azimuth.map { ($0+180).truncatingRemainder(dividingBy: 360) })
    }
    public static func areaLabel(_ squareMetres: Double) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        if squareMetres < 10_000 { return String(format: "%.0f m²",locale: locale,squareMetres) }
        if squareMetres < 1_000_000 { return String(format: "%.1f ha",locale: locale,squareMetres/10_000) }
        return String(format: "%.2f km²",locale: locale,squareMetres/1_000_000)
    }
}
