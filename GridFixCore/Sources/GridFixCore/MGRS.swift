import Foundation

/// MGRS forward and reverse.
///
/// Android gets this from `mil.nga:mgrs`, a JVM library with no iOS build, so
/// here it is implemented directly on top of `UTM`. That is a second source of
/// truth, which is exactly the thing that drifts — so both platforms are pinned
/// to the same `golden.json`, and a divergence fails CI on whichever side moved.
///
/// MGRS truncates, it never rounds: 12345 at 100 m precision is "123", not
/// "124". A rounded grid can name a square the shooter is not standing in.
public enum MGRS {

    public struct Parts: Equatable, Sendable {
        /// Grid zone designator, e.g. "40R".
        public let gzd: String
        /// 100 km square, e.g. "CQ".
        public let square: String
        public let easting: String
        public let northing: String
        /// Canonical written form with group breaks: "40R CQ 1234 5678".
        public let full: String

        public init(gzd: String, square: String, easting: String, northing: String, full: String) {
            self.gzd = gzd
            self.square = square
            self.easting = easting
            self.northing = northing
            self.full = full
        }
    }

    /// Lat/lon to MGRS at 4, 6, 8 or 10 digits. Nil outside -80...84.
    public static func parts(lat: Double, lon: Double, digits: Int) -> Parts? {
        guard lat >= -80.0, lat <= 84.0 else { return nil }
        let d = [4, 6, 8, 10].contains(digits) ? digits : 10
        let z = UTM.zone(lat: lat, lon: lon)
        let north = lat >= 0
        let p = UTM.forZone(lat: lat, lon: lon, zone: z, north: north)
        let sq = UTM.squareLetters(zone: z, easting: p.easting, northing: p.northing)
        guard sq.count == 2 else { return nil }
        let half = d / 2
        let scale = pow(10.0, Double(5 - half))
        let e = Int(floor(p.easting.truncatingRemainder(dividingBy: 100000.0) / scale))
        let n = Int(floor(p.northing.truncatingRemainder(dividingBy: 100000.0) / scale))
        let gzd = "\(z)\(UTM.bandLetter(lat: lat))"
        let es = pad(e, half)
        let ns = pad(n, half)
        return Parts(gzd: gzd, square: sq, easting: es, northing: ns,
                     full: "\(gzd) \(sq) \(es) \(ns)")
    }

    /// The compact machine form with no spaces, e.g. "40RCQ12345678".
    public static func string(lat: Double, lon: Double, digits: Int) -> String? {
        guard let p = parts(lat: lat, lon: lon, digits: digits) else { return nil }
        return p.gzd + p.square + p.easting + p.northing
    }

    /// Parse an MGRS string to the CENTRE of the cell it names.
    ///
    /// A 6-digit grid means "somewhere in this 100 m square", and re-formatting
    /// a corner point can fall into the neighbouring cell, so this aims at the
    /// middle. For control points use ``parseCorner(_:)`` instead.
    public static func parse(_ text: String) -> (lat: Double, lon: Double)? {
        decode(text).map { d in
            UTM.inverse(easting: d.easting + d.cell / 2.0,
                        northing: d.northing + d.cell / 2.0,
                        zone: d.zone, north: d.north)
        }
    }

    /// Parse an MGRS string to the SW CORNER of the cell it names — the grid
    /// line intersection. Photo-map calibration control points are corners, and
    /// using ``parse(_:)`` there bakes a half-cell error into the homography.
    public static func parseCorner(_ text: String) -> (lat: Double, lon: Double)? {
        decode(text).map { d in
            UTM.inverse(easting: d.easting, northing: d.northing,
                        zone: d.zone, north: d.north)
        }
    }

    /// Scale a typed grid line number to 5 digits: "45" becomes 45000.
    /// Control point entry takes 2 to 5 digits; anything else is nil.
    public static func scaleGridLineNumber(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter { $0.isNumber && $0.isASCII }
        guard digits.count >= 2, digits.count <= 5,
              digits.count == trimmed.count else { return nil }
        return Double(digits + String(repeating: "0", count: 5 - digits.count))
    }

    // MARK: - Internals

    struct Decoded {
        let zone: Int
        let north: Bool
        let easting: Double
        let northing: Double
        /// Cell size in metres for the precision that was typed.
        let cell: Double
    }

    static func pad(_ v: Int, _ width: Int) -> String {
        guard width > 0 else { return "" }
        let s = String(v)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    static func decode(_ text: String) -> Decoded? {
        let s = text.uppercased().filter { !$0.isWhitespace }
        guard !s.isEmpty else { return nil }
        let chars = Array(s)
        var i = 0
        while i < chars.count, chars[i].isNumber { i += 1 }
        guard i >= 1, i <= 2, let zone = Int(String(chars[0..<i])),
              zone >= 1, zone <= 60, i < chars.count else { return nil }

        let band = chars[i]; i += 1
        guard let bandIndex = UTM.bands.firstIndex(of: band) else { return nil }
        guard i + 2 <= chars.count else { return nil }
        let colLetter = chars[i], rowLetter = chars[i + 1]
        i += 2
        guard let ci = UTM.columns.firstIndex(of: colLetter),
              let ri = UTM.rows.firstIndex(of: rowLetter) else { return nil }

        let num = String(chars[i...])
        guard num.allSatisfy({ $0.isNumber && $0.isASCII }),
              num.count % 2 == 0, num.count <= 10 else { return nil }
        let half = num.count / 2
        let cell = half == 0 ? 100000.0 : pow(10.0, Double(5 - half))

        let base = ((zone - 1) % 3) * 8
        let col = ci - base + 1
        guard col >= 1, col <= 8 else { return nil }
        let numChars = Array(num)
        let eDigits = half == 0 ? 0 : Int(String(numChars[0..<half])) ?? 0
        let nDigits = half == 0 ? 0 : Int(String(numChars[half...])) ?? 0
        let easting = Double(col) * 100000.0 + Double(eDigits) * cell

        // The row letter repeats every 2,000,000 m. Walk the cycles and keep the
        // first whose latitude actually lands inside the band that was typed.
        let r0 = (ri - (zone % 2 == 0 ? 5 : 0) + 20) % 20
        let north = band >= "N"
        let bandLo = Double(bandIndex) * 8.0 - 80.0
        let bandHi = bandLo + (band == "X" ? 12.0 : 8.0)
        let cm = UTM.centralMeridian(zone: zone)

        for k in 0...10 {
            let n = Double((r0 + k * 20)) * 100000.0 + Double(nDigits) * cell
            // Reject before projecting: past these the Snyder inverse is beyond
            // a pole and returns garbage that can still land inside the window.
            if north {
                if n > 9_500_000.0 { break }
            } else {
                if n > 10_000_000.0 { break }
                if n < 1_000_000.0 { continue }
            }
            let ll = UTM.inverse(easting: easting, northing: n, zone: zone, north: north)
            if ll.lat >= bandLo - 0.5, ll.lat <= bandHi + 0.5, abs(ll.lon - cm) <= 10.0 {
                return Decoded(zone: zone, north: north, easting: easting, northing: n, cell: cell)
            }
        }
        return nil
    }
}
