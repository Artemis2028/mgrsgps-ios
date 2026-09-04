import XCTest
@testable import GridFixCore

/// The grid overlay, tested — which the Canvas version on Android never could
/// be. Every one of these is a rule a map-reading instructor would recognise.
final class MgrsGridTests: XCTestCase {

    // MARK: - Grid zone cells

    func testNorwayWidensZone32AtTheExpenseOf31() {
        // Band V, 56°–64° N: 31V stops at 3° E and 32V runs 3°–12° E, so the
        // Norwegian coast is not split down the middle.
        let cells = MgrsGrid.cells(latSouth: 57, latNorth: 58, lonWest: 1, lonEast: 6)
        let v31 = cells.first { $0.zone == 31 }
        let v32 = cells.first { $0.zone == 32 }
        XCTAssertEqual(v31?.lonEast, 3.0)
        XCTAssertEqual(v32?.lonWest, 3.0)
        XCTAssertEqual(v32?.lonEast, 12.0)
        XCTAssertEqual(v31?.gzd, "31V")
    }

    func testSvalbardHasFourWideZonesAndThreeThatDoNotExist() {
        let cells = MgrsGrid.cells(latSouth: 75, latNorth: 76, lonWest: -5, lonEast: 45)
        let zones = cells.map(\.zone).sorted()
        XCTAssertFalse(zones.contains(32), "32X does not exist")
        XCTAssertFalse(zones.contains(34), "34X does not exist")
        XCTAssertFalse(zones.contains(36), "36X does not exist")
        let byZone = Dictionary(uniqueKeysWithValues: cells.map { ($0.zone, $0) })
        XCTAssertEqual(byZone[31]?.lonWest, 0.0)
        XCTAssertEqual(byZone[31]?.lonEast, 9.0)
        XCTAssertEqual(byZone[33]?.lonEast, 21.0)
        XCTAssertEqual(byZone[35]?.lonEast, 33.0)
        XCTAssertEqual(byZone[37]?.lonEast, 42.0)
        XCTAssertEqual(byZone[33]?.letter, "X")
    }

    func testTheTopBandRunsToEightyFour() {
        let cells = MgrsGrid.cells(latSouth: 80, latNorth: 83, lonWest: 0, lonEast: 5)
        XCTAssertEqual(cells.first?.latSouth, 72.0)
        XCTAssertEqual(cells.first?.latNorth, 84.0, "band X is twelve degrees, not eight")
    }

    func testAnOrdinaryViewportGivesOneCell() {
        let cells = MgrsGrid.cells(latSouth: 24.4, latNorth: 24.5, lonWest: 54.3, lonEast: 54.5)
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells.first?.gzd, "40R")
        XCTAssertTrue(cells.first?.isNorth ?? false)
    }

    func testCellsAreEmptyBelowTheUTMLimit() {
        // UTM stops at 80° S; nothing to draw further down.
        let cells = MgrsGrid.cells(latSouth: -88, latNorth: -85, lonWest: 0, lonEast: 10)
        XCTAssertTrue(cells.allSatisfy { $0.latNorth >= -80 })
    }

    // MARK: - The rule that matters most

    func testAGridLineNeverLeavesItsOwnZone() {
        // A UTM grid line belongs to its zone. Letting one run past the zone
        // meridian draws a line naming a grid square that does not exist —
        // the most common bug in MGRS overlays, and the reason for the clip.
        let r = MgrsGrid.build(latSouth: 24.40, latNorth: 24.60,
                               lonWest: 53.90, lonEast: 54.10,
                               metersPerPoint: 6.0)
        var checked = 0
        for line in r.lines where line.kind != .gzd {
            // Recover the line's zone from its midpoint, not an endpoint — a
            // clipped endpoint sits exactly ON the boundary meridian and would
            // resolve to the neighbour.
            let mid = line.points[line.points.count / 2]
            let zone = UTM.zone(lat: mid.lat, lon: mid.lon)
            let west = UTM.centralMeridian(zone: zone) - 3.0
            let east = west + 6.0
            for p in line.points {
                XCTAssertGreaterThanOrEqual(p.lon, west - 1e-6)
                XCTAssertLessThanOrEqual(p.lon, east + 1e-6)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 50, "the viewport should have produced lines to check")
    }

    func testAViewportOnAZoneBoundaryDrawsBothSides() {
        // 54° E is the 39/40 boundary. Both zones must appear, each with its
        // own grid, meeting at the meridian rather than one running through.
        let r = MgrsGrid.build(latSouth: 24.40, latNorth: 24.60,
                               lonWest: 53.90, lonEast: 54.10,
                               metersPerPoint: 6.0)
        var zones = Set<Int>()
        for line in r.lines where line.kind != .gzd {
            let mid = line.points[line.points.count / 2]
            zones.insert(UTM.zone(lat: mid.lat, lon: mid.lon))
        }
        XCTAssertEqual(zones, [39, 40])
    }

    // MARK: - Interval and work

    func testTheTwoIntervalOverloadsAgree() {
        // metres/pixel with a scale, and metres/point without one, are the same
        // rule stated twice. If they ever disagree the grid coarsens silently.
        for scale in [1.0, 2.0, 3.0] {
            for mpp in stride(from: 0.02, through: 3000.0, by: 7.7) {
                XCTAssertEqual(
                    Grid.chooseInterval(metersPerPixel: mpp, scale: scale),
                    Grid.chooseInterval(metersPerPoint: mpp * scale),
                    "at \(mpp) m/px scale \(scale)"
                )
            }
        }
    }

    func testWorkStaysBoundedFromStreetLevelToWholeContinent() {
        for mpp in [0.05, 0.5, 5.0, 50.0, 500.0, 5000.0, 50000.0] {
            let r = MgrsGrid.build(latSouth: 24.0, latNorth: 25.0,
                                   lonWest: 54.0, lonEast: 55.0,
                                   metersPerPoint: mpp)
            XCTAssertLessThan(r.lines.count, 1200, "line explosion at \(mpp) m/point")
            let points = r.lines.reduce(0) { $0 + $1.points.count }
            XCTAssertLessThan(points, 20000, "vertex explosion at \(mpp) m/point")
        }
    }

    func testZoomedOutFarEnoughOnlyTheZoneBoundariesRemain() {
        let r = MgrsGrid.build(latSouth: -60, latNorth: 60,
                               lonWest: -120, lonEast: 120,
                               metersPerPoint: 40000)
        XCTAssertEqual(r.interval, 0)
        XCTAssertEqual(r.intervalLabel, "GZD")
        XCTAssertTrue(r.lines.allSatisfy { $0.kind == .gzd },
                      "no metre grid should survive at continent scale")
        XCTAssertGreaterThan(r.lines.count, 10)
    }

    func testZoneBoundariesAreNotDrawnTwice() {
        // Adjacent cells share a meridian. Drawing it from both sides doubles
        // its opacity and shows up as a heavier line on one arbitrary edge.
        let r = MgrsGrid.build(latSouth: 20, latNorth: 30,
                               lonWest: 48, lonEast: 66,
                               metersPerPoint: 4000)
        var seen = Set<String>()
        for line in r.lines where line.kind == .gzd {
            let key = line.points.map { "\($0.lat),\($0.lon)" }.joined(separator: ";")
            XCTAssertTrue(seen.insert(key).inserted, "duplicate GZD edge: \(key)")
        }
    }

    // MARK: - Labels

    func testPrincipalDigitsFollowTheMapMarginConvention() {
        // Two principal figures large, subordinate digits small — what is
        // printed up the side of a real sheet.
        XCTAssertEqual(MgrsGrid.principalDigits(4_567_000, interval: 1000), "67")
        XCTAssertEqual(MgrsGrid.principalDigits(4_567_500, interval: 100), "675")
        XCTAssertEqual(MgrsGrid.principalDigits(4_567_560, interval: 10), "6756")
        XCTAssertEqual(MgrsGrid.principalDigits(300_000, interval: 1000), "00")
        XCTAssertEqual(MgrsGrid.principalDigits(4_500_000, interval: 1000), "00")

        let p = MgrsGrid.principalParts(4_567_500, interval: 100)
        XCTAssertEqual(p.principal, "67")
        XCTAssertEqual(p.subordinate, "5")
        XCTAssertEqual(MgrsGrid.principalParts(4_567_000, interval: 1000).subordinate, "",
                       "a 1 km grid has no subordinate digits")
    }

    func testSquareLettersAgreeWithTheGridReadout() {
        // The letters drawn on the map and the letters in the position readout
        // come from different code paths and must never disagree.
        let r = MgrsGrid.build(latSouth: 24.0, latNorth: 25.0,
                               lonWest: 54.0, lonEast: 55.0,
                               metersPerPoint: 300)
        let letterLabels = r.labels.filter { $0.text.count == 2 && $0.text.allSatisfy(\.isLetter) }
        XCTAssertGreaterThan(letterLabels.count, 0, "no 100 km squares were labelled")
        for l in letterLabels {
            let parts = MGRS.parts(lat: l.lat, lon: l.lon, digits: 4)
            XCTAssertEqual(parts?.square, l.text,
                           "square label \(l.text) disagrees with the readout at \(l.lat), \(l.lon)")
        }
    }

    // MARK: - GeoJSON

    func testGeoJSONIsWellFormedAndCarriesWhatTheStyleNeeds() throws {
        let r = MgrsGrid.build(latSouth: 24.40, latNorth: 24.50,
                               lonWest: 54.30, lonEast: 54.45,
                               metersPerPoint: 6.0)
        let data = r.geoJSON()
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "FeatureCollection")
        let features = try XCTUnwrap(obj?["features"] as? [[String: Any]])
        XCTAssertEqual(features.count, r.lines.count + r.labels.count)

        let lines = features.filter {
            ($0["geometry"] as? [String: Any])?["type"] as? String == "LineString"
        }
        XCTAssertEqual(lines.count, r.lines.count)
        for f in lines {
            let props = try XCTUnwrap(f["properties"] as? [String: Any])
            let kind = try XCTUnwrap(props["kind"] as? String)
            XCTAssertTrue(["gzd", "square", "metre"].contains(kind))
            XCTAssertNotNil(props["heavy"] as? Bool)
            let coords = try XCTUnwrap(
                (f["geometry"] as? [String: Any])?["coordinates"] as? [[Double]])
            XCTAssertGreaterThanOrEqual(coords.count, 2)
            for c in coords {
                XCTAssertEqual(c.count, 2)
                XCTAssertTrue((-180.0...180.0).contains(c[0]), "longitude first, then latitude")
                XCTAssertTrue((-90.0...90.0).contains(c[1]))
            }
        }

        for f in features where (f["geometry"] as? [String: Any])?["type"] as? String == "Point" {
            let props = try XCTUnwrap(f["properties"] as? [String: Any])
            let text = try XCTUnwrap(props["text"] as? String)
            let principal = try XCTUnwrap(props["principal"] as? String)
            let subordinate = try XCTUnwrap(props["subordinate"] as? String)
            XCTAssertEqual(principal + subordinate, text)
        }
    }

    func testAnEmptyViewportProducesValidEmptyGeoJSON() throws {
        let r = MgrsGrid.build(latSouth: 10, latNorth: 10, lonWest: 20, lonEast: 20,
                               metersPerPoint: 5)
        let obj = try JSONSerialization.jsonObject(with: r.geoJSON()) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "FeatureCollection")
        XCTAssertEqual((obj?["features"] as? [Any])?.count, 0)
    }

    func testTheAntimeridianDoesNotSwallowTheGrid() {
        // A viewport crossing 180° arrives as west > east. Handled wrong, the
        // whole world reads as "in view" and nothing renders.
        let r = MgrsGrid.build(latSouth: -18, latNorth: -16,
                               lonWest: 179.0, lonEast: -179.0,
                               metersPerPoint: 60)
        XCTAssertGreaterThan(r.lines.count, 0)
        for line in r.lines {
            for p in line.points {
                XCTAssertTrue(abs(p.lon) > 170.0,
                              "a point at \(p.lon) is nowhere near the antimeridian view")
            }
        }
    }
}
