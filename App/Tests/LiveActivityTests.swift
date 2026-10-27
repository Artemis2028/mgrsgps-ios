import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor private final class TestActivityDriver: FieldActivityDriver {
    var authorized=true;var supported=true
    var values:[FieldActivityReference]=[]
    var starts=0;var updates:[FieldActivityState]=[];var ended:[String]=[]
    var onStart:(()->Void)?
    func current()->[FieldActivityReference] { values }
    func start(_ session:FieldActivitySession) async throws -> Bool {
        starts+=1;values.append(.init(id:"activity-\(starts)",sessionID:session.id,kind:session.kind));onStart?();return true
    }
    func update(_ activity:FieldActivityReference,state:FieldActivityState) async { updates.append(state) }
    func end(_ activity:FieldActivityReference) async { ended.append(activity.id);values.removeAll{$0.id==activity.id} }
}

@MainActor final class LiveActivityTests:XCTestCase {
    private func session(_ id:String="track",kind:String="recording")->FieldActivitySession {
        .init(id:id,kind:kind,state:.init(title:"Patrol",status:"Recording",detail:"4 saved points",grid:nil,fixDate:nil,fixExpiresAt:nil,startedAt:Date(timeIntervalSince1970:100),night:false))
    }
    func testDefaultOffAndBackupRestoreNeverEnablesOrClearsLocalConsent() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let settings=AppSettings(directory:directory)
        XCTAssertFalse(settings.liveActivitiesEnabled)
        settings.liveActivitiesEnabled=true;await settings.waitForPersistence()
        XCTAssertTrue(AppSettings(directory:directory).liveActivitiesEnabled)
        let snapshot=settings.restoreSnapshot(), prepared=try snapshot.prepare(Backup.AppSettings())
        XCTAssertTrue(try settings.publishRestore(prepared));XCTAssertTrue(settings.liveActivitiesEnabled)
        XCTAssertTrue(AppSettings(directory:directory).liveActivitiesEnabled)
        try settings.applyBackup(.init());XCTAssertTrue(AppSettings(directory:directory).liveActivitiesEnabled)
        let stale=try settings.restoreSnapshot().prepare(.init());settings.liveActivitiesEnabled=false
        XCTAssertFalse(try settings.publishRestore(stale));await settings.waitForPersistence();XCTAssertFalse(AppSettings(directory:directory).liveActivitiesEnabled)
    }
    func testOptOutAndSystemDenialEndExistingActivitiesWithoutStarting() async {
        let d=TestActivityDriver();d.values=[.init(id:"old",sessionID:"track",kind:"recording")]
        var enabled=false
        let m=LiveActivityManager(driver:d,enabled:{enabled},foreground:{true},sessions:{[self.session()]})
        m.refresh();await m.waitForUpdates();XCTAssertEqual(d.ended,["old"]);XCTAssertEqual(d.starts,0)
        enabled=true;d.authorized=false;m.refresh();await m.waitForUpdates();XCTAssertEqual(d.starts,0)
        XCTAssertTrue(m.message.contains("disabled"))
    }
    func testBackgroundDefersNewActivityButUpdatesAndEndsAnExistingOne() async {
        let d=TestActivityDriver();var foreground=false;var sessions=[session()]
        let m=LiveActivityManager(driver:d,enabled:{true},foreground:{foreground},sessions:{sessions})
        m.refresh();await m.waitForUpdates();XCTAssertEqual(d.starts,0)
        foreground=true;m.refresh();await m.waitForUpdates();XCTAssertEqual(d.starts,1)
        foreground=false;sessions[0].state.status="Saving track";m.refresh();await m.waitForUpdates()
        XCTAssertEqual(d.updates.last?.status,"Saving track")
        sessions=[];m.refresh();await m.waitForUpdates();XCTAssertTrue(d.values.isEmpty)
    }
    func testOptOutWhileStartIsPendingGetsReconciledAndDuplicatesAreRemoved() async {
        let d=TestActivityDriver();var enabled=true
        let m=LiveActivityManager(driver:d,enabled:{enabled},foreground:{true},sessions:{[self.session()]})
        d.onStart={enabled=false;m.refresh()}
        m.refresh();await m.waitForUpdates();XCTAssertEqual(d.starts,1);XCTAssertTrue(d.values.isEmpty)
        enabled=true;d.onStart=nil
        d.values=[.init(id:"a",sessionID:"track",kind:"recording"),.init(id:"b",sessionID:"track",kind:"recording"),.init(id:"orphan",sessionID:"old",kind:"navigation")]
        m.refresh();await m.waitForUpdates();XCTAssertEqual(d.values.count,1);XCTAssertEqual(d.values.first?.id,"a")
    }
    func testUserDismissalDoesNotRecreateUntilSessionChanges() async {
        let d=TestActivityDriver();var sessions=[session()]
        let m=LiveActivityManager(driver:d,enabled:{true},foreground:{true},sessions:{sessions})
        m.refresh();await m.waitForUpdates();XCTAssertEqual(d.starts,1)
        d.values=[];m.refresh();await m.waitForUpdates();XCTAssertEqual(d.starts,1)
        XCTAssertTrue(m.message.contains("dismissed"))
        sessions=[session("next")];m.refresh();await m.waitForUpdates();XCTAssertEqual(d.starts,2)
    }
    func testFreshnessCannotReviveAfterClockRollbackOrReboot() {
        var state=session().state
        state.fixDate=Date(timeIntervalSince1970:100);state.fixExpiresAt=Date(timeIntervalSince1970:115);state.fixUptime=1000
        XCTAssertTrue(state.hasFreshFix(at:Date(timeIntervalSince1970:105),uptime:1005))
        XCTAssertFalse(state.hasFreshFix(at:Date(timeIntervalSince1970:90),uptime:1020))
        XCTAssertFalse(state.hasFreshFix(at:Date(timeIntervalSince1970:105),uptime:10))
        state.startedAt=nil
        XCTAssertFalse(state.hasFreshFix(at:Date(timeIntervalSince1970:105),uptime:1011))
    }
}
