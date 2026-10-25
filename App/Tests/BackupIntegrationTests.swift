import XCTest
import GridFixCore
import UniformTypeIdentifiers
@testable import MGRSGPS

@MainActor
final class BackupIntegrationTests: XCTestCase {
    func testMappedZIP64BackupRestoresNativeStoresAndReopens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "zip64-full-backup",withExtension: "zip"))
        let document = try InterchangeFileReader.backup(file)
        let waypoints = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory)
        let result = BackupCoordinator.restore(document,waypoints: waypoints,fieldData: field,settings: settings)
        XCTAssertFalse(result.contains("stopped"),result)
        XCTAssertEqual(WaypointStore(directory: directory).waypoints[0].id,"contract-vertex")
        let reopened = FieldDataStore(directory: directory)
        XCTAssertEqual(reopened.document.graphics[0].id,"contract-route")
        XCTAssertEqual(reopened.document.tracks[0].pointCount,2)
        XCTAssertEqual(try reopened.points(for: reopened.document.tracks[0].id).count,2)
        XCTAssertEqual(AppSettings(directory: directory).backupSettings,document.settings)
    }
    func testFreshSettingsMatchAndroidDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(AppSettings(directory: directory).backupSettings, Backup.AppSettings())
        XCTAssertEqual(UTType.gridFixGPX.preferredFilenameExtension, "gpx")
        XCTAssertTrue(UTType.gridFixGPX.conforms(to: .xml))
    }

    func testPartialRestoreReportsSavedSectionsAndRetryCompletesWithoutDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "android-backup-contract", withExtension: "zip"))
        let document = try Backup.importZip(Data(contentsOf: file))
        let settings = AppSettings(directory: directory)
        let waypoints = WaypointStore(directory: directory)
        let field = FieldDataStore(directory: directory)
        let blocked = directory.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        let result = BackupCoordinator.restore(document, waypoints: waypoints, fieldData: field, settings: settings)
        XCTAssertTrue(result.contains("Restore stopped"), result)
        XCTAssertTrue(result.contains("Already restored:"), result)
        XCTAssertEqual(field.document.tracks.count, 1)
        XCTAssertTrue(waypoints.waypoints.isEmpty)
        XCTAssertEqual(settings.backupSettings, Backup.AppSettings())
        try FileManager.default.removeItem(at: blocked)
        let retry = BackupCoordinator.restore(document, waypoints: waypoints, fieldData: field, settings: settings)
        XCTAssertFalse(retry.contains("Restore stopped"), retry)
        XCTAssertEqual(field.document.tracks.count, 1)
        XCTAssertEqual(waypoints.waypoints.count, 1)
        XCTAssertEqual(settings.backupSettings, document.settings)
    }

    func testCompleteAndroidRestoreAppliesSettingsAndSurvivesReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "android-backup-contract", withExtension: "zip"))
        let document = try Backup.importZip(Data(contentsOf: file))
        let settings = AppSettings(directory: directory)
        let waypoints = WaypointStore(directory: directory)
        let field = FieldDataStore(directory: directory)
        let result = BackupCoordinator.restore(document, waypoints: waypoints, fieldData: field, settings: settings)
        XCTAssertTrue(result.contains("settings"), result)
        let reopened = AppSettings(directory: directory)
        XCTAssertEqual(reopened.backupSettings, document.settings)
        XCTAssertEqual(WaypointStore(directory: directory).waypoints.first?.sourceRouteId, "contract-route")
        let saved = FieldDataStore(directory: directory)
        XCTAssertEqual(saved.document.tracks.count, 1)
        XCTAssertEqual(saved.document.graphics.count, 1)
        XCTAssertEqual(saved.document.courseHistory.count, 1)
        _ = BackupCoordinator.restore(document, waypoints: waypoints, fieldData: field, settings: settings)
        XCTAssertEqual(waypoints.waypoints.count, 1)
        XCTAssertEqual(field.document.tracks.count, 1)
        let exported = try Backup.importZip(Backup.exportZip(field.backup(waypoints: waypoints.waypoints, folders: waypoints.folders, settings: settings.backupSettings)))
        XCTAssertEqual(exported.settings, document.settings)
        XCTAssertEqual(exported.trackFiles, document.trackFiles)
    }

    func testGpxImportDoesNotResetDeviceSettingsOrNavigationSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(directory: directory)
        settings.mgrsDigits = 6; settings.pacePer100m = 72; settings.northRef = .magnetic
        let waypoints = WaypointStore(directory: directory)
        let selected = waypoints.add(WaypointDraft(name: "Chosen", lat: 24, lon: 54))
        waypoints.select(selected.id)
        let document = try GPX.parse("<gpx><wpt lat=\"25\" lon=\"55\"><name>Imported</name></wpt></gpx>")
        _ = BackupCoordinator.restore(document, waypoints: waypoints, fieldData: FieldDataStore(directory: directory), settings: settings)
        XCTAssertEqual(settings.mgrsDigits, 6)
        XCTAssertEqual(settings.pacePer100m, 72)
        XCTAssertEqual(settings.northRef, .magnetic)
        XCTAssertEqual(waypoints.selectedId, selected.id)
    }
}
