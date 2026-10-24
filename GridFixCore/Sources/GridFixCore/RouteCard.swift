import Foundation

public enum RouteCard {
    public struct Leg: Equatable, Sendable {
        public let index: Int
        public let forward: Double?
        public let reverse: Double?
        public let distanceMeters: Double
        public let paces: Int
        public let destinationGrid: String
    }

    /// Forward corrections are evaluated at the start; reverse corrections at
    /// the end. A reciprocal bearing is not generally forward + 180 degrees.
    public static func legs(points: [GeoPoint], northReference: Int, pacePer100m: Int,
                            declination: (GeoPoint) -> Double?) -> [Leg] {
        zip(points, points.dropFirst()).enumerated().map { index, pair in
            let fwd = Geodesy.navInfo(fromLat: pair.0.lat, fromLon: pair.0.lon, toLat: pair.1.lat, toLon: pair.1.lon)
            let rev = Geodesy.navInfo(fromLat: pair.1.lat, fromLon: pair.1.lon, toLat: pair.0.lat, toLon: pair.0.lon)
            func corrected(_ bearing: Double, at point: GeoPoint) -> Double? {
                let correction: Double
                switch northReference {
                case 1: guard let d = declination(point) else { return nil }; correction = d
                case 2: guard (-80...84).contains(point.lat) else { return nil }; correction = UTM.gridConvergence(lat: point.lat, lon: point.lon)
                default: correction = 0
                }
                return (bearing - correction + 720).truncatingRemainder(dividingBy: 360)
            }
            return Leg(index: index + 1, forward: corrected(fwd.bearingTrue, at: pair.0),
                       reverse: corrected(rev.bearingTrue, at: pair.1), distanceMeters: fwd.distanceMeters,
                       paces: Int((fwd.distanceMeters / 100 * Double(pacePer100m)).rounded()),
                       destinationGrid: MGRS.parts(lat: pair.1.lat, lon: pair.1.lon, digits: 8)?.full ?? "—")
        }
    }
}
