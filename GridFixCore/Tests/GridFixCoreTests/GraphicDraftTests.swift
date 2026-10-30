import XCTest
@testable import GridFixCore

final class GraphicDraftTests: XCTestCase {
    func testBentRouteEditsPersistWithoutClosingOrChangingIdentity() throws {
        var draft = GraphicDraft(type: "route")
        draft.graphic.name = "  Patrol  "; draft.graphic.folder = "Patrols"
        draft.append(.init(lat: 24,lon: 179.9)); draft.append(.init(lat: 24.1,lon: -179.9))
        draft.selected = 0; draft.insert(.init(lat: 24.05,lon: 180.05))
        XCTAssertEqual(draft.vertices.count,3); XCTAssertEqual(draft.selected,1)
        draft.move(1,to: .init(lat: 24.06,lon: -179.95))
        XCTAssertNil(draft.validationMessage)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FieldDataStore(directory: directory); try store.saveGraphic(draft.saved)
        let restored = FieldDataStore(directory: directory).document.graphics[0]
        XCTAssertEqual(restored.name,"Patrol"); XCTAssertEqual(restored.points,draft.graphic.points)
        XCTAssertEqual(restored.id,draft.graphic.id); XCTAssertNotEqual(restored.points.first,restored.points.last)
        var edited = GraphicDraft(restored); edited.selected = 1; edited.removeSelected()
        XCTAssertEqual(edited.graphic.points.count,2); XCTAssertNil(edited.selected)
        XCTAssertEqual(edited.graphic.createdAt,restored.createdAt)
    }
    func testRingExtentsIncludeFullCircleAcrossTheDateLine() throws {
        let ring = Backup.Graphic(id: "ring",name: "Range",type: "ring",points: [.init(lat: 24,lon: 179.99),.init(lat: 24,lon: -179.99)])
        let bounds = try XCTUnwrap(FieldMapGeometry.bounds(ring.mapExtentPoints))
        XCTAssertLessThan(bounds.south,24); XCTAssertGreaterThan(bounds.north,24)
        XCTAssertGreaterThan(bounds.east-bounds.west,0.039)
        XCTAssertLessThan(bounds.east-bounds.west,0.041)
    }
    func testFixedPointTypesDoNotAcceptExtraVerticesAndCanBeMoved() {
        for (type,count) in [("ring",2),("sector",3),("trp",1),("checkpoint",1),("dp",1),("roadblock",1),("text",1)] {
            var draft = GraphicDraft(type: type)
            for i in 0..<(count+3) { draft.append(.init(lat: 24+Double(i)*0.001,lon: 54)) }
            XCTAssertEqual(draft.graphic.points.count,count,type); XCTAssertFalse(draft.canAppend,type); XCTAssertNil(draft.validationMessage,type)
            draft.move(0,to: .init(lat: 25,lon: 55)); XCTAssertEqual(draft.vertices.first,.init(lat: 25,lon: 55),type)
        }
    }
    func testAllAndroidGraphicTypesHaveCreationRulesAndTacticalBoundaryIsOpen() {
        XCTAssertEqual(GraphicTypes.all.count,30)
        for type in GraphicTypes.all {
            var draft = GraphicDraft(type: type.key)
            XCTAssertNotNil(draft.validationMessage)
            for i in 0..<type.minPoints { draft.append(.init(lat: 24+Double(i)*0.001,lon: 54)) }
            XCTAssertNil(draft.validationMessage,type.key)
            XCTAssertFalse(GraphicTypes.placementHint(type.key).isEmpty)
        }
        XCTAssertFalse(GraphicTypes.isArea("boundary")); XCTAssertNil(GraphicTypes.fixedPoints("boundary"))
    }
    func testBadCoordinatesAndDuplicateLegsCannotBeSavedAndImportedMetadataSurvives() {
        var draft = GraphicDraft(.init(id: "original",name: "PL",type: "phase_line",points: [.init(lat: 24,lon: 54),.init(lat: 24,lon: 54)],folder: "A",affiliation: "hostile",createdAt: 42,echelon: "bn",visible: false))
        XCTAssertNotNil(draft.validationMessage)
        draft.move(1,to: .init(lat: 24.1,lon: 54.1)); XCTAssertNil(draft.validationMessage)
        XCTAssertEqual(draft.saved.affiliation,"hostile"); XCTAssertEqual(draft.saved.echelon,"bn"); XCTAssertFalse(draft.saved.visible)
        draft.move(1,to: .init(lat: .nan,lon: 54)); XCTAssertNotNil(draft.validationMessage)
    }
}
