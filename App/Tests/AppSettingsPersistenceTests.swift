import GridFixCore
import XCTest
@testable import MGRSGPS

private actor SettingsStageGate {
    private var armed = false,fail = false
    private(set) var arrived = false
    private var continuation: CheckedContinuation<Void,Never>?
    private(set) var calls = 0
    func arm(fail: Bool = false) { armed = true; arrived = false; self.fail = fail }
    func hold() async throws {
        calls += 1
        guard armed else { return }
        armed = false; arrived = true
        await withCheckedContinuation { continuation = $0 }
        if fail { throw CocoaError(.fileWriteOutOfSpace) }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class AppSettingsPersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    private func store(_ dir: URL,_ gate: SettingsStageGate) -> AppSettings {
        AppSettings(directory: dir,stage: { snapshot,file in
            let prepared = try await AppSettings.stageSettings(snapshot,to: file)
            try await gate.hold(); return prepared
        })
    }
    private func awaitStage(_ gate: SettingsStageGate) async throws {
        let end = Date().addingTimeInterval(5)
        while !(await gate.arrived),Date() < end { try await Task.sleep(nanoseconds: 1_000_000) }
        let arrived = await gate.arrived; XCTAssertTrue(arrived)
    }
    func testRapidChangesCoalesceAndOnlyLatestSnapshotSurvivesReopen() async throws {
        let dir = try directory(),gate = SettingsStageGate(),settings = store(dir,gate)
        await gate.arm(); settings.mgrsDigits = 4
        try await awaitStage(gate)
        for i in 0..<100 { settings.pacePer100m = i+1; settings.guideAllowance = i%90+1 }
        settings.nightMode = true; settings.orientation = 3; settings.mgrsDigits = 6
        settings.liveActivitiesEnabled = true; settings.hiddenMapTools = ["record","ruler"]
        settings.laneInsideTick = false; settings.declinationOverride = 4
        XCTAssertTrue(settings.saving); XCTAssertTrue(settings.nightMode)
        await gate.release()
        let waiter = Task { await settings.waitForPersistence() }; waiter.cancel(); await waiter.value
        XCTAssertFalse(settings.saving); XCTAssertNil(settings.saveError)
        let reopened = AppSettings(directory: dir)
        XCTAssertEqual(reopened.backupSettings,settings.backupSettings)
        XCTAssertEqual(reopened.mgrsDigits,6); XCTAssertTrue(reopened.liveActivitiesEnabled)
        XCTAssertEqual(reopened.hiddenMapTools,["record","ruler"])
        let calls = await gate.calls; XCTAssertEqual(calls,2,"One obsolete staged file, then one latest snapshot; not one write per toggle")
    }
    func testFailedWriteRetainsSessionChoicesAndRetryPublishesThem() async throws {
        let dir = try directory(),gate = SettingsStageGate(),settings = store(dir,gate)
        settings.mgrsDigits = 8; await settings.waitForPersistence()
        let file = dir.appendingPathComponent("settings-v1.json"),bytes = try Data(contentsOf: file)
        await gate.arm(fail: true); settings.nightMode = true
        try await awaitStage(gate); await gate.release(); await settings.waitForPersistence()
        XCTAssertTrue(settings.nightMode); XCTAssertNotNil(settings.saveError); XCTAssertFalse(settings.saving)
        XCTAssertEqual(try Data(contentsOf: file),bytes); XCTAssertFalse(AppSettings(directory: dir).nightMode)
        let calls = await gate.calls
        try await Task.sleep(nanoseconds: 10_000_000)
        let after = await gate.calls; XCTAssertEqual(calls,after,"Failure must not busy-loop")
        settings.retryPersistence(); await settings.waitForPersistence()
        XCTAssertNil(settings.saveError); XCTAssertTrue(AppSettings(directory: dir).nightMode)
        XCTAssertEqual(AppSettings(directory: dir).mgrsDigits,8)
    }
    func testExternalReplacementDuringStagingIsKeptAndRetryDoesNotOverwriteIt() async throws {
        let dir = try directory(),gate = SettingsStageGate(),settings = store(dir,gate)
        settings.mgrsDigits = 8; await settings.waitForPersistence()
        let file = dir.appendingPathComponent("settings-v1.json")
        var external = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String:Any])
        external["mgrsDigits"] = 4
        let bytes = try JSONSerialization.data(withJSONObject: external)
        await gate.arm(); settings.nightMode = true; try await awaitStage(gate)
        try bytes.write(to: file,options: .atomic)
        await gate.release(); await settings.waitForPersistence()
        XCTAssertTrue(settings.nightMode); XCTAssertTrue(settings.saveError?.contains("outside this session") == true)
        XCTAssertEqual(try Data(contentsOf: file),bytes)
        settings.retryPersistence(); await settings.waitForPersistence()
        XCTAssertNotNil(settings.saveError); XCTAssertEqual(try Data(contentsOf: file),bytes)
        XCTAssertEqual(AppSettings(directory: dir).mgrsDigits,4)
    }
    func testConfirmedRestoreSupersedesHeldOrdinaryWriteAndItsLateFailure() async throws {
        for fail in [false,true] {
            let dir = try directory(),gate = SettingsStageGate(),settings = store(dir,gate)
            settings.mgrsDigits = 8; await settings.waitForPersistence()
            await gate.arm(fail: fail); settings.liveActivitiesEnabled = true; try await awaitStage(gate)
            var incoming = Backup.AppSettings(); incoming.mgrsDigits = 4; incoming.nightMode = true
            let snapshot = settings.restoreSnapshot(),desired = incoming
            let prepared = try await Task.detached { try snapshot.prepare(desired) }.value
            XCTAssertTrue(try settings.publishRestore(prepared))
            await gate.release(); await settings.waitForPersistence()
            XCTAssertNil(settings.saveError); XCTAssertEqual(settings.mgrsDigits,4); XCTAssertTrue(settings.liveActivitiesEnabled)
            let reopened = AppSettings(directory: dir)
            XCTAssertEqual(reopened.backupSettings,incoming); XCTAssertTrue(reopened.liveActivitiesEnabled)
        }
    }
    func testRestorePreparedBeforeOrdinaryPublicationRebasesEvenWithoutAnotherEdit() async throws {
        let dir = try directory(),gate = SettingsStageGate(),settings = store(dir,gate)
        await gate.arm(); settings.mgrsDigits = 6; try await awaitStage(gate)
        var incoming = Backup.AppSettings(); incoming.mgrsDigits = 4
        let snapshot = settings.restoreSnapshot(),desired = incoming
        let stale = try await Task.detached { try snapshot.prepare(desired) }.value
        await gate.release(); await settings.waitForPersistence()
        XCTAssertFalse(try settings.publishRestore(stale)); XCTAssertEqual(AppSettings(directory: dir).mgrsDigits,6)
        let fresh = settings.restoreSnapshot()
        let prepared = try await Task.detached { try fresh.prepare(desired) }.value
        XCTAssertTrue(try settings.publishRestore(prepared)); XCTAssertEqual(AppSettings(directory: dir).mgrsDigits,4)
    }
}
