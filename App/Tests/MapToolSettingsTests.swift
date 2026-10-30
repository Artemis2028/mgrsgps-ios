import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class MapToolSettingsTests: XCTestCase {
    func testToolPreferencesReopenAndSurviveOrderedBackupRestoreAndReset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(directory: directory)
        settings.hiddenMapTools = ["ruler","tools","record"]
        await settings.waitForPersistence()
        XCTAssertEqual(AppSettings(directory: directory).hiddenMapTools,settings.hiddenMapTools)
        var doc = Backup.Document(settings: settings.backupSettings)
        doc = try Backup.importZip(Backup.exportZip(doc))
        settings.hiddenMapTools = []
        let message = await BackupCoordinator.restore(doc,waypoints: WaypointStore(directory: directory),fieldData: FieldDataStore(directory: directory),settings: settings)
        XCTAssertTrue(message.hasPrefix("Restored"),message)
        XCTAssertEqual(settings.hiddenMapTools,["ruler","tools","record"])
        await settings.waitForPersistence()
        XCTAssertEqual(AppSettings(directory: directory).hiddenMapTools,settings.hiddenMapTools)
        settings.hiddenMapTools = []
        await settings.waitForPersistence()
        XCTAssertTrue(AppSettings(directory: directory).hiddenMapTools.isEmpty)
    }
    func testPreparedSettingsCannotOverwriteAConcurrentMapToolChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(directory: directory), snapshot = settings.restoreSnapshot()
        var imported = Backup.AppSettings(); imported.hiddenMapTools = ["ruler"]
        let prepared = try snapshot.prepare(imported)
        settings.hiddenMapTools = ["record"]
        XCTAssertFalse(try settings.publishRestore(prepared))
        await settings.waitForPersistence()
        XCTAssertEqual(AppSettings(directory: directory).hiddenMapTools,["record"])
    }
    func testWorkerStartupRetainsSettingsWithoutRewritingTheSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = AppSettings(directory: directory)
        saved.nightMode = true; saved.orientation = 3; saved.mgrsDigits = 6
        saved.hiddenMapTools = ["ruler","record"]; saved.liveActivitiesEnabled = true
        saved.guideMode = 1; saved.guideCorridorM = 55; saved.laneInsideTick = false
        await saved.waitForPersistence()
        let file = directory.appendingPathComponent("settings-v1.json"),bytes = try Data(contentsOf: file)
        let prepared = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return AppSettings.prepareStartup(directory: directory)
        }.value
        let reopened = try AppSettings(startup: prepared)
        XCTAssertTrue(reopened.nightMode); XCTAssertEqual(reopened.orientation,3); XCTAssertEqual(reopened.mgrsDigits,6)
        XCTAssertEqual(reopened.hiddenMapTools,["ruler","record"]); XCTAssertTrue(reopened.liveActivitiesEnabled)
        XCTAssertEqual(reopened.guideMode,1); XCTAssertEqual(reopened.guideCorridorM,55); XCTAssertFalse(reopened.laneInsideTick)
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testPreparedStartupRefusesSettingsCreatedReplacedOrRemovedDuringLoad() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = AppSettings.prepareStartup(directory: directory)
        let saved = AppSettings(directory: directory); saved.nightMode = true; await saved.waitForPersistence()
        XCTAssertThrowsError(try AppSettings(startup: missing))
        let beforeReplacement = AppSettings.prepareStartup(directory: directory)
        saved.orientation = 2; await saved.waitForPersistence()
        XCTAssertThrowsError(try AppSettings(startup: beforeReplacement))
        let beforeRemoval = AppSettings.prepareStartup(directory: directory)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("settings-v1.json"))
        XCTAssertThrowsError(try AppSettings(startup: beforeRemoval))
        let fresh = try AppSettings(startup: AppSettings.prepareStartup(directory: directory))
        XCTAssertFalse(fresh.nightMode); XCTAssertEqual(fresh.orientation,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("settings-v1.json").path))
    }
    func testMalformedSettingsKeepExistingFallbackAndOriginalBytesOnStartup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings-v1.json"),bytes = Data("SYNTHETIC malformed settings CAFÉ".utf8)
        try bytes.write(to: file)
        let prepared = await Task.detached { AppSettings.prepareStartup(directory: directory) }.value
        let settings = try AppSettings(startup: prepared)
        XCTAssertFalse(settings.nightMode); XCTAssertEqual(settings.mgrsDigits,10); XCTAssertFalse(settings.liveActivitiesEnabled)
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
}
