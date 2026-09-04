import CoreLocation
import Foundation
import GridFixCore

/// Where the magnetic reference comes from, and how sure we are of it.
///
/// The app always tells the operator which of these it used. A declination
/// with no provenance is the kind of number people stop questioning.
enum DeclinationSource: String {
    /// Typed in Settings from the map sheet or the order. Beats every model.
    case override = "SET"
    /// trueHeading - magneticHeading from a live compass. Exact, never stale,
    /// but only ever describes where you are standing right now.
    case heading = "COMPASS"
    /// The carried World Magnetic Model. Works anywhere, any date, until it
    /// expires.
    case model = "WMM"
    /// Nothing available — show grid and true north only and say so. Never
    /// show zero and let it read as "no declination here".
    case none = "—"
}

struct DeclinationReading {
    let degreesEast: Double?
    let source: DeclinationSource
    /// Set when the carried model is past its epoch: the value is an
    /// extrapolation and the operator should be told, not quietly served.
    let modelExpired: Bool

    var display: String {
        guard let d = degreesEast else { return "MAGNETIC REFERENCE UNAVAILABLE" }
        let ew = d >= 0 ? "E" : "W"
        return String(format: "%.1f° %@", abs(d), ew)
    }
}

/// Resolves declination in the order the field wants it, not the order that is
/// easiest to compute. See `docs/wmm-plan.md`.
struct DeclinationService {
    /// Operator override from Settings, east-positive degrees.
    var overrideDegrees: Double?
    var model: WMM? = WMM.bundled

    func declination(lat: Double, lon: Double,
                     heightMeters: Double = 0,
                     date: Date = Date(),
                     heading: CLHeading? = nil,
                     isCurrentPosition: Bool) -> DeclinationReading {
        if let o = overrideDegrees {
            return DeclinationReading(degreesEast: o, source: .override, modelExpired: false)
        }

        // Only for where the phone actually is. Using a heading-derived value
        // for a waypoint two valleys over is a category error.
        if isCurrentPosition, let h = heading,
           h.headingAccuracy >= 0, h.trueHeading >= 0 {
            let d = h.trueHeading - h.magneticHeading
            return DeclinationReading(degreesEast: normalise(d), source: .heading,
                                      modelExpired: false)
        }

        if let m = model {
            let year = WMM.decimalYear(from: date)
            let d = m.declination(lat: lat, lon: lon,
                                  heightMeters: heightMeters, decimalYear: year)
            return DeclinationReading(degreesEast: d, source: .model,
                                      modelExpired: !m.isValid(at: year))
        }

        return DeclinationReading(degreesEast: nil, source: .none, modelExpired: false)
    }

    /// Fold into -180..180 so a heading pair that straddles north does not
    /// report a 359° declination.
    private func normalise(_ d: Double) -> Double {
        var v = d.truncatingRemainder(dividingBy: 360.0)
        if v > 180 { v -= 360 }
        if v < -180 { v += 360 }
        return v
    }
}
