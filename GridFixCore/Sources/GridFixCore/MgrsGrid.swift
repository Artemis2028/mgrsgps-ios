import Foundation

/// The MGRS grid for a viewport, as geometry rather than as drawing.
///
/// The Android overlay computes interval, sampling and painting in one Canvas
/// pass. MapLibre wants the opposite: hand it a GeoJSON source and let the
/// renderer do the drawing on the GPU. So this file stops at the geometry —
/// lines and labels in lat/lon — and knows nothing about any map engine, which
/// is also what makes it testable, which the Canvas version never was.
///
///     bbox -> cells(...) -> build(...) -> [GridLine] + [GridLabel] -> renderer
///
/// Ported from `MgrsGridOverlay.kt`. The parts that carry real doctrine —
/// which zone a line belongs to, the Norway and Svalbard exceptions, clipping
/// at the zone meridian so a grid line never leaks into its neighbour — are
/// ported line for line, because those are the parts that are wrong in most
/// grid overlays.
public enum MgrsGrid {

    /// One grid-zone designator cell: a zone column crossed with a band row.
    public struct Cell: Equatable, Sendable {
        public let zone: Int
        /// Index into "CDEFGHJKLMNPQRSTUVWX", 0 = C at 80° S.
        public let band: Int
        public let lonWest, lonEast, latSouth, latNorth: Double

        public var isNorth: Bool { band >= 10 }
        public var letter: Character { UTM.bands[band] }
        public var gzd: String { "\(zone)\(letter)" }
    }

    public struct Result: Sendable {
        public let lines: [GridLine]
        public let labels: [GridLabel]
        /// Metres between fine grid lines. 0 means the view is too wide for a
        /// metre grid and only GZD boundaries are drawn.
        public let interval: Int
        /// What the readout shows: "1 km", "100 m", "GZD".
        public let intervalLabel: String
    }

    /// Samples per grid line. A UTM line is straight in its own projection and
    /// curved in Web Mercator; twelve segments hold the curve to well under a
    /// pixel at any zoom the grid is drawn at.
    static let samplesPerLine = 12
    /// Hard ceiling on lines per direction per cell. A degenerate viewport must
    /// cost a bounded amount of work, not lock the map up.
    static let lineGuard = 90

    // MARK: - Cells

    /// Every GZD cell touching the viewport, with the two irregular regions
    /// handled: 32V is widened over south-west Norway at the expense of 31V,
    /// and band X has four wide zones over Svalbard with 32X, 34X and 36X
    /// simply not existing.
    public static func cells(latSouth: Double, latNorth: Double,
                             lonWest: Double, lonEast: Double) -> [Cell] {
        var out: [Cell] = []
        let bandSouth = min(19, max(0, Int(floor((max(latSouth, -80.0) + 80.0) / 8.0))))
        let bandNorth = min(19, max(0, Int(floor((min(latNorth, 83.999) + 80.0) / 8.0))))
        guard bandSouth <= bandNorth else { return [] }

        for b in bandSouth...bandNorth {
            let cs = -80.0 + 8.0 * Double(b)
            let cn = b == 19 ? 84.0 : cs + 8.0
            for z in 1...60 {
                var cw = Double(z - 1) * 6.0 - 180.0
                var ce = cw + 6.0
                if b == 17 {                       // band V: Norway
                    if z == 31 { ce = 3.0 }
                    if z == 32 { cw = 3.0 }
                }
                if b == 19 && (31...37).contains(z) {   // band X: Svalbard
                    switch z {
                    case 31: cw = 0.0;  ce = 9.0
                    case 33: cw = 9.0;  ce = 21.0
                    case 35: cw = 21.0; ce = 33.0
                    case 37: cw = 33.0; ce = 42.0
                    default: continue               // 32X, 34X and 36X do not exist
                    }
                }
                if ce < lonWest || cw > lonEast { continue }
                out.append(Cell(zone: z, band: b, lonWest: cw, lonEast: ce,
                                latSouth: cs, latNorth: cn))
            }
        }
        return out
    }

    // MARK: - Build

    /// Everything the renderer needs for one viewport.
    ///
    /// - Parameters:
    ///   - metersPerPoint: ground metres per screen point at the viewport
    ///     centre — `MLNMapView.metersPerPoint(atLatitude:)`.
    public static func build(latSouth: Double, latNorth: Double,
                             lonWest: Double, lonEast: Double,
                             metersPerPoint: Double) -> Result {
        let interval = Grid.chooseInterval(metersPerPoint: metersPerPoint)
        var lines: [GridLine] = []
        var labels: [GridLabel] = []

        // A viewport straddling the antimeridian arrives as west > east.
        let ranges: [(Double, Double)] = lonWest <= lonEast
            ? [(lonWest, lonEast)]
            : [(lonWest, 180.0), (-180.0, lonEast)]

        var drawnEdges = Set<String>()
        for (rw, re) in ranges {
            let inView = cells(latSouth: latSouth, latNorth: latNorth,
                               lonWest: rw, lonEast: re)
            for cell in inView {
                appendGzdEdges(cell, rw, re, latSouth, latNorth, &lines, &drawnEdges)
                guard interval > 0 else { continue }
                appendCellGrid(cell, rw, re, latSouth, latNorth, interval, &lines, &labels)
            }
        }

        return Result(lines: lines, labels: labels,
                      interval: interval, intervalLabel: Grid.intervalLabel(interval))
    }

    // MARK: - GZD boundaries

    /// The cell's own four edges, clipped to the viewport and deduplicated so a
    /// shared boundary is not drawn twice at double opacity.
    static func appendGzdEdges(_ cell: Cell,
                               _ rw: Double, _ re: Double,
                               _ latSouth: Double, _ latNorth: Double,
                               _ lines: inout [GridLine],
                               _ drawn: inout Set<String>) {
        let s = max(cell.latSouth, latSouth)
        let n = min(cell.latNorth, latNorth)
        let w = max(cell.lonWest, rw)
        let e = min(cell.lonEast, re)
        guard s < n, w < e else { return }

        func key(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> String {
            String(format: "%.6f,%.6f,%.6f,%.6f", a, b, c, d)
        }
        // Meridians and parallels are both straight lines in Web Mercator, so
        // two points are exact — no sampling needed.
        for lon in [cell.lonWest, cell.lonEast] where lon >= w - 1e-9 && lon <= e + 1e-9 {
            let k = key(s, lon, n, lon)
            if drawn.insert(k).inserted {
                lines.append(GridLine(points: [GeoPoint(lat: s, lon: lon),
                                               GeoPoint(lat: n, lon: lon)],
                                      heavy: true, kind: .gzd))
            }
        }
        for lat in [cell.latSouth, cell.latNorth] where lat >= s - 1e-9 && lat <= n + 1e-9 {
            let k = key(lat, w, lat, e)
            if drawn.insert(k).inserted {
                lines.append(GridLine(points: [GeoPoint(lat: lat, lon: w),
                                               GeoPoint(lat: lat, lon: e)],
                                      heavy: true, kind: .gzd))
            }
        }
    }

    // MARK: - The grid inside one cell

    static func appendCellGrid(_ cell: Cell,
                               _ rw: Double, _ re: Double,
                               _ latSouth: Double, _ latNorth: Double,
                               _ interval: Int,
                               _ lines: inout [GridLine],
                               _ labels: inout [GridLabel]) {
        let cw = max(cell.lonWest, rw)
        let ce = min(cell.lonEast, re)
        let cs = max(cell.latSouth, latSouth)
        let cn = min(cell.latNorth, latNorth)
        guard cw < ce, cs < cn else { return }

        // UTM extent of the clipped cell, from its corners plus the midpoint of
        // each edge — the edges bow, so corners alone under-cover the range.
        var eMin = Double.greatestFiniteMagnitude, eMax = -Double.greatestFiniteMagnitude
        var nMin = Double.greatestFiniteMagnitude, nMax = -Double.greatestFiniteMagnitude
        let midLat = (cs + cn) / 2.0, midLon = (cw + ce) / 2.0
        let samples = [(cs, cw), (cs, ce), (cn, cw), (cn, ce),
                       (cs, midLon), (cn, midLon), (midLat, cw), (midLat, ce)]
        for (la, lo) in samples {
            let p = UTM.forZone(lat: la, lon: lo, zone: cell.zone, north: cell.isNorth)
            eMin = min(eMin, p.easting); eMax = max(eMax, p.easting)
            nMin = min(nMin, p.northing); nMax = max(nMax, p.northing)
        }
        let step = Double(interval)
        eMin = floor(eMin / step) * step
        nMin = floor(nMin / step) * step
        eMax += step
        nMax += step

        if interval < 100_000 {
            gridPass(cell, 100_000, eMin, eMax, nMin, nMax, cw, ce, cs, cn,
                     skipMultipleOf: 0, kind: .square, heavy: true, &lines, &labels)
            gridPass(cell, interval, eMin, eMax, nMin, nMax, cw, ce, cs, cn,
                     skipMultipleOf: 100_000, kind: .metre, heavy: false, &lines, &labels)
        } else {
            gridPass(cell, 100_000, eMin, eMax, nMin, nMax, cw, ce, cs, cn,
                     skipMultipleOf: 0, kind: .square, heavy: true, &lines, &labels)
        }

        appendSquareLetters(cell, eMin, eMax, nMin, nMax, cw, ce, cs, cn, &labels)
    }

    static func gridPass(_ cell: Cell, _ interval: Int,
                         _ eMin: Double, _ eMax: Double,
                         _ nMin: Double, _ nMax: Double,
                         _ cw: Double, _ ce: Double, _ cs: Double, _ cn: Double,
                         skipMultipleOf skip: Int,
                         kind: GridLine.Kind, heavy: Bool,
                         _ lines: inout [GridLine],
                         _ labels: inout [GridLabel]) {
        // Values come from the pure helper (and its tests) rather than from a
        // rounded walk off an unaligned start — see Grid.lineValues / Android
        // gridLineValues for the 100 km line that cost.
        for eL in Grid.lineValues(min: eMin, max: eMax, interval: interval,
                                  guardLimit: lineGuard) {
            if skip > 0 && eL % Int64(skip) == 0 { continue }
            let value = Double(eL)
            var pts: [GeoPoint] = []
            pts.reserveCapacity(samplesPerLine + 1)
            for i in 0...samplesPerLine {
                let n = nMin + (nMax - nMin) * Double(i) / Double(samplesPerLine)
                let ll = UTM.inverse(easting: value, northing: n,
                                     zone: cell.zone, north: cell.isNorth)
                pts.append(GeoPoint(lat: ll.lat, lon: ll.lon))
            }
            emit(pts, cell, cw, ce, cs, cn, kind, heavy, value, interval,
                 vertical: true, &lines, &labels)
        }

        for nL in Grid.lineValues(min: nMin, max: nMax, interval: interval,
                                  guardLimit: lineGuard) {
            if skip > 0 && nL % Int64(skip) == 0 { continue }
            let value = Double(nL)
            var pts: [GeoPoint] = []
            pts.reserveCapacity(samplesPerLine + 1)
            for i in 0...samplesPerLine {
                let e = eMin + (eMax - eMin) * Double(i) / Double(samplesPerLine)
                let ll = UTM.inverse(easting: e, northing: value,
                                     zone: cell.zone, north: cell.isNorth)
                pts.append(GeoPoint(lat: ll.lat, lon: ll.lon))
            }
            emit(pts, cell, cw, ce, cs, cn, kind, heavy, value, interval,
                 vertical: false, &lines, &labels)
        }
    }

    /// Clip a sampled line to the cell's meridians and the viewport's parallels,
    /// then keep whatever contiguous runs survive.
    ///
    /// The meridian clip is the important half: a UTM grid line belongs to its
    /// own zone and must stop dead at the zone boundary. Letting it run on is
    /// the single most common bug in MGRS overlays, and it puts a line on the
    /// map that names a grid square that does not exist.
    static func emit(_ pts: [GeoPoint], _ cell: Cell,
                     _ cw: Double, _ ce: Double, _ cs: Double, _ cn: Double,
                     _ kind: GridLine.Kind, _ heavy: Bool,
                     _ value: Double, _ interval: Int,
                     vertical: Bool,
                     _ lines: inout [GridLine],
                     _ labels: inout [GridLabel]) {
        var runs: [[GeoPoint]] = []
        var current: [GeoPoint] = []
        var previous: GeoPoint?
        var previousInside = false

        for (index, p) in pts.enumerated() {
            let inside = p.lon >= cell.lonWest - 1e-9 && p.lon <= cell.lonEast + 1e-9
            if inside {
                if !previousInside, index > 0, let prev = previous {
                    // Entering: start the run exactly on the boundary meridian.
                    let bound = prev.lon < cell.lonWest ? cell.lonWest : cell.lonEast
                    let t = crossing(bound, prev.lon, p.lon)
                    current.append(GeoPoint(lat: prev.lat + t * (p.lat - prev.lat), lon: bound))
                }
                current.append(p)
            } else if previousInside, let prev = previous {
                // Leaving: end the run exactly on the boundary meridian.
                let bound = p.lon < cell.lonWest ? cell.lonWest : cell.lonEast
                let t = crossing(bound, prev.lon, p.lon)
                current.append(GeoPoint(lat: prev.lat + t * (p.lat - prev.lat), lon: bound))
                runs.append(current)
                current = []
            }
            previous = p
            previousInside = inside
        }
        if current.count >= 2 { runs.append(current) }

        for run in runs where run.count >= 2 {
            // Drop runs entirely outside the viewport; the renderer would clip
            // them anyway, but not sending them keeps the source small.
            let lats = run.map(\.lat), lons = run.map(\.lon)
            guard let lo = lats.min(), let hi = lats.max(),
                  let we = lons.min(), let ea = lons.max(),
                  hi >= cs - 1e-9, lo <= cn + 1e-9,
                  ea >= cw - 1e-9, we <= ce + 1e-9 else { continue }
            lines.append(GridLine(points: run, heavy: heavy, kind: kind))

            if kind == .metre || interval == 100_000 {
                let mid = run[run.count / 2]
                labels.append(GridLabel(text: principalDigits(value, interval: interval),
                                        lat: mid.lat, lon: mid.lon))
            }
        }
    }

    /// The digits an operator actually reads off a grid line.
    ///
    /// A map margin prints the two principal figures large and the subordinate
    /// digits small, and the app follows that: 4 567 500 on a 100 m grid is a
    /// big "67" and a small "5". Kept as two pieces so the renderer can set
    /// them at two sizes the way a printed sheet does; ``principalDigits``
    /// joins them for anything that just wants a string.
    public static func principalParts(_ value: Double, interval: Int)
        -> (principal: String, subordinate: String) {
        let v = Int(value.rounded())
        let km = ((v / 1000) % 100 + 100) % 100
        let principal = km < 10 ? "0\(km)" : "\(km)"
        let subordinate: String
        switch interval {
        case 100:
            subordinate = "\((((v / 100) % 10) + 10) % 10)"
        case 10:
            let d = (((v % 1000) + 1000) % 1000) / 10
            subordinate = d < 10 ? "0\(d)" : "\(d)"
        default:
            subordinate = ""
        }
        return (principal, subordinate)
    }

    public static func principalDigits(_ value: Double, interval: Int) -> String {
        let p = principalParts(value, interval: interval)
        return p.principal + p.subordinate
    }

    /// The two-letter 100 km square identifiers whose centres fall in view.
    ///
    /// Android places these in screen space against the viewport edges; here
    /// they sit at the square's own centre and MapLibre's symbol layer handles
    /// collision. Same information, and it survives map rotation for free.
    static func appendSquareLetters(_ cell: Cell,
                                    _ eMin: Double, _ eMax: Double,
                                    _ nMin: Double, _ nMax: Double,
                                    _ cw: Double, _ ce: Double,
                                    _ cs: Double, _ cn: Double,
                                    _ labels: inout [GridLabel]) {
        let size = 100_000.0
        var e = floor(eMin / size) * size
        var guardCount = 0
        while e <= eMax && guardCount < 40 {
            var n = floor(nMin / size) * size
            var innerGuard = 0
            while n <= nMax && innerGuard < 40 {
                let centreE = e + size / 2.0
                let centreN = n + size / 2.0
                n += size
                innerGuard += 1
                guard centreE > 0, centreE < 1_000_000 else { continue }
                let ll = UTM.inverse(easting: centreE, northing: centreN,
                                     zone: cell.zone, north: cell.isNorth)
                guard ll.lat >= cs, ll.lat <= cn, ll.lon >= cw, ll.lon <= ce else { continue }
                let letters = UTM.squareLetters(zone: cell.zone,
                                                easting: centreE, northing: centreN)
                guard letters.count == 2 else { continue }
                labels.append(GridLabel(text: letters, lat: ll.lat, lon: ll.lon))
            }
            e += size
            guardCount += 1
        }
    }

    static func crossing(_ bound: Double, _ a: Double, _ b: Double) -> Double {
        let d = b - a
        if d == 0 { return 0 }
        return min(max((bound - a) / d, 0.0), 1.0)
    }
}

// MARK: - GeoJSON

public extension MgrsGrid.Result {

    /// The grid as a GeoJSON FeatureCollection, ready for
    /// `MLNShapeSource.setShapeData(_:)`.
    ///
    /// Every feature carries `kind` (gzd / square / metre), `heavy`, and for
    /// labels `text` plus `principal` and `subordinate` so a style layer can
    /// set the two at different sizes the way a printed map margin does.
    /// Emitting GeoJSON rather than MapLibre objects keeps all of this
    /// testable and keeps the engine out of the field math.
    func geoJSON() -> Data {
        var features: [String] = []
        features.reserveCapacity(lines.count + labels.count)

        for line in lines {
            let coords = line.points
                .map { "[\(fmt($0.lon)),\(fmt($0.lat))]" }
                .joined(separator: ",")
            features.append("""
            {"type":"Feature","geometry":{"type":"LineString","coordinates":[\(coords)]},\
            "properties":{"kind":"\(line.kind.rawValue)","heavy":\(line.heavy)}}
            """)
        }

        for label in labels {
            let parts = label.text.count == 2 && label.text.allSatisfy(\.isLetter)
                ? (label.text, "")
                : split(label.text)
            features.append("""
            {"type":"Feature","geometry":{"type":"Point","coordinates":\
            [\(fmt(label.lon)),\(fmt(label.lat))]},\
            "properties":{"text":"\(escape(label.text))",\
            "principal":"\(escape(parts.0))","subordinate":"\(escape(parts.1))"}}
            """)
        }

        let doc = """
        {"type":"FeatureCollection","features":[\(features.joined(separator: ","))]}
        """
        return Data(doc.utf8)
    }

    /// Six decimals is about 11 cm — finer than any grid line is drawn, and it
    /// keeps the payload small enough to rebuild on every camera idle.
    private func fmt(_ v: Double) -> String {
        String(format: "%.6f", v)
    }

    /// Grid-line labels are two principal figures plus any subordinate digits.
    private func split(_ text: String) -> (String, String) {
        guard text.count > 2 else { return (text, "") }
        let cut = text.index(text.startIndex, offsetBy: 2)
        return (String(text[..<cut]), String(text[cut...]))
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
