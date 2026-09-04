import Foundation

/// Every string the field screens put on glass.
///
/// The unit raw values match the Android settings store exactly, so a user's
/// saved preference means the same thing on both phones and a backup restored
/// across platforms does not silently change units.
public enum DistanceUnit: Int, Sendable, CaseIterable {
    case metric = 0, imperial = 1, nautical = 2
}

public enum AngleUnit: Int, Sendable, CaseIterable {
    case degrees = 0, mils = 1
}

public enum LatLonFormat: Int, Sendable, CaseIterable {
    case decimalDegrees = 0, degreesMinutes = 1, degreesMinutesSeconds = 2
}

public enum Format {

    static let posix = Locale(identifier: "en_US_POSIX")

    /// Doubles only. Integers are padded by hand below, because %d in a
    /// format string reads 32 bits and Swift's Int is 64.
    static func f(_ fmt: String, _ args: CVarArg...) -> String {
        String(format: fmt, locale: posix, arguments: args)
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    /// Distance for the readout. Metric switches to km at 1 km and drops a
    /// decimal past 10 km, because a fourth significant figure on a 12 km leg
    /// is noise you cannot pace out anyway.
    public static func distance(meters: Double, unit: DistanceUnit) -> String {
        switch unit {
        case .imperial:
            let feet = meters * 3.28084
            return feet < 1000.0 ? f("%.0f ft", feet) : f("%.2f mi", meters / 1609.344)
        case .nautical:
            return meters < 1852.0 ? f("%.0f m", meters) : f("%.2f NM", meters / 1852.0)
        case .metric:
            if meters < 1000.0 { return f("%.0f m", meters) }
            if meters < 10000.0 { return f("%.2f km", meters / 1000.0) }
            return f("%.1f km", meters / 1000.0)
        }
    }

    /// Bearing as three-digit degrees or NATO mils.
    public static func angle(degrees: Double, unit: AngleUnit) -> String {
        switch unit {
        case .mils:
            let mils = Int((degrees * 6400.0 / 360.0).rounded())
            return "\(((mils % 6400) + 6400) % 6400) mils"
        case .degrees:
            let deg = Int(degrees.rounded())
            return pad(((deg % 360) + 360) % 360, 3) + "°"
        }
    }

    /// Lat/lon in the chosen format. DMS carries in tenths of arc-seconds and
    /// DDM in thousandths of a minute, so 59.96 seconds rolls the minute over
    /// instead of printing 60.0.
    public static func latLon(lat: Double, lon: Double, format: LatLonFormat) -> String {
        func one(_ value: Double, _ positive: Character, _ negative: Character) -> String {
            let hemi = value >= 0 ? positive : negative
            let v = abs(value)
            switch format {
            case .decimalDegrees:
                return f("%.5f", v) + "° \(hemi)"
            case .degreesMinutesSeconds:
                let tenths = Int((v * 36000.0).rounded())
                let d = tenths / 36000
                let mm = (tenths % 36000) / 600
                let s = Double(tenths % 600) / 10.0
                return "\(d)° " + pad(mm, 2) + "' " + f("%04.1f", s) + "\" \(hemi)"
            case .degreesMinutes:
                let milli = Int((v * 60000.0).rounded())
                let d = milli / 60000
                let mFull = Double(milli % 60000) / 1000.0
                return "\(d)° " + f("%06.3f", mFull) + "' \(hemi)"
            }
        }
        return one(lat, "N", "S") + "   " + one(lon, "E", "W")
    }

    public static func utm(_ u: UTM.Coordinate?) -> String {
        guard let u else { return "—" }
        return "\(u.zone)\(u.hemisphere) \(u.easting)E \(u.northing)N"
    }

    /// Military date-time group in Zulu, e.g. "241435Z AUG 26".
    public static func dtg(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = posix
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "ddHHmm'Z' MMM yy"
        return df.string(from: date).uppercased()
    }

    public static func altitude(meters: Double, unit: DistanceUnit) -> String {
        unit == .imperial
            ? "\(Int((meters * 3.28084).rounded())) ft"
            : "\(Int(meters.rounded())) m"
    }

    public static func accuracy(meters: Double, unit: DistanceUnit) -> String {
        unit == .imperial
            ? "±\(Int((meters * 3.28084).rounded())) ft"
            : "±\(Int(meters.rounded())) m"
    }

    public static func speed(metersPerSecond: Double, unit: DistanceUnit) -> String {
        switch unit {
        case .imperial: return f("%.1f mph", metersPerSecond * 2.23694)
        case .nautical: return f("%.1f kn", metersPerSecond * 1.94384)
        case .metric:   return f("%.1f km/h", metersPerSecond * 3.6)
        }
    }
}
