import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class GridNamingIntegrationTests: XCTestCase {
    func testGridNamePersistsAndCrossPlatformBackupRestoresIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(directory: directory)
        XCTAssertEqual(settings.gridName,"MGRS")
        settings.gridSystem = 1; await settings.waitForPersistence()
        XCTAssertEqual(AppSettings(directory: directory).gridName,"USNG")
        let backup = settings.backupSettings
        XCTAssertEqual(backup.gridSystem,1)
        settings.gridSystem = 0
        try settings.applyBackup(backup)
        XCTAssertEqual(settings.gridName,"USNG")
        XCTAssertEqual(AppSettings(directory: directory).gridName,"USNG")
        var invalid = backup; invalid.gridSystem = 2
        XCTAssertThrowsError(try settings.applyBackup(invalid))
        XCTAssertEqual(settings.gridName,"USNG")
    }
}
