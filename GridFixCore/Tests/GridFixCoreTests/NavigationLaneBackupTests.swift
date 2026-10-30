import Combine
import XCTest
@testable import GridFixCore

@MainActor
final class NavigationLaneBackupTests: XCTestCase {
    private func lane(_ id: String = "lane") -> NavLane {
        .init(id: id,name: "Creek",left: .init(graphicId: "phase-left"),right: .init(points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54)],label: "Rte 12"),backstop: .init(graphicId: "phase-back"),scope: .route,targetId: "route",folder: "Patrol",createdAt: 1234,visible: false)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testOptionalAndroidSectionAndZIPRoundTripRetainOrphanedLinksAndVisibility() throws {
        let value = lane(), document = Backup.Document(exportedAt: 1,navLanes: [value])
        let decoded = try Backup.importZip(Backup.exportZip(document))
        XCTAssertEqual(decoded.navLanes,[value])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Backup.encodeManifest(document)) as? [String:Any])
        let record = try XCTUnwrap((root["navLanes"] as? [[String:Any]])?.first)
        XCTAssertEqual(record["scope"] as? String,"route"); XCTAssertEqual(record["targetId"] as? String,"route")
        let right = try XCTUnwrap(record["right"] as? [String:Any])
        XCTAssertEqual(right["points"] as? [[Double]],[[24,54],[24.001,54]])
        XCTAssertTrue(right["graphicId"] is NSNull)
        let legacy = try Backup.decodeManifest(Data(#"{"app":"GridFix","version":1}"#.utf8))
        XCTAssertTrue(legacy.navLanes.isEmpty)
    }
    func testAndroidJSONSectionRejectsMalformedRecordsRatherThanPartiallyReading() throws {
        let valid = Backup.Document(navLanes: [lane()])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Backup.encodeManifest(valid)) as? [String:Any])
        let record = try XCTUnwrap((original["navLanes"] as? [[String:Any]])?.first)
        for mutation in ["scope","targetId","point","line"] {
            var broken = record
            switch mutation {
            case "scope": broken["scope"] = "corridor"
            case "targetId": broken["targetId"] = " "
            case "point": broken["right"] = ["points":[[91,0],[24,0]]]
            default: broken["left"] = ["points":[]]
            }
            var root = original; root["navLanes"] = [record,broken]
            XCTAssertThrowsError(try Backup.decodeManifest(JSONSerialization.data(withJSONObject: root)),mutation)
        }
        for section: Any in ["not an array",[1],NSNull(),Array(repeating: record,count: 10_001)] {
            var root = original; root["navLanes"] = section
            XCTAssertThrowsError(try Backup.decodeManifest(JSONSerialization.data(withJSONObject: root)))
        }
    }
    func testProgrammaticExportRejectsDuplicateIDsAndInvalidLanePoints() throws {
        var document = Backup.Document(navLanes: [lane(),lane()])
        XCTAssertThrowsError(try Backup.exportZip(document))
        document.navLanes = [lane()]; document.navLanes[0].right.points[0] = .init(lat: .nan,lon: 54)
        XCTAssertThrowsError(try Backup.exportZip(document))
        document.navLanes[0] = lane(); document.navLanes[0].right.points = Array(repeating: .init(lat: 24,lon: 54),count: 501)
        XCTAssertThrowsError(try Backup.validate(document))
    }
    func testRestoreIsAdditiveRetainsCurrentEditsAndPublishesOnMain() async throws {
        let directory = try directory(), store = NavigationLaneStore(directory: directory)
        var local = lane(); local.name = "Locally edited"
        let subscription = store.$lanes.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        let first = try await store.restore([local]); XCTAssertEqual(first,1)
        try await store.setVisible(local.id,true)
        let count = try await store.restore([lane(),lane("new")]); XCTAssertEqual(count,1)
        XCTAssertEqual(store.lanes[0].name,"Locally edited"); XCTAssertTrue(store.lanes[0].visible)
        let before = try Data(contentsOf: directory.appendingPathComponent("nav-lanes-v1.json"))
        let retry = try await store.restore([lane(),lane("new")]); XCTAssertEqual(retry,0)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("nav-lanes-v1.json")),before)
        let reopened = NavigationLaneStore(directory: directory); await reopened.waitUntilLoaded()
        XCTAssertEqual(reopened.lanes,store.lanes); withExtendedLifetime(subscription) {}
    }
    func testInvalidRestoreAndAtomicFailureKeepEarlierLaneData() async throws {
        let directory = try directory(), store = NavigationLaneStore(directory: directory)
        _ = try await store.restore([lane()])
        let file = directory.appendingPathComponent("nav-lanes-v1.json"), before = try Data(contentsOf: file)
        var broken = lane("bad"); broken.targetId = ""
        do { _ = try await store.restore([lane("good"),broken]); XCTFail("Partially restored") } catch {}
        XCTAssertEqual(store.lanes.map(\.id),["lane"]); XCTAssertEqual(try Data(contentsOf: file),before)
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        do { _ = try await store.restore([lane("next")]); XCTFail("Atomic rename should fail") } catch {}
        XCTAssertEqual(store.lanes.map(\.id),["lane"])
        try FileManager.default.removeItem(at: file)
        let retry = try await store.restore([lane("next")]); XCTAssertEqual(retry,1)
    }
    func testConfirmedRestorePhaseFinishesWhenCallerIsCancelled() async throws {
        let store = NavigationLaneStore(directory: try directory()), value = lane()
        let task = Task { try await store.restore([value]) }; task.cancel()
        let count = try await task.value
        XCTAssertEqual(count,1); XCTAssertEqual(store.lanes,[value])
    }
    func testReportCarriesPerLegLimitsInSharedTextAndRejectsMisalignment() throws {
        let points = [GeoPoint(lat: 24,lon: 54),.init(lat: 24.001,lon: 54),.init(lat: 24.002,lon: 54)]
        let report = try RouteCard.report(name: "Patrol",points: points,configuration: .init(),legLimits: ["L: Creek · R: Road · BS: Wire",nil]) { _ in 0 }
        XCTAssertEqual(report.rows[0].limits,"L: Creek · R: Road · BS: Wire"); XCTAssertNil(report.rows[1].limits)
        XCTAssertTrue(report.shareText.contains("\n  L: Creek · R: Road · BS: Wire\nLEG 2:"))
        XCTAssertThrowsError(try RouteCard.report(name: "Wrong",points: points,configuration: .init(),legLimits: ["one"]) { _ in 0 })
    }
}
