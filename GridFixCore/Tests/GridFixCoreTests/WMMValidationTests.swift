import XCTest
@testable import GridFixCore

/// The only test that can validate the coefficients themselves.
///
/// NOAA publishes the field they expect at a set of points spanning the poles,
/// the equator, both hemispheres, ground level and 100 km altitude, at the
/// epoch and mid-epoch. Nothing else in this repository can tell a correct
/// `WMM.COF` from a subtly wrong one, and nothing else can tell a correct
/// implementation from one that merely agrees with itself.
final class WMMValidationTests: XCTestCase {

    struct Row {
        let year, heightKm, lat, lon: Double
        let x, y, z, h, f, inclination, declination: Double
    }

    /// NOAA's layout, in order: date, height (km), lat, lon, X, Y, Z, H, F, I,
    /// D, grid variation, then rates of change. Header lines are comments and
    /// yield too few numbers to pass the count check.
    ///
    /// The grid-variation column is literally `NaN` away from the poles, and
    /// Swift's `Double("NaN")` parses that to a real NaN rather than failing,
    /// so the column count stays right and the field is simply never read.
    static func parse(_ text: String) -> [Row] {
        var rows: [Row] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") { continue }
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .compactMap { Double($0) }
            guard f.count >= 11 else { continue }
            let row = Row(year: f[0], heightKm: f[1], lat: f[2], lon: f[3],
                          x: f[4], y: f[5], z: f[6], h: f[7], f: f[8],
                          inclination: f[9], declination: f[10])
            // A NaN in a column we actually use would silently pass every
            // comparison below, so drop the row rather than trust it.
            let used = [row.year, row.heightKm, row.lat, row.lon, row.x, row.y,
                        row.z, row.h, row.f, row.inclination, row.declination]
            guard used.allSatisfy({ $0.isFinite }) else { continue }
            rows.append(row)
        }
        return rows
    }

    /// NOAA ships this file under more than one spelling depending on where it
    /// was downloaded from, and bundle lookup is case-sensitive.
    static func testValuesURL() -> URL? {
        for name in ["WMM2025_TEST_VALUES", "WMM2025_TestValues",
                     "WMM2025testvalues", "WMM_TEST_VALUES"] {
            if let u = Bundle.module.url(forResource: name, withExtension: "txt") {
                return u
            }
        }
        return nil
    }

    func testAgainstNOAAPublishedTestValues() throws {
        guard let model = WMM.bundled else {
            throw XCTSkip("WMM.COF is not bundled — see docs/wmm-plan.md")
        }
        guard let url = Self.testValuesURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("the NOAA test-value file is not bundled — see docs/wmm-plan.md")
        }

        let rows = Self.parse(text)
        // The published table is a dozen points, not a thousand: poles, equator,
        // both hemispheres, two altitudes, epoch and mid-epoch. Small and
        // deliberately chosen, so every row has to pass.
        XCTAssertGreaterThanOrEqual(rows.count, 6,
                                    "the test-value file parsed to almost nothing")

        var worstD = 0.0, worstI = 0.0, worstF = 0.0, worstXYZ = 0.0
        var worstRow = ""
        for r in rows {
            let got = model.field(lat: r.lat, lon: r.lon,
                                  heightMeters: r.heightKm * 1000.0,
                                  decimalYear: r.year)

            // Declination is circular: 179.9 and -179.9 are 0.2 apart.
            var dd = abs(got.declination - r.declination)
                .truncatingRemainder(dividingBy: 360.0)
            if dd > 180.0 { dd = 360.0 - dd }
            if dd > worstD {
                worstD = dd
                worstRow = "\(r.year) h=\(r.heightKm)km \(r.lat), \(r.lon): "
                    + "got \(got.declination), NOAA says \(r.declination)"
            }
            worstI = max(worstI, abs(got.inclination - r.inclination))
            worstF = max(worstF, abs(got.totalIntensity - r.f))
            worstXYZ = max(worstXYZ, abs(got.x - r.x))
            worstXYZ = max(worstXYZ, abs(got.y - r.y))
            worstXYZ = max(worstXYZ, abs(got.z - r.z))
        }

        // NOAA prints angles to two decimals, so a correct implementation lands
        // inside half of the last place. Anything looser is not a test.
        XCTAssertLessThan(worstD, 0.01, "declination worst case — \(worstRow)")
        XCTAssertLessThan(worstI, 0.01, "inclination is off by \(worstI)°")
        XCTAssertLessThan(worstF, 1.0, "total intensity is off by \(worstF) nT")
        XCTAssertLessThan(worstXYZ, 1.0, "a field component is off by \(worstXYZ) nT")
    }

    func testTheParserSkipsCommentsAndKeepsData() {
        let sample = """
        # Field 1: Date
        # Field 12: Grid Variation (deg)
          2025.0    0.0   80.0    0.0     6521.6      145.9    54791.5     6523.2    55178.5   83.21    1.28    1.28
          2025.0    0.0    0.0  120.0    39677.8     -109.6   -10580.2    39677.9    41064.3  -14.93   -0.16     NaN
        """
        let rows = Self.parse(sample)
        XCTAssertEqual(rows.count, 2, "a NaN in the unused grid-variation column must not drop a row")
        XCTAssertEqual(rows[0].lat, 80.0)
        XCTAssertEqual(rows[0].declination, 1.28, accuracy: 1e-9)
        XCTAssertEqual(rows[1].lon, 120.0)
        XCTAssertEqual(rows[1].declination, -0.16, accuracy: 1e-9)
    }
}
