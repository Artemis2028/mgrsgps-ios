import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class OrientationTests: XCTestCase {
    func testAndroidCodesAndNativeMasks() {
        XCTAssertEqual(ScreenOrientation.allCases.map(\.rawValue),[0,1,2,3])
        XCTAssertEqual(ScreenOrientation.portrait.mask(pad: false),.portrait)
        XCTAssertEqual(ScreenOrientation.landscape.mask(pad: false),.landscapeRight)
        XCTAssertEqual(ScreenOrientation.flipped.mask(pad: false),.landscapeLeft)
        XCTAssertEqual(ScreenOrientation.auto.mask(pad: false),.allButUpsideDown)
        XCTAssertEqual(ScreenOrientation.auto.mask(pad: true),.all)
    }
    func testOrientationPersistsAndBackupUsesAndroidIntegers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(directory: directory)
        for mode in ScreenOrientation.allCases {
            settings.orientation = mode.rawValue; await settings.waitForPersistence()
            XCTAssertEqual(AppSettings(directory: directory).orientation,mode.rawValue)
            let backup = settings.backupSettings
            settings.orientation = (mode.rawValue + 1) % 4
            try settings.applyBackup(backup)
            XCTAssertEqual(settings.orientation,mode.rawValue)
        }
        var invalid = settings.backupSettings; invalid.orientation = 4
        XCTAssertThrowsError(try settings.applyBackup(invalid))
    }
}
