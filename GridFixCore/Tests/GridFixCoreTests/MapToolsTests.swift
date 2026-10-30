import XCTest
@testable import GridFixCore

final class MapToolsTests: XCTestCase {
    func testAndroidDeckOrderFilteringAndActiveEscapeControls() {
        XCTAssertEqual(MapTools.visible(hidden: []),["layers","locate","ruler","draw","goto","tools","record"])
        XCTAssertEqual(MapTools.visible(hidden: ["ruler","tools","record"]),["layers","locate","draw","goto"])
        XCTAssertEqual(MapTools.visible(hidden: Set(MapTools.all),active: ["record","draw","ruler","tools"]),["ruler","draw","tools","record"])
        XCTAssertTrue(MapTools.visible(hidden: Set(MapTools.all)).isEmpty)
    }
    func testAndroidCommaContractAndUnknownKeys() throws {
        XCTAssertEqual(MapTools.decode("record, ruler,teleport,,"),["ruler","record"])
        XCTAssertEqual(MapTools.encode(["record","ruler","teleport"]),"ruler,record")
        XCTAssertEqual(MapTools.decode(nil),[])
        let source = Data(#"{"app":"GridFix","version":1,"settings":{"hiddenMapTools":"record, ruler,teleport,,"}}"#.utf8)
        let doc = try Backup.decodeManifest(source)
        XCTAssertEqual(doc.settings.hiddenMapTools,["ruler","record"])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Backup.encodeManifest(doc)) as? [String:Any])
        XCTAssertEqual((root["settings"] as? [String:Any])?["hiddenMapTools"] as? String,"ruler,record")
        XCTAssertEqual(try Backup.importZip(Backup.exportZip(doc)).settings.hiddenMapTools,["ruler","record"])
        XCTAssertTrue(try Backup.decodeManifest(Data(#"{"app":"GridFix","version":1,"settings":{}}"#.utf8)).settings.hiddenMapTools.isEmpty)
    }
}
