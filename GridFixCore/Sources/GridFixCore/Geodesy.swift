import Foundation

/// Distance and bearing on the WGS84 ellipsoid.
///
/// Vincenty's inverse formula — the same algorithm Android's
/// `Location.distanceBetween` runs, so Android and iOS report the same numbers
/// for the same leg. A great-circle (haversine) shortcut would be 0.3 to 0.5%
/// off, which is metres on a route card and shows up as a distance that
/// disagrees between the two phones in the same patrol.
///
/// Pinned by the `distance` vectors in `golden.json`, which match the published
/// Geoscience Australia test line to better than a millimetre.
public enum Geodesy {

    static let a = 6378137.0
    static let f = 1.0 / 298.257223563
    static let b = a * (1.0 - f)

    public struct NavInfo: Equatable, Sendable {
        /// Geodesic distance in metres.
        public let distanceMeters: Double
        /// Initial bearing from true north, 0..<360.
        public let bearingTrue: Double
        public init(distanceMeters: Double, bearingTrue: Double) {
            self.distanceMeters = distanceMeters
            self.bearingTrue = bearingTrue
        }
    }

    /// Geodesic distance and initial true bearing between two points.
    public static func navInfo(fromLat: Double, fromLon: Double,
                               toLat: Double, toLon: Double) -> NavInfo {
        if fromLat == toLat && fromLon == toLon {
            return NavInfo(distanceMeters: 0.0, bearingTrue: 0.0)
        }
        let L = (toLon - fromLon) * .pi / 180.0
        let U1 = atan((1.0 - f) * tan(fromLat * .pi / 180.0))
        let U2 = atan((1.0 - f) * tan(toLat * .pi / 180.0))
        let sinU1 = sin(U1), cosU1 = cos(U1)
        let sinU2 = sin(U2), cosU2 = cos(U2)

        var lambda = L
        var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0
        var cosSqAlpha = 0.0, cos2SigmaM = 0.0
        var converged = false

        for _ in 0..<200 {
            let sinLambda = sin(lambda), cosLambda = cos(lambda)
            sinSigma = ((cosU2 * sinLambda) * (cosU2 * sinLambda)
                + (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
                * (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)).squareRoot()
            if sinSigma == 0.0 {
                return NavInfo(distanceMeters: 0.0, bearingTrue: 0.0)
            }
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cosSqAlpha = 1.0 - sinAlpha * sinAlpha
            cos2SigmaM = cosSqAlpha == 0.0 ? 0.0
                : cosSigma - 2.0 * sinU1 * sinU2 / cosSqAlpha
            let C = f / 16.0 * cosSqAlpha * (4.0 + f * (4.0 - 3.0 * cosSqAlpha))
            let previous = lambda
            lambda = L + (1.0 - C) * f * sinAlpha
                * (sigma + C * sinSigma
                   * (cos2SigmaM + C * cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)))
            if abs(lambda - previous) < 1e-12 { converged = true; break }
        }

        if !converged {
            // Near-antipodal only; land navigation never gets here. Falling back
            // to the great circle keeps a bearing on screen instead of NaN.
            return NavInfo(distanceMeters: greatCircleMeters(fromLat, fromLon, toLat, toLon),
                           bearingTrue: greatCircleBearing(fromLat, fromLon, toLat, toLon))
        }

        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let A = 1.0 + uSq / 16384.0 * (4096.0 + uSq * (-768.0 + uSq * (320.0 - 175.0 * uSq)))
        let B = uSq / 1024.0 * (256.0 + uSq * (-128.0 + uSq * (74.0 - 47.0 * uSq)))
        let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4.0 * (
            cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)
            - B / 6.0 * cos2SigmaM * (-3.0 + 4.0 * sinSigma * sinSigma)
            * (-3.0 + 4.0 * cos2SigmaM * cos2SigmaM)))
        let s = b * A * (sigma - deltaSigma)

        let sinLambda = sin(lambda), cosLambda = cos(lambda)
        let alpha1 = atan2(cosU2 * sinLambda, cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
        let bearing = (alpha1 * 180.0 / .pi).truncatingRemainder(dividingBy: 360.0)
        return NavInfo(distanceMeters: s, bearingTrue: (bearing + 360.0).truncatingRemainder(dividingBy: 360.0))
    }

    /// Great-circle distance. Only for the non-convergent fallback and for
    /// cheap proximity sorting where half a percent does not matter.
    public static func greatCircleMeters(_ lat1: Double, _ lon1: Double,
                                         _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371008.8
        let p1 = lat1 * .pi / 180.0, p2 = lat2 * .pi / 180.0
        let dp = p2 - p1
        let dl = (lon2 - lon1) * .pi / 180.0
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2.0 * r * atan2(h.squareRoot(), max(0.0, 1.0 - h).squareRoot())
    }

    static func greatCircleBearing(_ lat1: Double, _ lon1: Double,
                                   _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180.0, p2 = lat2 * .pi / 180.0
        let dl = (lon2 - lon1) * .pi / 180.0
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return ((atan2(y, x) * 180.0 / .pi) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    // MARK: - Resection

    /// A two-ray fix: where the rays cross, and the range along each.
    public struct RayFix: Equatable, Sendable {
        public let lat: Double
        public let lon: Double
        public let dist1: Double
        public let dist2: Double
    }

    /// Intersection of two rays given as TRUE bearings, solved in the UTM plane
    /// of the first point's zone. Nil when the rays are near-parallel, diverge,
    /// or the fix lands beyond 100 km — the cases an instructor would also
    /// reject rather than plot.
    public static func rayIntersection(lat1: Double, lon1: Double, bearing1True: Double,
                                       lat2: Double, lon2: Double, bearing2True: Double) -> RayFix? {
        let zone = UTM.zone(lat: lat1, lon: lon1)
        let north = lat1 >= 0
        let p1 = UTM.forZone(lat: lat1, lon: lon1, zone: zone, north: north)
        let p2 = UTM.forZone(lat: lat2, lon: lon2, zone: zone, north: north)
        let g1 = (bearing1True - UTM.gridConvergence(lat: lat1, lon: lon1, zone: zone)) * .pi / 180.0
        let g2 = (bearing2True - UTM.gridConvergence(lat: lat2, lon: lon2, zone: zone)) * .pi / 180.0
        let d1x = sin(g1), d1y = cos(g1)
        let d2x = sin(g2), d2y = cos(g2)
        let cross = d1x * d2y - d1y * d2x
        if abs(cross) < 1e-6 { return nil }
        let dx = p2.easting - p1.easting
        let dy = p2.northing - p1.northing
        let t = (dx * d2y - dy * d2x) / cross
        let s = (dx * d1y - dy * d1x) / cross
        if t <= 0.0 || s <= 0.0 || t > 100000.0 || s > 100000.0 { return nil }
        let ll = UTM.inverse(easting: p1.easting + t * d1x,
                             northing: p1.northing + t * d1y,
                             zone: zone, north: north)
        return RayFix(lat: ll.lat, lon: ll.lon, dist1: t, dist2: s)
    }
}
