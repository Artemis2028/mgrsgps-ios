import Foundation

/// UTM and the MGRS lettering scheme.
///
/// A direct port of `Coordinates.kt` in the Android app — the same Snyder
/// series, term for term, so the two platforms cannot drift. Every function
/// here is pinned by `golden.json`, which both test suites read.
public enum UTM {

    // WGS84
    public static let a = 6378137.0
    public static let f = 1.0 / 298.257223563
    public static let k0 = 0.9996
    static let e2 = f * (2.0 - f)
    static let ep2 = e2 / (1.0 - e2)

    /// MGRS latitude bands, C at 80S through X at 84N. No I or O.
    public static let bands = Array("CDEFGHJKLMNPQRSTUVWX")
    /// 100 km column letters, 24 of them, no I or O.
    public static let columns = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    /// 100 km row letters, 20 of them, no I or O.
    public static let rows = Array("ABCDEFGHJKLMNPQRSTUV")

    public struct Coordinate: Equatable, Sendable {
        public let zone: Int
        public let hemisphere: Character
        public let easting: Int
        public let northing: Int
        public init(zone: Int, hemisphere: Character, easting: Int, northing: Int) {
            self.zone = zone
            self.hemisphere = hemisphere
            self.easting = easting
            self.northing = northing
        }
    }

    /// The UTM zone for a point, including the Norway and Svalbard exceptions.
    public static func zone(lat: Double, lon: Double) -> Int {
        var z = min(60, max(1, Int(floor((lon + 180.0) / 6.0)) + 1))
        if lat >= 56.0 && lat <= 64.0 && lon >= 3.0 && lon <= 12.0 { z = 32 }
        if lat >= 72.0 && lat <= 84.0 {
            if lon >= 0.0 && lon <= 9.0 { z = 31 }
            else if lon >= 9.0 && lon <= 21.0 { z = 33 }
            else if lon >= 21.0 && lon <= 33.0 { z = 35 }
            else if lon >= 33.0 && lon <= 42.0 { z = 37 }
        }
        return z
    }

    /// MGRS latitude band letter for a latitude in -80...84.
    public static func bandLetter(lat: Double) -> Character {
        let idx = min(19, max(0, Int(floor((lat + 80.0) / 8.0))))
        return bands[idx]
    }

    /// Central meridian of a zone, in degrees.
    public static func centralMeridian(zone: Int) -> Double {
        Double((zone - 1) * 6 - 180 + 3)
    }

    /// Easting/northing of a point projected in a SPECIFIC zone — what the grid
    /// overlay needs, because grid lines continue past the zone boundary.
    public static func forZone(lat: Double, lon: Double, zone: Int, north: Bool) -> (easting: Double, northing: Double) {
        let latRad = lat * .pi / 180.0
        let lonRad = lon * .pi / 180.0
        let lonOrigin = centralMeridian(zone: zone) * .pi / 180.0

        let n = a / (1.0 - e2 * pow(sin(latRad), 2)).squareRoot()
        let t = pow(tan(latRad), 2)
        let c = ep2 * pow(cos(latRad), 2)
        let bigA = cos(latRad) * (lonRad - lonOrigin)
        let m = a * (
            (1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0) * latRad
            - (3.0 * e2 / 8.0 + 3.0 * e2 * e2 / 32.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(2.0 * latRad)
            + (15.0 * e2 * e2 / 256.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(4.0 * latRad)
            - (35.0 * e2 * e2 * e2 / 3072.0) * sin(6.0 * latRad)
        )
        let easting = k0 * n * (
            bigA + (1.0 - t + c) * pow(bigA, 3) / 6.0
            + (5.0 - 18.0 * t + t * t + 72.0 * c - 58.0 * ep2) * pow(bigA, 5) / 120.0
        ) + 500000.0
        var northing = k0 * (
            m + n * tan(latRad) * (
                pow(bigA, 2) / 2.0
                + (5.0 - t + 9.0 * c + 4.0 * c * c) * pow(bigA, 4) / 24.0
                + (61.0 - 58.0 * t + t * t + 600.0 * c - 330.0 * ep2) * pow(bigA, 6) / 720.0
            )
        )
        if !north { northing += 10000000.0 }
        return (easting, northing)
    }

    /// Standard UTM for a point. Nil outside -80...84, where UTM is undefined.
    public static func coordinate(lat: Double, lon: Double) -> Coordinate? {
        guard lat >= -80.0, lat <= 84.0 else { return nil }
        let z = zone(lat: lat, lon: lon)
        let p = forZone(lat: lat, lon: lon, zone: z, north: lat >= 0)
        return Coordinate(
            zone: z,
            hemisphere: lat >= 0 ? "N" : "S",
            easting: Int(p.easting.rounded()),
            northing: Int(p.northing.rounded())
        )
    }

    /// Easting/northing back to lat/lon. The Snyder inverse series.
    public static func inverse(easting: Double, northing: Double, zone z: Int, north: Bool) -> (lat: Double, lon: Double) {
        let x = easting - 500000.0
        let y = north ? northing : northing - 10000000.0
        let m = y / k0
        let mu = m / (a * (1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0))
        let e1 = (1.0 - (1.0 - e2).squareRoot()) / (1.0 + (1.0 - e2).squareRoot())
        let phi1 = mu
            + (3.0 * e1 / 2.0 - 27.0 * e1 * e1 * e1 / 32.0) * sin(2.0 * mu)
            + (21.0 * e1 * e1 / 16.0 - 55.0 * pow(e1, 4) / 32.0) * sin(4.0 * mu)
            + (151.0 * e1 * e1 * e1 / 96.0) * sin(6.0 * mu)
            + (1097.0 * pow(e1, 4) / 512.0) * sin(8.0 * mu)
        let sin1 = sin(phi1), cos1 = cos(phi1), tan1 = tan(phi1)
        let c1 = ep2 * cos1 * cos1
        let t1 = tan1 * tan1
        let n1 = a / (1.0 - e2 * sin1 * sin1).squareRoot()
        let r1 = a * (1.0 - e2) / pow(1.0 - e2 * sin1 * sin1, 1.5)
        let d = x / (n1 * k0)
        let lat = phi1 - (n1 * tan1 / r1) * (
            d * d / 2.0
            - (5.0 + 3.0 * t1 + 10.0 * c1 - 4.0 * c1 * c1 - 9.0 * ep2) * pow(d, 4) / 24.0
            + (61.0 + 90.0 * t1 + 298.0 * c1 + 45.0 * t1 * t1 - 252.0 * ep2 - 3.0 * c1 * c1) * pow(d, 6) / 720.0
        )
        let lonOrigin = centralMeridian(zone: z) * .pi / 180.0
        let lon = lonOrigin + (
            d
            - (1.0 + 2.0 * t1 + c1) * pow(d, 3) / 6.0
            + (5.0 - 2.0 * c1 + 28.0 * t1 - 3.0 * c1 * c1 + 8.0 * ep2 + 24.0 * t1 * t1) * pow(d, 5) / 120.0
        ) / cos1
        return (lat * 180.0 / .pi, lon * 180.0 / .pi)
    }

    /// Grid north minus true north, in degrees, for this point's own zone.
    public static func gridConvergence(lat: Double, lon: Double) -> Double {
        gridConvergence(lat: lat, lon: lon, zone: zone(lat: lat, lon: lon))
    }

    public static func gridConvergence(lat: Double, lon: Double, zone z: Int) -> Double {
        let lonOrigin = centralMeridian(zone: z)
        return atan(tan((lon - lonOrigin) * .pi / 180.0) * sin(lat * .pi / 180.0)) * 180.0 / .pi
    }

    /// The two 100 km square letters for an easting/northing in a zone.
    public static func squareLetters(zone z: Int, easting: Double, northing: Double) -> String {
        let col = Int(easting / 100000.0)                 // 1...8
        let ci = ((z - 1) % 3) * 8 + (col - 1)
        let ri = (Int(northing / 100000.0) + (z % 2 == 0 ? 5 : 0)) % 20
        guard ci >= 0, ci < columns.count, ri >= 0, ri < rows.count else { return "" }
        return String([columns[ci], rows[ri]])
    }
}
