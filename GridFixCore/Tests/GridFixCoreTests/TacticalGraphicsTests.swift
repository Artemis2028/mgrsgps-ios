import XCTest
@testable import GridFixCore

/// Tactical graphics as GeoJSON, held to the same table as the Android app.
///
/// The geometry rule has to match the Android KML exporter exactly. The same
/// graphic exported two ways and coming back as two different shapes is a data
/// bug the user only discovers after a round trip through someone else's app.
final class TacticalGraphicsTests: XCTestCase {

    var golden: Golden!

    override func setUpWithError() throws {
        golden = try Golden.load()
    }

    private func g(_ type: String, _ n: Int,
                   name: String = "OBJ FALCON",
                   folder: String = "Base") -> TacGraphic {
        TacGraphic(
            id: "g-\(type)-\(n)",
            name: name,
            type: type,
            points: (0..<n).map { GeoPoint(lat: 24.45 + Double($0) * 0.001,
                                           lon: 54.37 + Double($0) * 0.001) },
            folder: folder,
            affiliation: "friend",
            echelon: "co"
        )
    }

    // MARK: - The shared table

    func testGeometryKindMatchesTheSharedFixture() {
        XCTAssertGreaterThan(golden.graphicGeometry.count, 100)
        for v in golden.graphicGeometry {
            let expected: String? = v.kind == "none" ? nil : v.kind
            XCTAssertEqual(TacGraphic.geometryKind(type: v.type, vertexCount: v.vertexCount),
                           expected, "\(v.type) with \(v.vertexCount) vertices")
        }
    }

    func testTheAreaTypeListMatchesAndroid() {
        // Two lists that drift apart would close the wrong graphics into
        // polygons, silently, on one platform only.
        XCTAssertEqual(GraphicTypes.areaTypes, Set(golden.areaTypes))
    }

    func testEveryTypeInTheFixtureIsATypeThisAppKnows() {
        let known = Set(GraphicTypes.all.map(\.key))
        for v in golden.graphicGeometry {
            XCTAssertTrue(known.contains(v.type), "unknown graphic type \(v.type)")
        }
        XCTAssertEqual(known.count, 30)
    }

    // MARK: - The documents

    func testAGraphicWithNoVerticesProducesNoFeature() {
        XCTAssertNil(TacGraphic.geometryKind(type: "phase_line", vertexCount: 0))
        XCTAssertNil(g("phase_line", 0).geoJSONFeature())
        XCTAssertNil(g("objective", 0).geoJSONFeature())
    }

    func testAPointGraphicIsLongitudeThenLatitude() throws {
        let f = try feature(g("trp", 1))
        let geom = try XCTUnwrap(f["geometry"] as? [String: Any])
        XCTAssertEqual(geom["type"] as? String, "Point")
        let c = try XCTUnwrap(geom["coordinates"] as? [Double])
        XCTAssertEqual(c[0], 54.37, accuracy: 1e-6)
        XCTAssertEqual(c[1], 24.45, accuracy: 1e-6)
    }

    func testALineKeepsItsVerticesInOrder() throws {
        let f = try feature(g("phase_line", 4))
        let geom = try XCTUnwrap(f["geometry"] as? [String: Any])
        XCTAssertEqual(geom["type"] as? String, "LineString")
        let c = try XCTUnwrap(geom["coordinates"] as? [[Double]])
        XCTAssertEqual(c.count, 4)
        XCTAssertEqual(c[0][0], 54.37, accuracy: 1e-6)
        XCTAssertEqual(c[3][0], 54.373, accuracy: 1e-6)
    }

    func testAnAreaClosesItsRing() throws {
        let f = try feature(g("objective", 4))
        let geom = try XCTUnwrap(f["geometry"] as? [String: Any])
        XCTAssertEqual(geom["type"] as? String, "Polygon")
        let rings = try XCTUnwrap(geom["coordinates"] as? [[[Double]]])
        XCTAssertEqual(rings.count, 1)
        let ring = rings[0]
        XCTAssertEqual(ring.count, 5)
        XCTAssertEqual(ring.first![0], ring.last![0], accuracy: 1e-9)
        XCTAssertEqual(ring.first![1], ring.last![1], accuracy: 1e-9)
    }

    func testAnAreaTypeWithTwoVerticesStaysALine() throws {
        let f = try feature(g("objective", 2))
        let geom = try XCTUnwrap(f["geometry"] as? [String: Any])
        XCTAssertEqual(geom["type"] as? String, "LineString")
    }

    func testPropertiesCarryWhatTheStyleFiltersOn() throws {
        let f = try feature(g("boundary", 2))
        let p = try XCTUnwrap(f["properties"] as? [String: Any])
        XCTAssertEqual(p["id"] as? String, "g-boundary-2")
        XCTAssertEqual(p["name"] as? String, "OBJ FALCON")
        XCTAssertEqual(p["tacType"] as? String, "boundary")
        XCTAssertEqual(p["folder"] as? String, "Base")
        XCTAssertEqual(p["affiliation"] as? String, "friend")
        XCTAssertEqual(p["echelon"] as? String, "co")
    }

    func testNastyNamesStillParse() throws {
        let nasty = "OBJ \"FALCON\"\tone\ntwo\\three\r\u{01}"
        let f = try feature(g("objective", 3, name: nasty))
        let p = try XCTUnwrap(f["properties"] as? [String: Any])
        XCTAssertEqual(p["name"] as? String, nasty)
    }

    func testAnOverlayIsOneFeatureCollection() throws {
        let all = [g("phase_line", 3), g("objective", 4), g("trp", 1), g("phase_line", 0)]
        let doc = try XCTUnwrap(
            JSONSerialization.jsonObject(with: all.geoJSON()) as? [String: Any])
        XCTAssertEqual(doc["type"] as? String, "FeatureCollection")
        let features = try XCTUnwrap(doc["features"] as? [[String: Any]])
        XCTAssertEqual(features.count, 3, "the empty graphic must drop out")
        let kinds = features.compactMap {
            ($0["geometry"] as? [String: Any])?["type"] as? String
        }
        XCTAssertEqual(kinds, ["LineString", "Polygon", "Point"])
    }

    func testAnEmptyOverlayIsStillValid() throws {
        let doc = try XCTUnwrap(
            JSONSerialization.jsonObject(with: [TacGraphic]().geoJSON()) as? [String: Any])
        XCTAssertEqual(doc["type"] as? String, "FeatureCollection")
        XCTAssertEqual((doc["features"] as? [Any])?.count, 0)
    }

    func testEveryTypeAtItsMinimumVertexCountProducesAValidFeature() throws {
        for t in GraphicTypes.all {
            let f = try feature(g(t.key, t.minPoints))
            let geom = try XCTUnwrap(f["geometry"] as? [String: Any],
                                     "\(t.key) produced no geometry")
            XCTAssertNotNil(geom["coordinates"])
        }
    }

    private func feature(_ graphic: TacGraphic) throws -> [String: Any] {
        let text = try XCTUnwrap(graphic.geoJSONFeature())
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
