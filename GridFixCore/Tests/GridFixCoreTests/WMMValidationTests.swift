import XCTest
@testable import GridFixCore

/// The only test that can validate the coefficients themselves.
///
/// NOAA publishes a table of about 1,300 points with the field they expect at
/// each. Nothing else in this repository can tell a correct `WMM.COF` from a
/// subtly wrong one, so this is the gate — and it skips loudly rather than
/// passing vacuously when the files are not there yet.
///
/// To turn it on:
///   1. WMM.COF                -> GridFixCore/Sources/GridFixCore/Resources/
///   2. WMM2025_TestValues.txt -> GridFixCore/Tests/GridFixCoreTests/Resources/
///   Both from https://www.ncei.noaa.gov/products/world-magnetic-model
final class WMMValidationTests: XCTestCase {

    struct Row {
        let year, heightKm, lat, lon: Double
        let x, y, z, h, f, inclination, declination: Double
    }

    /// NOAA's layout: date, height (km), lat, lon, X, Y, Z, H, F, I, D, and on
    /// some editions a grid-variation column. Header and prose lines are
    /// skipped by requiring eleven parsable numbers.
    static func parse(_ text: String) -> [Row] {
        var rows: [Row] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .compactMap { Double($0) }
            guard f.count >= 11 else { continue }
            rows.append(Row(year: f[0], heightKm: f[1], lat: f[2], lon: f[3],
                            x: f[4], y: f[5], z: f[6], h: f[7], f: f[8],
                            inclination: f[9], declination: f[10]))
        }
        return rows
    }

    func testAgainstNOAAPublishedTestValues() throws {
        guard let model = WMM.bundled else {
            throw XCTSkip("WMM.COF is not bundled — see docs/wmm-plan.md")
        }
        guard let url = Bundle.module.url(forResource: "WMM2025_TestValues",
                                          withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("WMM2025_TestValues.txt is not bundled — see docs/wmm-plan.md")
        }

        let rows = Self.parse(text)
        XCTAssertGreaterThan(rows.count, 100, "the test-value file parsed to almost nothing")

        var worstD = 0.0, worstI = 0.0, worstF = 0.0
        var worstRow = ""
        for r in rows {
            let got = model.field(lat: r.lat, lon: r.lon,
                                  heightMeters: r.heightKm * 1000.0,
                                  decimalYear: r.year)
            // Declination is circular: 179.9 and -179.9 are 0.2 apart.
            var dd = abs(got.declination - r.declination)
                .truncatingRemainder(dividingBy: 360.0)
            if dd > 180.0 { dd = 360.0 - dd }
            if dd > worstD { worstD = dd; worstRow = "\(r.year) \(r.lat) \(r.lon)" }
            worstI = max(worstI, abs(got.inclination - r.inclination))
            worstF = max(worstF, abs(got.totalIntensity - r.f))
        }

        // NOAA prints two decimals; a correct implementation lands well inside
        // half of the last place. Anything looser is not a test.
        XCTAssertLessThan(worstD, 0.01, "declination is off at \(worstRow)")
        XCTAssertLessThan(worstI, 0.01, "inclination is off")
        XCTAssertLessThan(worstF, 1.0, "total intensity is off by more than a nanotesla")
    }
}
