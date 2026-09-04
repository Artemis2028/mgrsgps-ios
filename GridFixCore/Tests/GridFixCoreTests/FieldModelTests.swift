import XCTest
@testable import GridFixCore

/// Everything that is not coordinate math: the grid interval rule, folder
/// naming, phonetic spelling and the readout strings. All of it has an exact
/// Android counterpart, so these are written to the same expectations.
final class FieldModelTests: XCTestCase {

    // MARK: - Grid interval

    func testIntervalIsTheFinestGridThatClearsMinimumSpacing() {
        // 48 points of screen per line: at scale 2 that is 96 pixels.
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: 0.05, scale: 2), 10)
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: 1.0, scale: 2), 100)
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: 10.0, scale: 2), 1000)
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: 100.0, scale: 2), 10000)
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: 1000.0, scale: 2), 100000)
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: 5000.0, scale: 2), 0)
    }

    func testIntervalSurvivesNonsenseInput() {
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: 0.0, scale: 2), 0)
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: -1.0, scale: 2), 0)
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: 1.0, scale: 0), 0)
        XCTAssertEqual(Grid.chooseInterval(metersPerPixel: .nan, scale: 2), 0)
    }

    func testADenserScreenNeverAsksForAFinerGrid() {
        for mpp in stride(from: 0.1, through: 500.0, by: 7.3) {
            let coarse = Grid.chooseInterval(metersPerPixel: mpp, scale: 1)
            let dense = Grid.chooseInterval(metersPerPixel: mpp, scale: 3)
            XCTAssertGreaterThanOrEqual(dense == 0 ? Int.max : dense,
                                        coarse == 0 ? Int.max : coarse,
                                        "at \(mpp) m per point")
        }
    }

    func testEveryIntervalTheChooserCanReturnHasALabel() {
        let named = [0: "GZD", 100000: "100 km", 10000: "10 km",
                     1000: "1 km", 100: "100 m", 10: "10 m"]
        var seen = Set<Int>()
        var mpp = 0.01
        while mpp < 100000.0 {
            seen.insert(Grid.chooseInterval(metersPerPixel: mpp, scale: 2))
            mpp *= 1.2
        }
        XCTAssertGreaterThan(seen.count, 3)
        for i in seen {
            XCTAssertEqual(Grid.intervalLabel(i), named[i], "interval \(i)")
        }
    }

    // MARK: - Folders

    func testLegacyFolderNamesCollapseIntoBase() {
        XCTAssertEqual(Folders.canonical("Waypoints"), "Base")
        XCTAssertEqual(Folders.canonical("Graphics"), "Base")
        XCTAssertEqual(Folders.canonical(""), "Base")
        XCTAssertEqual(Folders.canonical("   "), "Base")
        XCTAssertEqual(Folders.canonical(nil), "Base")
        XCTAssertEqual(Folders.canonical("  Recon  "), "Recon")
        XCTAssertEqual(Folders.canonical("waypoints"), "waypoints", "the collapse is case sensitive")
    }

    func testReservedNamesWarnBeforeTheUserCommits() {
        XCTAssertEqual(Folders.reservedHint("Waypoints"),
                       "\"Waypoints\" is a reserved name — this goes into Base")
        XCTAssertEqual(Folders.reservedHint("Graphics"),
                       "\"Graphics\" is a reserved name — this goes into Base")
        XCTAssertNil(Folders.reservedHint(""))
        XCTAssertNil(Folders.reservedHint("Base"))
        XCTAssertNil(Folders.reservedHint("Recon"))
    }

    func testFolderMatchingIsCaseInsensitiveAgainstFoldersInUse() {
        let known = ["Base", "Recon", "OBJ Falcon"]
        XCTAssertEqual(Folders.match(known: known, raw: "recon"), "Recon")
        XCTAssertEqual(Folders.match(known: known, raw: "RECON"), "Recon")
        XCTAssertEqual(Folders.match(known: known, raw: "obj falcon"), "OBJ Falcon")
        XCTAssertEqual(Folders.match(known: known, raw: "Ambush"), "Ambush")
        XCTAssertEqual(Folders.match(known: known, raw: "Waypoints"), "Base")
        XCTAssertEqual(Folders.match(known: [], raw: nil), "Base")
    }

    // MARK: - Phonetic

    func testGridSpellsForRadio() {
        XCTAssertEqual(Phonetic.spellGroup("VP"), "Victor Papa")
        XCTAssertEqual(Phonetic.spellGroup("18T"), "One Eight Tango")
        XCTAssertEqual(Phonetic.mgrs("18T VP 3808 9755"),
                       "One Eight Tango · Victor Papa · Tree Eight Zero Eight · Niner Seven Fife Fife")
        XCTAssertEqual(Phonetic.mgrsSpeech("18T VP"),
                       "One Eight Tango, Victor Papa")
    }

    func testMilitaryDigitsAreUsedNotPlainEnglish() {
        XCTAssertEqual(Phonetic.spellGroup("34590"), "Tree Fower Fife Niner Zero")
    }

    func testSpellingIgnoresPunctuationAndExtraSpaces() {
        XCTAssertEqual(Phonetic.mgrs("  40R   BN  "), "Fower Zero Romeo · Bravo November")
        XCTAssertEqual(Phonetic.spellGroup(""), "")
    }

    // MARK: - Readout strings

    func testDistanceReadout() {
        XCTAssertEqual(Format.distance(meters: 500, unit: .metric), "500 m")
        XCTAssertEqual(Format.distance(meters: 1500, unit: .metric), "1.50 km")
        XCTAssertEqual(Format.distance(meters: 15000, unit: .metric), "15.0 km")
        XCTAssertEqual(Format.distance(meters: 100, unit: .imperial), "328 ft")
        XCTAssertEqual(Format.distance(meters: 500, unit: .imperial), "0.31 mi")
        XCTAssertEqual(Format.distance(meters: 1000, unit: .nautical), "1000 m")
        XCTAssertEqual(Format.distance(meters: 3704, unit: .nautical), "2.00 NM")
    }

    func testBearingReadout() {
        XCTAssertEqual(Format.angle(degrees: 0, unit: .degrees), "000°")
        XCTAssertEqual(Format.angle(degrees: 45.4, unit: .degrees), "045°")
        XCTAssertEqual(Format.angle(degrees: 359.6, unit: .degrees), "000°",
                       "360 must wrap to 000, not print 360")
        XCTAssertEqual(Format.angle(degrees: 90, unit: .mils), "1600 mils")
        XCTAssertEqual(Format.angle(degrees: 360, unit: .mils), "0 mils")
    }

    func testLatLonReadoutInAllThreeFormats() {
        XCTAssertEqual(Format.latLon(lat: 24.4539, lon: 54.3773, format: .decimalDegrees),
                       "24.45390° N   54.37730° E")
        XCTAssertEqual(Format.latLon(lat: 24.4539, lon: 54.3773, format: .degreesMinutes),
                       "24° 27.234' N   54° 22.638' E")
        XCTAssertEqual(Format.latLon(lat: 24.4539, lon: 54.3773, format: .degreesMinutesSeconds),
                       "24° 27' 14.0\" N   54° 22' 38.3\" E")
    }

    func testSecondsCarryInsteadOfPrintingSixty() {
        // 0.99999 degrees is 59.9964 minutes: it must roll to 1 degree flat.
        XCTAssertEqual(Format.latLon(lat: 0.99999, lon: 0.0, format: .degreesMinutesSeconds),
                       "1° 00' 00.0\" N   0° 00' 00.0\" E")
    }

    func testSingleDigitSecondsAndMinutesKeepTheirLeadingZero() {
        // Regression. String(format: "%04.1f", 0.0) pads with a SPACE on
        // Darwin and a ZERO in Kotlin, so the two platforms printed a
        // coordinate that differed by one character. Padding is explicit now.
        XCTAssertEqual(Format.latLon(lat: 1.001, lon: 0.0, format: .degreesMinutesSeconds),
                       "1° 00' 03.6\" N   0° 00' 00.0\" E")
        XCTAssertEqual(Format.latLon(lat: 1.09, lon: 0.0, format: .degreesMinutes),
                       "1° 05.400' N   0° 00.000' E")
    }

    func testDecimalPaddingIsExplicitNotLeftToTheFormatter() {
        XCTAssertEqual(Format.padDecimal(0.0, intDigits: 2, decimals: 1), "00.0")
        XCTAssertEqual(Format.padDecimal(3.6, intDigits: 2, decimals: 1), "03.6")
        XCTAssertEqual(Format.padDecimal(14.0, intDigits: 2, decimals: 1), "14.0")
        XCTAssertEqual(Format.padDecimal(5.5, intDigits: 2, decimals: 3), "05.500")
        XCTAssertEqual(Format.padDecimal(27.234, intDigits: 2, decimals: 3), "27.234")
        XCTAssertFalse(Format.padDecimal(0.0, intDigits: 2, decimals: 1).contains(" "),
                       "a space where a zero belongs is the bug this guards")
    }

    func testSouthAndWestGetTheRightHemisphere() {
        XCTAssertEqual(Format.latLon(lat: -33.8568, lon: -70.6693, format: .decimalDegrees),
                       "33.85680° S   70.66930° W")
    }

    func testUTMReadout() {
        let u = UTM.Coordinate(zone: 40, hemisphere: "N", easting: 334120, northing: 2707000)
        XCTAssertEqual(Format.utm(u), "40N 334120E 2707000N")
        XCTAssertEqual(Format.utm(nil), "—")
    }

    func testDateTimeGroupIsZulu() {
        // 2026-08-24 14:35 UTC
        let d = Date(timeIntervalSince1970: 1_787_582_100)
        XCTAssertEqual(Format.dtg(d), "241435Z AUG 26")
    }

    func testAltitudeAccuracyAndSpeed() {
        XCTAssertEqual(Format.altitude(meters: 100, unit: .metric), "100 m")
        XCTAssertEqual(Format.altitude(meters: 100, unit: .imperial), "328 ft")
        XCTAssertEqual(Format.accuracy(meters: 4.4, unit: .metric), "±4 m")
        XCTAssertEqual(Format.speed(metersPerSecond: 10, unit: .metric), "36.0 km/h")
        XCTAssertEqual(Format.speed(metersPerSecond: 10, unit: .imperial), "22.4 mph")
        XCTAssertEqual(Format.speed(metersPerSecond: 10, unit: .nautical), "19.4 kn")
    }

    // MARK: - Map models

    func testImageQuadRefusesAnythingButFourCorners() {
        let c = ImageQuad.Corner(lat: 0, lon: 0)
        XCTAssertNotNil(ImageQuad(id: "a", name: "n", corners: Array(repeating: c, count: 4)))
        for count in [0, 1, 3, 5] {
            XCTAssertNil(ImageQuad(id: "a", name: "n", corners: Array(repeating: c, count: count)),
                         "\(count) corners must be refused")
        }
    }

    func testMapModelsSurviveARoundTripThroughJSON() throws {
        let pack = OfflinePack(layerKey: "topo", latNorth: 25, latSouth: 24,
                               lonWest: 54, lonEast: 55, minZoom: 10, maxZoom: 15)
        let data = try JSONEncoder().encode(pack)
        XCTAssertEqual(try JSONDecoder().decode(OfflinePack.self, from: data), pack)

        let layer = BaseLayerDescriptor(key: "topo", label: "Topo", attribution: "x",
                                        maxDownloadZoom: 15, bulkDownload: true)
        let ld = try JSONEncoder().encode(layer)
        XCTAssertEqual(try JSONDecoder().decode(BaseLayerDescriptor.self, from: ld), layer)
    }
}
