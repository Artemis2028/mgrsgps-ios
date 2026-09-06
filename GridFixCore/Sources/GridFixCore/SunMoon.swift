import Foundation

/// Offline sun and moon planning data: BMNT/EENT (nautical twilight), civil
/// twilight, sunrise/sunset (NOAA solar equations — validated to the minute),
/// moon phase + illumination (validated < 0.1° against eclipse epochs), and
/// approximate moonrise/set (truncated Meeus series, about ±5 minutes).
///
/// Ported from Android `coords/SunMoon.kt` at 0.9.32.
public enum SunMoon {

    private static let d2r = Double.pi / 180.0
    private static let r2d = 180.0 / Double.pi

    public struct SunTimes: Equatable, Sendable {
        /// UT hours; nil when the sun never crosses that altitude.
        public let bmnt: Double?
        public let civilDawn: Double?
        public let sunrise: Double?
        public let sunset: Double?
        public let civilDusk: Double?
        public let eent: Double?
    }

    public struct MoonInfo: Equatable, Sendable {
        public let phaseName: String
        public let illuminationPct: Int
        /// UT hours within the requested local calendar day.
        public let rises: [Double]
        public let sets: [Double]
    }

    public static func julianDay(y0: Int, m0: Int, d: Int, hourUtc: Double) -> Double {
        var y = y0
        var m = m0
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = y / 100
        let b = 2 - a + a / 4
        return Double(Int(365.25 * Double(y + 4716)))
            + Double(Int(30.6001 * Double(m + 1)))
            + Double(d) + Double(b) - 1524.5 + hourUtc / 24.0
    }

    public static func sunTimes(y: Int, m: Int, d: Int, lat: Double, lon: Double) -> SunTimes {
        SunTimes(
            bmnt: solarCrossing(y: y, m: m, d: d, lat: lat, lon: lon, altDeg: -12.0, morning: true),
            civilDawn: solarCrossing(y: y, m: m, d: d, lat: lat, lon: lon, altDeg: -6.0, morning: true),
            sunrise: solarCrossing(y: y, m: m, d: d, lat: lat, lon: lon, altDeg: -0.833, morning: true),
            sunset: solarCrossing(y: y, m: m, d: d, lat: lat, lon: lon, altDeg: -0.833, morning: false),
            civilDusk: solarCrossing(y: y, m: m, d: d, lat: lat, lon: lon, altDeg: -6.0, morning: false),
            eent: solarCrossing(y: y, m: m, d: d, lat: lat, lon: lon, altDeg: -12.0, morning: false)
        )
    }

    private static func solarCrossing(y: Int, m: Int, d: Int, lat: Double, lon: Double,
                                      altDeg: Double, morning: Bool) -> Double? {
        var tUt = 12.0 - lon / 15.0
        for _ in 0..<3 {
            let jd = julianDay(y0: y, m0: m, d: d, hourUtc: tUt)
            let t = (jd - 2451545.0) / 36525.0
            let l0 = norm360(280.46646 + 36000.76983 * t + 0.0003032 * t * t)
            let ma = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
            let e = 0.016708634 - 0.000042037 * t
            let c = (1.914602 - 0.004817 * t) * sin(ma * d2r)
                + (0.019993 - 0.000101 * t) * sin(2 * ma * d2r)
                + 0.000289 * sin(3 * ma * d2r)
            let trueLong = l0 + c
            let omega = 125.04 - 1934.136 * t
            let lambda = trueLong - 0.00569 - 0.00478 * sin(omega * d2r)
            let eps0 = 23.0 + 26.0 / 60.0 + 21.448 / 3600.0 - 46.815 * t / 3600.0
            let eps = eps0 + 0.00256 * cos(omega * d2r)
            let decl = asin(sin(eps * d2r) * sin(lambda * d2r)) * r2d
            let yv = {
                let x = tan(eps * d2r / 2.0)
                return x * x
            }()
            let eqTime = 4.0 * r2d * (
                yv * sin(2 * l0 * d2r) - 2.0 * e * sin(ma * d2r)
                    + 4.0 * e * yv * sin(ma * d2r) * cos(2 * l0 * d2r)
                    - 0.5 * yv * yv * sin(4 * l0 * d2r) - 1.25 * e * e * sin(2 * ma * d2r)
            )
            let cosH = (sin(altDeg * d2r) - sin(lat * d2r) * sin(decl * d2r))
                / (cos(lat * d2r) * cos(decl * d2r))
            if cosH < -1.0 || cosH > 1.0 { return nil }
            let h = acos(cosH) * r2d
            let solarNoonUt = 12.0 - lon / 15.0 - eqTime / 60.0
            tUt = morning ? solarNoonUt - h / 15.0 : solarNoonUt + h / 15.0
        }
        return ((tUt.truncatingRemainder(dividingBy: 24.0)) + 24.0)
            .truncatingRemainder(dividingBy: 24.0)
    }

    // MARK: - Moon

    /// Moon RA (deg), declination (deg), ecliptic longitude (deg).
    private static func moonPos(jd: Double) -> (ra: Double, dec: Double, lon: Double) {
        let t = (jd - 2451545.0) / 36525.0
        let lp = norm360(218.3164477 + 481267.88123421 * t)
        let dd = norm360(297.8501921 + 445267.1114034 * t)
        let ms = norm360(357.5291092 + 35999.0502909 * t)
        let mp = norm360(134.9633964 + 477198.8675055 * t)
        let f = norm360(93.2720950 + 483202.0175233 * t)
        let lon = lp
            + 6.288774 * sin(mp * d2r)
            + 1.274027 * sin((2 * dd - mp) * d2r)
            + 0.658314 * sin(2 * dd * d2r)
            + 0.213618 * sin(2 * mp * d2r)
            - 0.185116 * sin(ms * d2r)
            - 0.114332 * sin(2 * f * d2r)
            + 0.058793 * sin((2 * dd - 2 * mp) * d2r)
            + 0.057066 * sin((2 * dd - ms - mp) * d2r)
            + 0.053322 * sin((2 * dd + mp) * d2r)
            + 0.045758 * sin((2 * dd - ms) * d2r)
        let lat = 5.128122 * sin(f * d2r)
            + 0.280602 * sin((mp + f) * d2r)
            + 0.277693 * sin((mp - f) * d2r)
            + 0.173237 * sin((2 * dd - f) * d2r)
            + 0.055413 * sin((2 * dd - mp + f) * d2r)
            + 0.046271 * sin((2 * dd - mp - f) * d2r)
        let eps = (23.4393 - 0.0130 * t) * d2r
        let lam = lon * d2r
        let beta = lat * d2r
        var ra = atan2(sin(lam) * cos(eps) - tan(beta) * sin(eps), cos(lam)) * r2d
        ra = ((ra.truncatingRemainder(dividingBy: 360.0)) + 360.0)
            .truncatingRemainder(dividingBy: 360.0)
        let dec = asin(sin(beta) * cos(eps) + cos(beta) * sin(eps) * sin(lam)) * r2d
        return (ra, dec, norm360(lon))
    }

    private static func sunEclipticLon(jd: Double) -> Double {
        let t = (jd - 2451545.0) / 36525.0
        let l0 = norm360(280.46646 + 36000.76983 * t)
        let ma = 357.52911 + 35999.05029 * t
        return norm360(l0 + 1.914602 * sin(ma * d2r) + 0.019993 * sin(2 * ma * d2r))
    }

    private static func gmstDeg(jd: Double) -> Double {
        let t = (jd - 2451545.0) / 36525.0
        return norm360(280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t)
    }

    private static func moonAltitude(jd: Double, lat: Double, lon: Double) -> Double {
        let pos = moonPos(jd: jd)
        let lst = norm360(gmstDeg(jd: jd) + lon)
        let h = (lst - pos.ra) * d2r
        return asin(
            sin(lat * d2r) * sin(pos.dec * d2r)
                + cos(lat * d2r) * cos(pos.dec * d2r) * cos(h)
        ) * r2d
    }

    public static func moonInfo(y: Int, m: Int, d: Int, lat: Double, lon: Double,
                                timeZone: TimeZone = .current) -> MoonInfo {
        let noon = julianDay(y0: y, m0: m, d: d, hourUtc: 12.0)
        let elong = norm360(moonPos(jd: noon).lon - sunEclipticLon(jd: noon))
        let illum = Int(((1.0 - cos(elong * d2r)) / 2.0 * 100.0).rounded())
        let name: String
        switch elong {
        case ..<22.5, 337.5...: name = "New moon"
        case ..<67.5: name = "Waxing crescent"
        case ..<112.5: name = "First quarter"
        case ..<157.5: name = "Waxing gibbous"
        case ..<202.5: name = "Full moon"
        case ..<247.5: name = "Waning gibbous"
        case ..<292.5: name = "Last quarter"
        default: name = "Waning crescent"
        }

        var rises: [Double] = []
        var sets: [Double] = []
        let std = 0.125
        // Scan the LOCAL calendar day, not 00:00–24:00 UT.
        let startUt = -localOffsetHours(y: y, m: m, d: d, timeZone: timeZone)
        var prev = moonAltitude(jd: julianDay(y0: y, m0: m, d: d, hourUtc: startUt),
                                lat: lat, lon: lon) - std
        for i in 1...144 {
            let tHour = startUt + Double(i) * 10.0 / 60.0
            let cur = moonAltitude(jd: julianDay(y0: y, m0: m, d: d, hourUtc: tHour),
                                   lat: lat, lon: lon) - std
            if prev <= 0 && cur > 0 {
                rises.append(tHour - (10.0 / 60.0) * cur / (cur - prev))
            }
            if prev > 0 && cur <= 0 {
                sets.append(tHour - (10.0 / 60.0) * cur / (cur - prev))
            }
            prev = cur
        }
        return MoonInfo(phaseName: name, illuminationPct: illum, rises: rises, sets: sets)
    }

    private static func localOffsetHours(y: Int, m: Int, d: Int, timeZone: TimeZone) -> Double {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = timeZone
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = 0; comps.minute = 0; comps.second = 0
        let date = comps.date ?? Date()
        return Double(timeZone.secondsFromGMT(for: date)) / 3600.0
    }

    // MARK: - Formatting

    /// "0453" style; UT hour → local clock via the given zone's offset on that date.
    public static func formatLocal(_ utHours: Double?, y: Int, m: Int, d: Int,
                                   timeZone: TimeZone = .current) -> String {
        guard let utHours else { return "----" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = Int(utHours)
        comps.minute = Int(((utHours.truncatingRemainder(dividingBy: 1.0)) * 60.0).rounded())
        comps.second = 0
        let utcDate = cal.date(from: comps) ?? Date()
        let offsetMin = timeZone.secondsFromGMT(for: utcDate) / 60
        var total = Int((utHours * 60.0).rounded()) + offsetMin
        total = ((total % 1440) + 1440) % 1440
        return String(format: "%02d%02d", total / 60, total % 60)
    }

    public static func formatZulu(_ utHours: Double?) -> String {
        guard let utHours else { return "----" }
        let total = ((Int((utHours * 60.0).rounded()) % 1440) + 1440) % 1440
        return String(format: "%02d%02dZ", total / 60, total % 60)
    }

    private static func norm360(_ v: Double) -> Double {
        ((v.truncatingRemainder(dividingBy: 360.0)) + 360.0)
            .truncatingRemainder(dividingBy: 360.0)
    }
}
