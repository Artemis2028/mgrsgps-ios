import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class MapPreferencesPersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testFailedSaveKeepsOfflinePolicyAndToggleTogetherAndRetryPersists() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("map-prefs-v1.json")
        let model = MapLayerStore(directory: dir,installPipeline: false)
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        model.setOfflineOnly(true)
        XCTAssertTrue(model.preferences.offlineOnly); XCTAssertTrue(model.pipeline.offlineOnly)
        await model.waitForPreferences()
        XCTAssertNotNil(model.preferenceError); XCTAssertFalse(model.preferenceSaving)
        model.setOfflineOnly(false)
        XCTAssertFalse(model.preferences.offlineOnly); XCTAssertFalse(model.pipeline.offlineOnly)
        await model.waitForPreferences(); XCTAssertNotNil(model.preferenceError)
        model.setOfflineOnly(true)
        await model.waitForPreferences()
        try FileManager.default.removeItem(at: file)
        model.retryPreferences(); await model.waitForPreferences()
        XCTAssertNil(model.preferenceError)
        let reopened = MapLayerStore(directory: dir,installPipeline: false)
        XCTAssertTrue(reopened.preferences.offlineOnly); XCTAssertTrue(reopened.pipeline.offlineOnly)
    }
    func testDebouncedCameraKeepsNewOverlayChoicesAndNormalizesBounds() async throws {
        let dir = try directory(),model = MapLayerStore(directory: dir,installPipeline: false)
        model.saveCamera(lat: 90,lon: -1081,zoom: 30)
        model.setGrid(false); model.setContours(true); model.setOfflineOnly(true)
        await model.waitForPreferences()
        XCTAssertNil(model.preferenceError)
        let reopened = MapLayerStore(directory: dir,installPipeline: false)
        XCTAssertFalse(reopened.preferences.gridEnabled); XCTAssertTrue(reopened.preferences.contours)
        XCTAssertTrue(reopened.preferences.offlineOnly); XCTAssertTrue(reopened.preferences.hasCamera)
        XCTAssertEqual(reopened.preferences.latitude,85.05112878)
        XCTAssertEqual(reopened.preferences.longitude,-1); XCTAssertEqual(reopened.preferences.zoom,22)
        model.saveCamera(lat: .nan,lon: 1,zoom: 3)
        await model.waitForPreferences()
        XCTAssertEqual(model.preferences,reopened.preferences)
    }
    func testAtomicPublicationFailureRetainsIntentForRetry() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("map-prefs-v1.json")
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        let model = MapLayerStore(directory: dir,installPipeline: false)
        model.setContours(true); await model.waitForPreferences()
        XCTAssertNotNil(model.preferenceError)
        XCTAssertTrue(model.preferences.contours)
        XCTAssertTrue(try file.resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true)
    }
    func testExternalReplacementIsPreserved() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("map-prefs-v1.json")
        let model = MapLayerStore(directory: dir,installPipeline: false)
        var replacement = MapLayerStore.Preferences(); replacement.contours = true
        let bytes = try JSONEncoder().encode(replacement)
        try bytes.write(to: file,options: .atomic)
        model.setGrid(false); await model.waitForPreferences()
        XCTAssertNotNil(model.preferenceError)
        model.retryPreferences(); await model.waitForPreferences()
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testExternalReplacementDuringStagingWins() async throws {
        let dir = try directory(),gate = MapPreferenceStageGate()
        defer { gate.release() }
        let model = MapLayerStore(directory: dir,installPipeline: false,stage: gate.stage)
        model.setGrid(false)
        for _ in 0..<1000 {
            if gate.entered { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(gate.entered)
        let file = dir.appendingPathComponent("map-prefs-v1.json")
        var replacement = MapLayerStore.Preferences(); replacement.offlineOnly = true
        let bytes = try JSONEncoder().encode(replacement)
        try bytes.write(to: file,options: .atomic)
        gate.release(); await model.waitForPreferences()
        XCTAssertNotNil(model.preferenceError)
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testNewerEditSupersedesHeldWorkerWithoutPublishingOldPreferences() async throws {
        let dir = try directory(),gate = MapPreferenceStageGate()
        defer { gate.release() }
        let model = MapLayerStore(directory: dir,installPipeline: false,stage: gate.stage)
        model.setGrid(false)
        for _ in 0..<1000 {
            if gate.entered { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(gate.entered)
        model.setGrid(true); model.setOfflineOnly(true); model.setHillshade(true)
        gate.release(); await model.waitForPreferences()
        XCTAssertNil(model.preferenceError)
        let reopened = MapLayerStore(directory: dir,installPipeline: false)
        XCTAssertEqual(reopened.preferences,model.preferences)
        XCTAssertTrue(reopened.preferences.gridEnabled); XCTAssertTrue(reopened.preferences.offlineOnly)
        XCTAssertTrue(reopened.preferences.hillshade)
    }
}
private final class MapPreferenceStageGate: @unchecked Sendable {
    private let lock = NSLock(),semaphore = DispatchSemaphore(value: 0)
    private var started = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return started }
    func release() { semaphore.signal() }
    private func first() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if started { return false }; started = true; return true
    }
    func stage(_ value: MapLayerStore.Preferences,_ file: URL) async throws -> PreparedAtomicFile {
        try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            let staged = try PreparedAtomicFile(data: JSONEncoder().encode(value),destination: file)
            if self.first() { self.semaphore.wait() }
            return staged
        }.value
    }
}
