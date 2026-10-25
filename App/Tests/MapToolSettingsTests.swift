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
        XCTAssertEqual(AppSettings(directory: directory).hiddenMapTools,settings.hiddenMapTools)
        var doc = Backup.Document(settings: settings.backupSettings)
        doc = try Backup.importZip(Backup.exportZip(doc))
        settings.hiddenMapTools = []
        let message = await BackupCoordinator.restore(doc,waypoints: WaypointStore(directory: directory),fieldData: FieldDataStore(directory: directory),settings: settings)
        XCTAssertTrue(message.hasPrefix("Restored"),message)
        XCTAssertEqual(settings.hiddenMapTools,["ruler","tools","record"])
        XCTAssertEqual(AppSettings(directory: directory).hiddenMapTools,settings.hiddenMapTools)
        settings.hiddenMapTools = []
        XCTAssertTrue(AppSettings(directory: directory).hiddenMapTools.isEmpty)
    }
    func testPreparedSettingsCannotOverwriteAConcurrentMapToolChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(directory: directory), snapshot = settings.restoreSnapshot()
        var imported = Backup.AppSettings(); imported.hiddenMapTools = ["ruler"]
        let prepared = try snapshot.prepare(imported)
        settings.hiddenMapTools = ["record"]
        XCTAssertFalse(try settings.publishRestore(prepared))
        XCTAssertEqual(AppSettings(directory: directory).hiddenMapTools,["record"])
    }
}
