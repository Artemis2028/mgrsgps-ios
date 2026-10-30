import XCTest
@testable import GridFixCore

final class WaypointMarkerDescriptionTests: XCTestCase {
    func testEveryImportedShapeAndCharacterOverridesHiddenCatalogFrameAndEchelon() {
        var checked = 0
        for shape in MilGpsShape.allCases {
            let characters: [String?] = shape == .cross ? [nil] : [nil] + MilGpsSymbols.characters.map(Optional.some)
            for character in characters {
                let code = MilGpsSymbols.encode(shape: shape,character: character)
                let spoken = character == "!" ? "exclamation mark" : character == "?" ? "question mark" : character
                let expected = [shape.label,spoken,"marker"].compactMap { $0 }.joined(separator: " ")
                XCTAssertEqual(WaypointMarkerDescription.text(symbol: "nato_h_inf",affiliation: "friendly",echelon: "bn",metadata: .init(color: "cyan",milgpsSymbolCode: code)),expected)
                XCTAssertEqual(WaypointMarkerDescription.text(symbol: "flag",metadata: .init(milgpsSymbolCode: code)),expected)
                checked += 1
            }
        }
        XCTAssertEqual(checked,157)
    }
    func testEntireUnitCatalogUsesItsOwnAffiliationAndVisibleEchelonExactlyOnce() {
        for key in MilitarySymbols.unitKeys {
            for echelon in MilitarySymbols.echelons {
                let expected = MilitarySymbols.label(key) + (echelon.key.isEmpty ? "" : ", " + echelon.label)
                XCTAssertEqual(WaypointMarkerDescription.text(symbol: key,affiliation: "hostile",echelon: echelon.key),expected,key)
            }
        }
    }
    func testBasicFramesAndTaskPathsDoNotInventHiddenEchelons() {
        XCTAssertEqual(WaypointMarkerDescription.text(symbol: "flag",affiliation: "hostile",echelon: "plt"),"Flag, Hostile, Platoon")
        for task in MilitarySymbols.tasks {
            XCTAssertEqual(WaypointMarkerDescription.text(symbol: task.key,affiliation: "friendly",echelon: "bn"),task.label + ", Friendly")
        }
    }
    func testInvalidImportedCodesFallBackToVisibleSymbolAndUnknownKeysRemainExplicit() {
        for code in [-1,1,999,1001,5000,Int.max] {
            XCTAssertNil(MilGpsSymbols.decode(code))
            XCTAssertEqual(WaypointMarkerDescription.text(symbol: "flag",affiliation: "hostile",echelon: "plt",metadata: .init(milgpsSymbolCode: code)),"Flag, Hostile, Platoon")
        }
        XCTAssertEqual(WaypointMarkerDescription.text(symbol: "legacy_custom"),"Unrecognized symbol legacy_custom")
        XCTAssertEqual(WaypointMarkerDescription.text(symbol: "nato_x_custom",affiliation: "neutral"),"Unrecognized symbol nato_x_custom, Neutral")
        XCTAssertEqual(WaypointMarkerDescription.text(symbol: ""),"Unrecognized marker")
    }
    func testPhoneDescriptionSurvivesActualWatchSnapshotEncodingAndReplacement() throws {
        let metadata = WaypointMetadata(color: "cyan",milgpsSymbolCode: MilGpsSymbols.encode(shape: .circle,character: "6"))
        var point = Waypoint(id: "imported",name: "OP CAFÉ",lat: 24,lon: 54,symbol: "flag",affiliation: "hostile",echelon: "bn",metadata: metadata)
        let scene = WatchMapSnapshot.build(waypoints: [point],folders: [],document: .init())
        let decoded = try XCTUnwrap(WatchMapSnapshot.decode(XCTUnwrap(scene.encoded())))
        XCTAssertEqual(WaypointMarkerDescription.text(try XCTUnwrap(decoded.waypoints.first)),"Circle 6 marker")
        XCTAssertEqual(WaypointMarkerDescription.text(point),"Circle 6 marker")
        point.metadata.milgpsSymbolCode = nil
        let replaced = WatchMapSnapshot.build(waypoints: [point],folders: [],document: .init())
        XCTAssertEqual(WaypointMarkerDescription.text(try XCTUnwrap(replaced.waypoints.first)),"Flag, Hostile, Battalion")
        XCTAssertTrue(WatchMapSnapshot.build(waypoints: [],folders: [],document: .init()).waypoints.isEmpty)
    }

}
