import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class LaneBackupIntegrationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func document() throws -> Backup.Document {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "android-backup-contract",withExtension: "zip"))
        var value = try Backup.importZip(Data(contentsOf: url))
        value.navLanes = [.init(id: "lane",name: "Creek corridor",left: .init(graphicId: value.graphics[0].id),right: .init(points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54)],label: "Road"),backstop: .init(graphicId: "orphan-preserved"),scope: .checkpoint,targetId: value.waypoints[0].id,folder: "Lane folder",createdAt: 100,visible: false)]
        value.settings.laneWarningM = 50
        value.courseHistory = [.init(name: "Lane practice",points: 2,started: 1,total: 10,splits: [5,5])]
        return value
    }
    func testEverySectionReopensAndExistingLaneEditsWinOnRetry() async throws {
        let directory = try directory(), plan = try document()
        let points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory), lanes = NavigationLaneStore(directory: directory)
        let result = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,lanes: lanes)
        XCTAssertFalse(result.contains("stopped"),result); XCTAssertTrue(result.contains("1 navigation lane"))
        let reopened = NavigationLaneStore(directory: directory); await reopened.waitUntilLoaded()
        XCTAssertEqual(reopened.lanes,plan.navLanes)
        XCTAssertEqual(AppSettings(directory: directory).laneWarningM,50)
        XCTAssertTrue(points.folders.contains { $0.name == "Lane folder" })
        XCTAssertEqual(field.document.courseHistory,plan.courseHistory)
        try await lanes.setVisible("lane",true)
        let before = try Data(contentsOf: directory.appendingPathComponent("nav-lanes-v1.json"))
        let retry = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,lanes: lanes)
        XCTAssertFalse(retry.contains("stopped"),retry); XCTAssertFalse(retry.contains("navigation lane"))
        XCTAssertTrue(lanes.lanes[0].visible)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("nav-lanes-v1.json")),before)
        XCTAssertEqual(field.document.tracks.count,plan.tracks.count)
        XCTAssertEqual(points.waypoints.count,plan.waypoints.count)
    }
    func testMalformedLaneOrMissingStoreRejectsBeforeAnyPublication() async throws {
        let directory = try directory(), points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory), lanes = NavigationLaneStore(directory: directory)
        var plan = try document(); plan.navLanes[0].targetId = ""
        let result = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,lanes: lanes)
        XCTAssertTrue(result.contains("No records added"),result)
        XCTAssertTrue(points.waypoints.isEmpty); XCTAssertTrue(field.document.graphics.isEmpty); XCTAssertTrue(field.document.tracks.isEmpty)
        plan = try document()
        let unavailable = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings)
        XCTAssertTrue(unavailable.contains("storage is unavailable"),unavailable)
        XCTAssertTrue(points.waypoints.isEmpty); XCTAssertTrue(field.document.tracks.isEmpty)
    }
    func testLaneFailureReportsEarlierSectionsAndRetryFinishesInAndroidOrder() async throws {
        let directory = try directory(), plan = try document()
        let points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory), lanes = NavigationLaneStore(directory: directory)
        await lanes.waitUntilLoaded()
        let file = directory.appendingPathComponent("nav-lanes-v1.json")
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        let failed = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,lanes: lanes)
        XCTAssertTrue(failed.contains("Already restored"),failed); XCTAssertFalse(failed.contains("course results"))
        XCTAssertEqual(points.waypoints.count,plan.waypoints.count); XCTAssertEqual(field.document.graphics,plan.graphics)
        XCTAssertEqual(field.document.tracks.count,plan.tracks.count); XCTAssertTrue(lanes.lanes.isEmpty)
        XCTAssertTrue(field.document.courseHistory.isEmpty); XCTAssertEqual(settings.laneWarningM,0)
        try FileManager.default.removeItem(at: file)
        let retry = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,lanes: lanes)
        XCTAssertFalse(retry.contains("stopped"),retry); XCTAssertEqual(lanes.lanes,plan.navLanes)
        XCTAssertEqual(field.document.courseHistory,plan.courseHistory); XCTAssertEqual(settings.laneWarningM,50)
        XCTAssertEqual(field.document.tracks.count,plan.tracks.count)
    }
    func testSettingsFailureKeepsDurableLanesAndDoesNotDuplicateOnRetry() async throws {
        let directory = try directory(), plan = try document()
        let points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory), lanes = NavigationLaneStore(directory: directory)
        let file = directory.appendingPathComponent("settings-v1.json")
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        let failed = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,lanes: lanes)
        XCTAssertTrue(failed.contains("1 navigation lane"),failed)
        XCTAssertEqual(lanes.lanes,plan.navLanes); XCTAssertEqual(settings.laneWarningM,0)
        XCTAssertEqual(field.document.courseHistory,plan.courseHistory)
        try FileManager.default.removeItem(at: file)
        let retry = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,lanes: lanes)
        XCTAssertFalse(retry.contains("stopped"),retry); XCTAssertEqual(lanes.lanes.count,1)
        XCTAssertEqual(settings.laneWarningM,50)
    }
}
