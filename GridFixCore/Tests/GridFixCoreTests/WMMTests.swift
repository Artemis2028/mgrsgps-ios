import XCTest
@testable import GridFixCore

/// The magnetic model, checked in three layers.
///
/// 1. The Legendre recursion, against closed forms.
/// 2. The whole field pipeline, against dipoles whose answer is known exactly —
///    this is what catches a sign error, and it caught one.
/// 3. NOAA's own published test values, once `WMM.COF` is in the bundle.
///
/// Layer 3 is the only one that can validate the coefficients, and it is
/// skipped rather than faked while the model file is absent. A magnetic model
/// that silently returns something is worse than one that says it has nothing.
final class WMMTests: XCTestCase {

    // MARK: - Legendre

    func testLegendreMatchesClosedFormsAtDegreeOneAndTwo() {
        for degrees in [0.5, 17.0, 45.0, 90.0, 133.0, 179.5] {
            let theta = degrees * .pi / 180.0
            let x = cos(theta), s = sin(theta)
            let (p, dp) = WMM.legendre(cosTheta: x, sinTheta: s)

            XCTAssertEqual(p[0][0], 1.0, accuracy: 1e-14)
            XCTAssertEqual(p[1][0], x, accuracy: 1e-14, "P(1,0) = cos θ")
            XCTAssertEqual(p[1][1], s, accuracy: 1e-14, "P(1,1) = sin θ, Schmidt")
            XCTAssertEqual(p[2][0], 1.5 * x * x - 0.5, accuracy: 1e-13)
            XCTAssertEqual(p[2][1], 3.0.squareRoot() * x * s, accuracy: 1e-13)
            XCTAssertEqual(p[2][2], 3.0.squareRoot() / 2.0 * s * s, accuracy: 1e-13)

            XCTAssertEqual(dp[1][0], -s, accuracy: 1e-13, "dP(1,0)/dθ = -sin θ")
            XCTAssertEqual(dp[1][1], x, accuracy: 1e-13, "dP(1,1)/dθ = cos θ")
        }
    }

    func testLegendreDerivativesMatchNumericalDifferentiation() {
        // Independent of the recursion: differentiate the values themselves.
        let h = 1e-6
        for degrees in [12.0, 40.0, 88.0, 120.0, 168.0] {
            let t = degrees * .pi / 180.0
            let (_, dp) = WMM.legendre(cosTheta: cos(t), sinTheta: sin(t))
            let (pPlus, _) = WMM.legendre(cosTheta: cos(t + h), sinTheta: sin(t + h))
            let (pMinus, _) = WMM.legendre(cosTheta: cos(t - h), sinTheta: sin(t - h))
            for n in 1...WMM.maxDegree {
                for m in 0...n {
                    let numeric = (pPlus[n][m] - pMinus[n][m]) / (2 * h)
                    XCTAssertEqual(dp[n][m], numeric, accuracy: 1e-6,
                                   "dP(\(n),\(m))/dθ at \(degrees)°")
                }
            }
        }
    }

    // MARK: - The field pipeline, proved with dipoles

    private func dipole(g10: Double, g11: Double = 0, h11: Double = 0) -> WMM {
        var g = [[Double]](repeating: [Double](repeating: 0, count: WMM.maxDegree + 1),
                           count: WMM.maxDegree + 1)
        var h = g
        g[1][0] = g10
        g[1][1] = g11
        h[1][1] = h11
        return WMM(epoch: 2025.0, name: "TEST", releaseDate: "",
                   g: g, h: h, gDot: g.map { $0.map { _ in 0.0 } },
                   hDot: g.map { $0.map { _ in 0.0 } })
    }

    func testAnAxialDipoleHasZeroDeclinationEverywhere() {
        // The sharpest test in the file. An axial dipole is symmetric about the
        // spin axis, so the horizontal field points at true north from every
        // point on earth. Any sign or index error in the X or Y summation
        // shows up here immediately — a flipped X reads as 180° everywhere.
        let m = dipole(g10: -30000)
        for lat in stride(from: -80.0, through: 80.0, by: 5.0) {
            for lon in stride(from: -180.0, through: 180.0, by: 15.0) {
                let d = m.declination(lat: lat, lon: lon, decimalYear: 2025.0)
                XCTAssertEqual(d, 0.0, accuracy: 1e-9,
                               "declination at \(lat), \(lon) must be zero")
            }
        }
    }

    func testAnAxialDipolePointsNorthAndDips() {
        let m = dipole(g10: -30000)
        let equator = m.field(lat: 0, lon: 0, decimalYear: 2025.0)
        XCTAssertGreaterThan(equator.x, 0, "horizontal field must point north")
        XCTAssertEqual(equator.y, 0, accuracy: 1e-9)
        XCTAssertEqual(equator.z, 0, accuracy: 1e-6, "no dip on the magnetic equator")
        XCTAssertEqual(equator.inclination, 0, accuracy: 1e-9)

        let north = m.field(lat: 60, lon: 33, decimalYear: 2025.0)
        XCTAssertGreaterThan(north.z, 0, "field dips down in the northern hemisphere")
        XCTAssertGreaterThan(north.inclination, 70)
        XCTAssertLessThan(north.inclination, 80)

        let south = m.field(lat: -60, lon: 33, decimalYear: 2025.0)
        XCTAssertLessThan(south.z, 0, "and up in the southern")
        XCTAssertEqual(south.inclination, -north.inclination, accuracy: 1e-7)
    }

    func testAnAxialDipoleDipMatchesTheClosedFormExactly() {
        // The dip of an axial dipole has an exact answer: in the geocentric
        // frame tan(I) = 2 tan(latitude), and the conversion to the geodetic
        // frame adds (geocentric - geodetic).
        //
        // This is the assertion that would have caught the rotation sign on
        // its own. The declination tests cannot: the rotation mixes X and Z
        // and never touches Y, so an axial dipole reads zero declination
        // whichever way it is rotated, or if it is not rotated at all.
        let m = dipole(g10: -30000)
        let e2 = WMM.f * (2.0 - WMM.f)
        for lat in [0.0, 30.0, 45.0, 60.0, -60.0, 78.0] {
            let latRad = lat * .pi / 180.0
            let rc = WMM.a / (1.0 - e2 * sin(latRad) * sin(latRad)).squareRoot()
            let p = rc * cos(latRad)
            let z = rc * (1.0 - e2) * sin(latRad)
            let geocentric = atan2(z, p)
            let expected = atan(2.0 * tan(geocentric)) * 180.0 / .pi
                + (geocentric - latRad) * 180.0 / .pi
            let got = m.field(lat: lat, lon: 33.0, decimalYear: 2025.0).inclination
            XCTAssertEqual(got, expected, accuracy: 1e-6, "dip at \(lat)°")
        }
    }

    func testATiltedDipoleIsAntisymmetricInLongitude() {
        // g11 tilts the axis inside the 0/180 meridian plane, so the whole
        // configuration mirrors across it and declination must flip sign.
        let m = dipole(g10: -30000, g11: 4000)
        for lat in [-60.0, -15.0, 0.0, 15.0, 60.0] {
            for lon in [10.0, 45.0, 90.0, 135.0, 175.0] {
                let a = m.declination(lat: lat, lon: lon, decimalYear: 2025.0)
                let b = m.declination(lat: lat, lon: -lon, decimalYear: 2025.0)
                XCTAssertEqual(a, -b, accuracy: 1e-9, "at \(lat), ±\(lon)")
            }
        }
    }

    func testIntensityFallsOffWithAltitude() {
        let m = dipole(g10: -30000)
        let ground = m.field(lat: 24.4539, lon: 54.3773, heightMeters: 0, decimalYear: 2025.0)
        let high = m.field(lat: 24.4539, lon: 54.3773, heightMeters: 100_000, decimalYear: 2025.0)
        XCTAssertLessThan(high.totalIntensity, ground.totalIntensity)
        // A dipole falls as 1/r^3: 100 km is about 1.57 % of the radius, so
        // roughly a 4.6 % drop.
        let ratio = high.totalIntensity / ground.totalIntensity
        XCTAssertEqual(ratio, 0.954, accuracy: 0.01)
    }

    func testSecularVariationMovesTheFieldOverTime() {
        var g = [[Double]](repeating: [Double](repeating: 0, count: WMM.maxDegree + 1),
                           count: WMM.maxDegree + 1)
        var h = g, gd = g, hd = g
        g[1][0] = -30000
        h[1][1] = 0
        hd[1][1] = 100          // 100 nT/year of east-tilting drift
        let m = WMM(epoch: 2025.0, name: "TEST", releaseDate: "",
                    g: g, h: h, gDot: gd, hDot: hd)
        let now = m.declination(lat: 24.4539, lon: 54.3773, decimalYear: 2025.0)
        let later = m.declination(lat: 24.4539, lon: 54.3773, decimalYear: 2029.0)
        XCTAssertEqual(now, 0.0, accuracy: 1e-9)
        XCTAssertNotEqual(later, 0.0, "secular variation must actually be applied")
    }

    func testTheModelKnowsWhenItHasExpired() {
        let m = dipole(g10: -30000)
        XCTAssertTrue(m.isValid(at: 2025.0))
        XCTAssertTrue(m.isValid(at: 2029.99))
        XCTAssertFalse(m.isValid(at: 2030.0), "a five-year model expires")
        XCTAssertFalse(m.isValid(at: 2024.9))
        XCTAssertEqual(m.validUntil, 2030.0)
    }

    // MARK: - Decimal year

    func testDecimalYear() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let jan1 = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        XCTAssertEqual(WMM.decimalYear(from: jan1), 2026.0, accuracy: 1e-9)
        let jul2 = cal.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12))!
        XCTAssertEqual(WMM.decimalYear(from: jul2), 2026.5, accuracy: 0.005)
    }

    // MARK: - Coefficient file

    func testCOFParserReadsTheShapeNOAAShips() throws {
        // Values here are invented and mean nothing physically; this checks the
        // parser, not the model. The real file is not in the repository and
        // must never be typed from memory.
        var lines = ["    2025.0            WMM-2025        11/13/2024"]
        for n in 1...WMM.maxDegree {
            for m in 0...n {
                lines.append(" \(n) \(m)  \(Double(n * 10 + m))  \(Double(m))  0.1  0.2")
            }
        }
        lines.append(String(repeating: "9", count: 48))
        let m = try WMM.parse(cof: lines.joined(separator: "\n"))
        XCTAssertEqual(m.epoch, 2025.0)
        XCTAssertEqual(m.name, "WMM-2025")
        XCTAssertEqual(m.releaseDate, "11/13/2024")
        XCTAssertEqual(m.validUntil, 2030.0)
        XCTAssertEqual(m.g[12][7], 127.0)
        XCTAssertEqual(m.h[3][2], 2.0)
        XCTAssertEqual(m.gDot[5][5], 0.1)
        XCTAssertEqual(m.hDot[5][5], 0.2)
    }

    func testCOFParserRefusesAnIncompleteFile() {
        let text = "    2025.0   WMM-2025   11/13/2024\n 1 0 1.0 0.0 0.0 0.0\n999999999999"
        XCTAssertThrowsError(try WMM.parse(cof: text)) { error in
            guard case WMM.LoadError.incomplete(let missing) = error else {
                return XCTFail("expected .incomplete, got \(error)")
            }
            XCTAssertEqual(missing, 89)
        }
    }

    func testCOFParserRefusesGarbage() {
        XCTAssertThrowsError(try WMM.parse(cof: "not a model"))
        XCTAssertThrowsError(try WMM.parse(cof: "2025.0 WMM 1/1/25\n bogus row here\n"))
    }

    // MARK: - The real model, when it is present

    func testTheRealModelIfItIsBundled() throws {
        guard let m = WMM.bundled else {
            throw XCTSkip("WMM.COF is not bundled yet — see docs/wmm-plan.md")
        }
        // Sanity only; the authoritative check is NOAA's test-value file, run
        // by the separate `wmm-validate` CI job.
        XCTAssertEqual(m.g[1][0], -29000, accuracy: 2000, "dipole term is out of family")
        XCTAssertTrue(m.isValid(at: WMM.decimalYear(from: Date())),
                      "the bundled magnetic model has expired — refresh it")
        // The UAE sits at a few degrees east; the UK at a degree or two west.
        let uae = m.declination(lat: 24.4539, lon: 54.3773,
                                decimalYear: WMM.decimalYear(from: Date()))
        XCTAssertTrue((0.0...6.0).contains(uae), "UAE declination out of family: \(uae)")
    }
}
