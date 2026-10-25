import XCTest
@testable import GridFixCore

final class GridNamingTests: XCTestCase {
    func testLabelledGridEntryKeepsOriginalCoordinateAndPrecisionValidation() throws {
        var entry = WaypointCoordinateDraft(lat: 24.453912345,lon: 54.377312345)
        let original = try XCTUnwrap(entry.position)
        entry.grid = "usng: " + entry.grid
        XCTAssertEqual(entry.position,original)
        entry.grid = "MGRS 40R BN 3412 0700"
        XCTAssertNotNil(entry.position)
        entry.grid = "USNG 40R BN 341 0700"
        XCTAssertNil(entry.position)
    }
    func testAndroidGridSystemBackupAndLegacyDefault() throws {
        var settings = Backup.AppSettings(); settings.gridSystem = 1
        let data = try Backup.encodeManifest(.init(settings: settings))
        XCTAssertEqual(try Backup.decodeManifest(data).settings.gridSystem,1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var values = try XCTUnwrap(object["settings"] as? [String: Any]); values.removeValue(forKey: "gridSystem"); object["settings"] = values
        XCTAssertEqual(try Backup.decodeManifest(JSONSerialization.data(withJSONObject: object)).settings.gridSystem,0)
        settings.gridSystem = 2
        XCTAssertThrowsError(try Backup.validate(.init(settings: settings)))
    }
}
