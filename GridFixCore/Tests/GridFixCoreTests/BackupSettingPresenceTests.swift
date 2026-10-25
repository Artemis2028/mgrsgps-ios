import XCTest
@testable import GridFixCore

final class BackupSettingPresenceTests:XCTestCase {
    private func document(_ settings:String) throws -> Backup.Document {
        try Backup.decodeManifest(Data(("{\"app\":\"GridFix\",\"version\":1,\"settings\":"+settings+"}").utf8))
    }
    func testSparseOlderBackupPreservesEveryAbsentSettingAndExplicitValuesWin() throws {
        var current=Backup.AppSettings()
        current.laneReminderMin=10;current.laneSideCues=false;current.laneGpsAlert=false
        current.hiddenMapTools=["draw"];current.guideAllowance=20;current.nightMode=true;current.declinationOverride=4
        let old=try document(#"{"units":1,"nightMode":false}"#)
        let merged=try Backup.mergingSettings(old.settings,presentKeys:old.settingsKeys,current:current)
        var expected=current;expected.units=1;expected.nightMode=false
        XCTAssertEqual(merged,expected)
        XCTAssertEqual(old.settingsKeys,["units","nightMode"])
        let again=try Backup.importZip(Backup.exportZip(old))
        XCTAssertEqual(again.settingsKeys,old.settingsKeys)
        XCTAssertEqual(try Backup.mergingSettings(again.settings,presentKeys:again.settingsKeys,current:current),expected)
    }
    func testExplicitNullClearsOverrideAndEmptySettingsKeepCurrent() throws {
        var current=Backup.AppSettings();current.declinationOverride=7;current.laneReminderMin=2
        let clear=try document(#"{"declinationOverride":null,"laneReminderMin":0}"#)
        let merged=try Backup.mergingSettings(clear.settings,presentKeys:clear.settingsKeys,current:current)
        XCTAssertNil(merged.declinationOverride);XCTAssertEqual(merged.laneReminderMin,0)
        let empty=try document("{}")
        XCTAssertEqual(try Backup.mergingSettings(empty.settings,presentKeys:empty.settingsKeys,current:current),current)
        XCTAssertThrowsError(try document("null"),"A malformed settings section is rejected before publication")
        let full=Backup.Document(settings:current)
        XCTAssertNil(try Backup.importZip(Backup.exportZip(full)).settingsKeys)
    }
    func testEditingParsedSettingsMarksChangedKeysWithoutMakingMissingFieldsExplicit() throws {
        var old=try document(#"{"units":1}"#)
        old.settings.laneWarningM=50
        XCTAssertEqual(old.settingsKeys,["units","laneWarningM"])
        var current=Backup.AppSettings();current.laneReminderMin=10
        let merged=try Backup.mergingSettings(old.settings,presentKeys:old.settingsKeys,current:current)
        XCTAssertEqual(merged.laneWarningM,50);XCTAssertEqual(merged.laneReminderMin,10)
        let reopened=try Backup.importZip(Backup.exportZip(old))
        XCTAssertEqual(reopened.settingsKeys,old.settingsKeys)
    }

}
