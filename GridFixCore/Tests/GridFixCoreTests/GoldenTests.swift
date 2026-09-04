import XCTest
@testable import GridFixCore

/// Every one of these compares this Swift port against vectors generated from
/// the Android app's own math. A failure here means the two phones in the same
/// patrol would read different grids — which is the one bug this app cannot
/// ship, because a wrong grid looks exactly like a right one.
final class GoldenTests: XCTestCase {

    var golden: Golden!

    override func setUpWithError() throws {
        golden = try Golden.load()
        XCTAssertEqual(golden.schema, 1, "fixture schema changed — update the tests")
    }

    func testFixtureIsNotEmpty() {
        XCTAssertGreaterThan(golden.utm.count, 20)
        XCTAssertGreaterThan(golden.mgrsForward.count, 50)
        XCTAssertGreaterThan(golden.mgrsParse.count, 50)
        XCTAssertGreaterThan(golden.distance.count, 10)
        XCTAssertGreaterThan(golden.convergence.count, 50)
    }

    // MARK: - UTM

    func testUTMForwardMatchesTheSharedVectors() {
        let tol = golden.tolerances.utmMeters
        for v in golden.utm {
            let zone = UTM.zone(lat: v.lat, lon: v.lon)
            XCTAssertEqual(zone, v.zone, "zone for \(v.name)")
            XCTAssertEqual(String(UTM.bandLetter(lat: v.lat)), v.band, "band for \(v.name)")
            let p = UTM.forZone(lat: v.lat, lon: v.lon, zone: v.zone, north: v.hemisphere == "N")
            XCTAssertEqual(p.easting, v.easting, accuracy: tol, "easting for \(v.name)")
            XCTAssertEqual(p.northing, v.northing, accuracy: tol, "northing for \(v.name)")
        }
    }

    func testUTMCoordinateRoundsTheSameWayAndroidRounds() {
        for v in golden.utm {
            guard let c = UTM.coordinate(lat: v.lat, lon: v.lon) else {
                return XCTFail("no UTM for \(v.name)")
            }
            XCTAssertEqual(c.zone, v.zone, "zone for \(v.name)")
            XCTAssertEqual(String(c.hemisphere), v.hemisphere, "hemisphere for \(v.name)")
            XCTAssertEqual(Double(c.easting), v.easting, accuracy: 1.0, "easting for \(v.name)")
            XCTAssertEqual(Double(c.northing), v.northing, accuracy: 1.0, "northing for \(v.name)")
        }
    }

    func testUTMIsUndefinedOutsideTheBands() {
        XCTAssertNil(UTM.coordinate(lat: 85.0, lon: 0.0))
        XCTAssertNil(UTM.coordinate(lat: -81.0, lon: 0.0))
        XCTAssertNotNil(UTM.coordinate(lat: 84.0, lon: 0.0))
        XCTAssertNotNil(UTM.coordinate(lat: -80.0, lon: 0.0))
    }

    func testUTMRoundTripsThroughItsOwnInverse() {
        for v in golden.utm {
            let north = v.hemisphere == "N"
            let ll = UTM.inverse(easting: v.easting, northing: v.northing,
                                 zone: v.zone, north: north)
            XCTAssertEqual(ll.lat, v.lat, accuracy: 1e-7, "lat for \(v.name)")
            XCTAssertEqual(ll.lon, v.lon, accuracy: 1e-7, "lon for \(v.name)")
        }
    }

    // MARK: - MGRS

    func testMGRSForwardMatchesTheSharedVectorsExactly() {
        for v in golden.mgrsForward {
            let s = MGRS.string(lat: v.lat, lon: v.lon, digits: v.digits)
            XCTAssertEqual(s, v.mgrs, "\(v.name) at \(v.digits) digits")
        }
    }

    func testMGRSPartsSplitTheWayTheReadoutExpects() {
        for v in golden.mgrsForward {
            guard let p = MGRS.parts(lat: v.lat, lon: v.lon, digits: v.digits) else {
                return XCTFail("no parts for \(v.name)")
            }
            XCTAssertEqual(p.gzd + p.square + p.easting + p.northing, v.mgrs)
            XCTAssertEqual(p.easting.count, v.digits / 2)
            XCTAssertEqual(p.northing.count, v.digits / 2)
            XCTAssertEqual(p.square.count, 2)
            XCTAssertEqual(p.full, "\(p.gzd) \(p.square) \(p.easting) \(p.northing)")
        }
    }

    func testMGRSParseHitsTheCellCentre() {
        let tol = golden.tolerances.latLonDegrees
        for v in golden.mgrsParse {
            guard let p = MGRS.parse(v.mgrs) else { return XCTFail("no parse for \(v.mgrs)") }
            XCTAssertEqual(p.lat, v.centreLat, accuracy: tol, "centre lat for \(v.mgrs)")
            XCTAssertEqual(p.lon, v.centreLon, accuracy: tol, "centre lon for \(v.mgrs)")
        }
    }

    func testMGRSParseCornerHitsTheGridLineIntersection() {
        let tol = golden.tolerances.latLonDegrees
        for v in golden.mgrsParse {
            guard let p = MGRS.parseCorner(v.mgrs) else { return XCTFail("no corner for \(v.mgrs)") }
            XCTAssertEqual(p.lat, v.cornerLat, accuracy: tol, "corner lat for \(v.mgrs)")
            XCTAssertEqual(p.lon, v.cornerLon, accuracy: tol, "corner lon for \(v.mgrs)")
        }
    }

    func testMGRSRoundTripsAtEveryPrecision() {
        for v in golden.mgrsForward {
            guard let p = MGRS.parse(v.mgrs) else { return XCTFail("no parse for \(v.mgrs)") }
            XCTAssertEqual(MGRS.string(lat: p.lat, lon: p.lon, digits: v.digits), v.mgrs,
                           "round trip for \(v.mgrs)")
        }
    }

    func testCornerIsAlwaysSouthWestOfTheCentre() {
        // In UTM the offset is exactly half a cell on both axes. Anything else
        // means one of the two parses picked a different cell.
        for v in golden.mgrsParse {
            guard let c = MGRS.parse(v.mgrs), let sw = MGRS.parseCorner(v.mgrs) else {
                return XCTFail("no parse for \(v.mgrs)")
            }
            let zone = UTM.zone(lat: c.lat, lon: c.lon)
            let north = c.lat >= 0
            let pc = UTM.forZone(lat: c.lat, lon: c.lon, zone: zone, north: north)
            let ps = UTM.forZone(lat: sw.lat, lon: sw.lon, zone: zone, north: north)
            let de = pc.easting - ps.easting
            let dn = pc.northing - ps.northing
            XCTAssertGreaterThan(de, 0.0, "centre must be east of the corner for \(v.mgrs)")
            XCTAssertGreaterThan(dn, 0.0, "centre must be north of the corner for \(v.mgrs)")
            XCTAssertEqual(de, dn, accuracy: 0.5, "offset must be square for \(v.mgrs)")
        }
    }

    func testMGRSRejectsJunk() {
        for bad in ["", "   ", "not a grid", "40", "40R", "40RCQ1", "40RCQ123",
                    "40RII1234", "61RCQ1234", "40ICQ1234", "40RCQ123456789012"] {
            XCTAssertNil(MGRS.parse(bad), "should reject \(bad)")
            XCTAssertNil(MGRS.parseCorner(bad), "should reject \(bad)")
        }
    }

    func testMGRSParseIgnoresSpacingAndCase() {
        guard let a = MGRS.parse("40R CQ 1234 5678"),
              let b = MGRS.parse("40rcq12345678"),
              let c = MGRS.parse("  40R  CQ12345678 ") else {
            return XCTFail("all three spellings must parse")
        }
        XCTAssertEqual(a.lat, b.lat, accuracy: 1e-12)
        XCTAssertEqual(a.lon, b.lon, accuracy: 1e-12)
        XCTAssertEqual(a.lat, c.lat, accuracy: 1e-12)
        XCTAssertEqual(a.lon, c.lon, accuracy: 1e-12)
    }

    func testMGRSTruncatesAndNeverRounds() {
        // A grid that rounds up names a square the shooter is not standing in.
        // Walk east across one 100 m cell and check the digits never jump early.
        let base = MGRS.parse("40R CQ 1234 5678")!
        var previous = ""
        for step in 0..<40 {
            let lon = base.lon + Double(step) * 0.00002
            let s = MGRS.string(lat: base.lat, lon: lon, digits: 6)!
            if !previous.isEmpty {
                XCTAssertGreaterThanOrEqual(s, previous, "grid ran backwards moving east")
            }
            previous = s
        }
    }

    // MARK: - Geodesy

    func testDistanceMatchesTheSharedVectors() {
        let tol = golden.tolerances.distanceMeters
        for v in golden.distance {
            let n = Geodesy.navInfo(fromLat: v.fromLat, fromLon: v.fromLon,
                                    toLat: v.toLat, toLon: v.toLon)
            XCTAssertEqual(n.distanceMeters, v.meters, accuracy: tol, "distance for \(v.name)")
        }
    }

    func testBearingMatchesTheSharedVectors() {
        let tol = golden.tolerances.bearingDegrees
        for v in golden.distance where v.meters > 1.0 {
            let n = Geodesy.navInfo(fromLat: v.fromLat, fromLon: v.fromLon,
                                    toLat: v.toLat, toLon: v.toLon)
            var delta = abs(n.bearingTrue - v.bearing).truncatingRemainder(dividingBy: 360.0)
            if delta > 180.0 { delta = 360.0 - delta }
            XCTAssertLessThan(delta, tol, "bearing for \(v.name): got \(n.bearingTrue), want \(v.bearing)")
        }
    }

    func testDistanceIsSymmetric() {
        for v in golden.distance {
            let there = Geodesy.navInfo(fromLat: v.fromLat, fromLon: v.fromLon,
                                        toLat: v.toLat, toLon: v.toLon)
            let back = Geodesy.navInfo(fromLat: v.toLat, fromLon: v.toLon,
                                       toLat: v.fromLat, toLon: v.fromLon)
            XCTAssertEqual(there.distanceMeters, back.distanceMeters,
                           accuracy: 0.001, "distance for \(v.name) is not symmetric")
        }
    }

    func testZeroDistanceDoesNotProduceNaN() {
        let n = Geodesy.navInfo(fromLat: 24.4539, fromLon: 54.3773,
                                toLat: 24.4539, toLon: 54.3773)
        XCTAssertEqual(n.distanceMeters, 0.0, accuracy: 1e-9)
        XCTAssertFalse(n.bearingTrue.isNaN)
    }

    func testGreatCircleIsCloseButNotEqualToTheEllipsoid() {
        // Documents why the app uses Vincenty: haversine is within half a
        // percent, which is centimetres on a course ring and metres on a leg.
        for v in golden.distance where v.meters > 1000.0 {
            let gc = Geodesy.greatCircleMeters(v.fromLat, v.fromLon, v.toLat, v.toLon)
            let error = abs(gc - v.meters) / v.meters
            XCTAssertLessThan(error, 0.008, "great circle is further off than expected for \(v.name)")
        }
    }

    func testConvergenceMatchesTheSharedVectors() {
        let tol = golden.tolerances.convergenceDegrees
        for v in golden.convergence {
            let c = UTM.gridConvergence(lat: v.lat, lon: v.lon, zone: v.zone)
            XCTAssertEqual(c, v.degrees, accuracy: tol,
                           "convergence at \(v.lat), \(v.lon) in zone \(v.zone)")
        }
    }

    func testConvergenceIsZeroOnTheCentralMeridianAndGrowsOutward() {
        let zone = UTM.zone(lat: 36.0, lon: 45.0)
        XCTAssertEqual(UTM.gridConvergence(lat: 36.0, lon: 45.0), 0.0, accuracy: 1e-9)
        XCTAssertGreaterThan(UTM.gridConvergence(lat: 36.0, lon: 47.5, zone: zone), 0.5)
        XCTAssertLessThan(UTM.gridConvergence(lat: 36.0, lon: 42.5, zone: zone), -0.5)
    }

    // MARK: - Resection

    func testTwoRayFixLandsWhereTheRaysCross() {
        // Two observers 1 km apart on an east-west line, both sighting a point
        // roughly north between them.
        let fix = Geodesy.rayIntersection(lat1: 24.4539, lon1: 54.3773, bearing1True: 45.0,
                                          lat2: 24.4539, lon2: 54.3873, bearing2True: 315.0)
        guard let fix else { return XCTFail("the rays should cross") }
        XCTAssertEqual(fix.lat, 24.4584766, accuracy: 1e-6)
        XCTAssertEqual(fix.lon, 54.3823000, accuracy: 1e-6)
        XCTAssertEqual(fix.dist1, 717.258, accuracy: 0.01)
        XCTAssertEqual(fix.dist2, 717.259, accuracy: 0.01)
    }

    func testTwoRayFixRejectsGeometryAnInstructorWouldReject() {
        // Parallel rays never cross.
        XCTAssertNil(Geodesy.rayIntersection(lat1: 24.4539, lon1: 54.3773, bearing1True: 45.0,
                                             lat2: 24.4539, lon2: 54.3873, bearing2True: 45.0))
        // Diverging rays cross behind the observers, which is not a fix.
        XCTAssertNil(Geodesy.rayIntersection(lat1: 24.4539, lon1: 54.3773, bearing1True: 315.0,
                                             lat2: 24.4539, lon2: 54.3873, bearing2True: 45.0))
    }
}
