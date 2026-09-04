import Foundation

/// The World Magnetic Model — magnetic declination anywhere, any date.
///
/// Android gets this free from `android.hardware.GeomagneticField`. iOS has no
/// equivalent, so the model has to be carried in the app. `CLHeading` does
/// offer `trueHeading - magneticHeading`, which IS the declination and is
/// worth using when it is available, but only for *here, now, with the compass
/// running*. Every other case the app needs it for — the G-M angle for a map
/// sheet, a bearing to a waypoint two valleys over, a route card computed at
/// the FOB for ground you have not reached — has no heading to subtract.
///
/// ## Status
///
/// The spherical-harmonic engine below is validated: its Schmidt
/// semi-normalised Legendre recursion was checked against SciPy for every
/// degree and order to 12 and colatitudes from 0.5° to 179.5°, agreeing to
/// 8e-15 in value and 9e-13 in derivative.
///
/// The **coefficients are not in this repository** and must not be guessed.
/// Drop NOAA's `WMM.COF` into `Sources/GridFixCore/Resources/` and the model
/// loads; until then `WMM.bundled` is nil and callers fall back to the
/// heading-derived declination. See `docs/wmm-plan.md`.
public struct WMM {

    /// WMM's geomagnetic reference radius. This is NOT the WGS84 semi-major
    /// axis — using 6378137 here is a classic and silent 1 km error.
    static let earthRadius = 6371200.0
    static let a = 6378137.0
    static let f = 1.0 / 298.257223563
    static let maxDegree = 12

    public let epoch: Double
    public let name: String
    public let releaseDate: String
    /// Gauss coefficients and their secular variation, in nanotesla.
    let g: [[Double]], h: [[Double]], gDot: [[Double]], hDot: [[Double]]

    /// The model is only valid for five years from its epoch. Past that the
    /// declination it returns is an extrapolation that drifts, and a
    /// navigation app that keeps quoting one is worse than one that admits it.
    public var validUntil: Double { epoch + 5.0 }

    public func isValid(at decimalYear: Double) -> Bool {
        decimalYear >= epoch && decimalYear < validUntil
    }

    /// The full field at a point.
    public struct Field: Equatable, Sendable {
        /// East-positive declination in degrees — the number the app calls
        /// "declination" and the map sheet calls the G-M angle's magnetic half.
        public let declination: Double
        /// Dip angle, positive down.
        public let inclination: Double
        /// Horizontal intensity, nanotesla.
        public let horizontalIntensity: Double
        /// Total intensity, nanotesla.
        public let totalIntensity: Double
        /// North, east and down components, nanotesla.
        public let x: Double, y: Double, z: Double
    }

    /// - Parameters:
    ///   - heightMeters: height above the WGS84 **ellipsoid**, not above sea
    ///     level. The difference is tens of metres and changes nothing at the
    ///     precision declination is used to, so passing MSL is acceptable.
    ///   - decimalYear: e.g. 2026.673. Use ``decimalYear(from:)``.
    public func field(lat: Double, lon: Double,
                      heightMeters: Double = 0.0,
                      decimalYear: Double) -> Field {
        let dt = decimalYear - epoch

        // Geodetic to geocentric.
        let e2 = Self.f * (2.0 - Self.f)
        let latRad = lat * .pi / 180.0
        let lonRad = lon * .pi / 180.0
        let sinLat = sin(latRad), cosLat = cos(latRad)
        let rc = Self.a / (1.0 - e2 * sinLat * sinLat).squareRoot()
        let p = (rc + heightMeters) * cosLat
        let z = (rc * (1.0 - e2) + heightMeters) * sinLat
        let r = (p * p + z * z).squareRoot()
        var geocentricLat = asin(z / r)

        // The Y component divides by sin(colatitude), which is singular at the
        // poles. The official implementation clamps to 89.992°; UTM stops at
        // 84° N anyway, so nothing the app draws is affected.
        let limit = 89.992 * .pi / 180.0
        geocentricLat = min(max(geocentricLat, -limit), limit)
        let theta = .pi / 2.0 - geocentricLat
        let sinTheta = sin(theta), cosTheta = cos(theta)

        let (pbar, dpbar) = Self.legendre(cosTheta: cosTheta, sinTheta: sinTheta)

        // Precompute the longitude harmonics once.
        var cosML = [Double](repeating: 0, count: Self.maxDegree + 1)
        var sinML = [Double](repeating: 0, count: Self.maxDegree + 1)
        for m in 0...Self.maxDegree {
            cosML[m] = cos(Double(m) * lonRad)
            sinML[m] = sin(Double(m) * lonRad)
        }

        var xp = 0.0, yp = 0.0, zp = 0.0
        let ratio = Self.earthRadius / r
        var power = ratio * ratio                     // (a/r)^2, stepped to n+2
        for n in 1...Self.maxDegree {
            power *= ratio                            // now (a/r)^(n+2)
            var sx = 0.0, sy = 0.0, sz = 0.0
            for m in 0...n {
                let gnm = g[n][m] + dt * gDot[n][m]
                let hnm = h[n][m] + dt * hDot[n][m]
                let c = gnm * cosML[m] + hnm * sinML[m]
                sx += c * dpbar[n][m]
                sy += Double(m) * (gnm * sinML[m] - hnm * cosML[m]) * pbar[n][m]
                sz += c * pbar[n][m]
            }
            // X = -B_theta = +sum, Z = -B_r = -(n+1) sum. Getting the X sign
            // wrong is invisible in the dip angle (which only reads Z) and
            // shows up as declination 180° off everywhere — so the axial
            // dipole test below is the one that catches it.
            xp += power * sx
            yp += power * sy
            zp -= power * Double(n + 1) * sz
        }
        yp /= sinTheta

        // Geocentric back to geodetic. The rotation is by (geocentric minus
        // geodetic), and getting the sign backwards is worse than omitting it:
        // no rotation is out by one delta, the wrong sign by two. It is also
        // invisible to a dipole test of declination, because the rotation only
        // ever mixes X and Z and leaves Y alone — which is exactly how it
        // survived until NOAA's own test values arrived.
        let delta = geocentricLat - latRad
        let x = xp * cos(delta) - zp * sin(delta)
        let zz = xp * sin(delta) + zp * cos(delta)
        let y = yp

        let horizontal = (x * x + y * y).squareRoot()
        return Field(
            declination: atan2(y, x) * 180.0 / .pi,
            inclination: atan2(zz, horizontal) * 180.0 / .pi,
            horizontalIntensity: horizontal,
            totalIntensity: (horizontal * horizontal + zz * zz).squareRoot(),
            x: x, y: y, z: zz
        )
    }

    /// East-positive magnetic declination in degrees — the one number most of
    /// the app wants.
    public func declination(lat: Double, lon: Double,
                            heightMeters: Double = 0.0,
                            decimalYear: Double) -> Double {
        field(lat: lat, lon: lon, heightMeters: heightMeters,
              decimalYear: decimalYear).declination
    }

    // MARK: - Legendre

    /// Schmidt semi-normalised associated Legendre functions and their
    /// derivatives with respect to colatitude.
    ///
    /// Verified against SciPy for every n, m up to 12 across colatitudes 0.5°
    /// to 179.5°: 8e-15 worst error in value, 9e-13 in derivative.
    static func legendre(cosTheta x: Double, sinTheta s: Double)
        -> (p: [[Double]], dp: [[Double]]) {
        let n = maxDegree
        var p = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n + 1)
        var dp = p
        p[0][0] = 1.0
        for i in 1...n {
            // Sectoral term. The normalisation factor is 1 at degree 1 and
            // sqrt((2i-1)/2i) above it; using the general form at i = 1 is a
            // factor of sqrt(2) wrong and every coefficient inherits it.
            let k = i == 1 ? 1.0 : ((Double(2 * i - 1)) / Double(2 * i)).squareRoot()
            p[i][i] = k * (s * p[i - 1][i - 1])
            dp[i][i] = k * (s * dp[i - 1][i - 1] + x * p[i - 1][i - 1])
            for m in 0..<i {
                let denom = Double(i * i - m * m).squareRoot()
                let hasTwoBack = (i - 2) >= m
                let b = hasTwoBack ? Double((i - 1) * (i - 1) - m * m).squareRoot() : 0.0
                let p2 = hasTwoBack ? p[i - 2][m] : 0.0
                let dp2 = hasTwoBack ? dp[i - 2][m] : 0.0
                p[i][m] = (Double(2 * i - 1) * x * p[i - 1][m] - b * p2) / denom
                dp[i][m] = (Double(2 * i - 1) * (x * dp[i - 1][m] - s * p[i - 1][m])
                            - b * dp2) / denom
            }
        }
        return (p, dp)
    }

    // MARK: - Loading

    public enum LoadError: Error, CustomStringConvertible {
        case notBundled
        case malformedHeader(String)
        case malformedRow(String)
        case incomplete(missing: Int)

        public var description: String {
            switch self {
            case .notBundled:
                return "WMM.COF is not in the bundle — see docs/wmm-plan.md"
            case .malformedHeader(let l): return "bad WMM header: \(l)"
            case .malformedRow(let l): return "bad WMM row: \(l)"
            case .incomplete(let n): return "WMM is missing \(n) coefficients"
            }
        }
    }

    /// Parse NOAA's `WMM.COF`: a header line of `<epoch> <name> <released>`,
    /// then rows of `n m g h gDot hDot`, terminated by lines of nines.
    public static func parse(cof text: String) throws -> WMM {
        var g = [[Double]](repeating: [Double](repeating: 0, count: maxDegree + 1),
                           count: maxDegree + 1)
        var h = g, gDot = g, hDot = g
        var epoch: Double?
        var name = "", released = ""
        var seen = 0

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("999999") || line.hasPrefix("9999999") { break }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if epoch == nil {
                guard let e = Double(parts.first ?? "") else {
                    throw LoadError.malformedHeader(line)
                }
                epoch = e
                name = parts.count > 1 ? parts[1] : "WMM"
                released = parts.count > 2 ? parts[2] : ""
                continue
            }
            guard parts.count >= 6,
                  let n = Int(parts[0]), let m = Int(parts[1]),
                  let gv = Double(parts[2]), let hv = Double(parts[3]),
                  let gd = Double(parts[4]), let hd = Double(parts[5]),
                  n >= 1, n <= maxDegree, m >= 0, m <= n
            else { throw LoadError.malformedRow(line) }
            g[n][m] = gv; h[n][m] = hv; gDot[n][m] = gd; hDot[n][m] = hd
            seen += 1
        }

        guard let epoch else { throw LoadError.malformedHeader("no header line") }
        // Degree 12 means 1+2+...+13 = 90 (n, m) pairs.
        let expected = (1...maxDegree).reduce(0) { $0 + $1 + 1 }
        if seen != expected { throw LoadError.incomplete(missing: expected - seen) }
        return WMM(epoch: epoch, name: name, releaseDate: released,
                   g: g, h: h, gDot: gDot, hDot: hDot)
    }

    /// The model shipped in the package, or nil when `WMM.COF` has not been
    /// added yet. Callers must handle nil rather than assume a declination.
    public static let bundled: WMM? = {
        guard let url = Bundle.module.url(forResource: "WMM", withExtension: "COF"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return try? parse(cof: text)
    }()

    /// Decimal year, the form the model wants: 2026.673.
    public static func decimalYear(from date: Date,
                                   calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let year = cal.component(.year, from: date)
        guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let next = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return Double(year) }
        let span = next.timeIntervalSince(start)
        return Double(year) + date.timeIntervalSince(start) / span
    }
}
