import Combine
import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class StagedBackupIntegrationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func document() throws -> Backup.Document {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "android-backup-contract",withExtension: "zip"))
        return try Backup.importZip(Data(contentsOf: url))
    }

    func testAsyncRestorePublishesOnMainAndReopensEverySection() async throws {
        let directory = try directory(), document = try document()
        let points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory)
        let local = points.add(.init(name: "Local selected",lat: 24,lon: 54)); points.select(local.id)
        let subscriptions = [points.$waypoints.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) },
                             field.$document.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) },
                             settings.$nightMode.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }]
        let result = await BackupCoordinator.restore(document,waypoints: points,fieldData: field,settings: settings)
        XCTAssertFalse(result.contains("stopped"),result)
        let reopened = FieldDataStore(directory: directory)
        XCTAssertEqual(reopened.document.graphics,document.graphics)
        XCTAssertEqual(reopened.document.courseHistory,document.courseHistory)
        XCTAssertEqual(try reopened.points(for: document.tracks[0].id).count,2)
        XCTAssertEqual(WaypointStore(directory: directory).waypoints.count,2)
        XCTAssertEqual(WaypointStore(directory: directory).selectedId,local.id)
        XCTAssertEqual(AppSettings(directory: directory).backupSettings,document.settings)
        let retry = await BackupCoordinator.restore(document,waypoints: points,fieldData: field,settings: settings)
        XCTAssertFalse(retry.contains("stopped"),retry)
        XCTAssertEqual(points.waypoints.count,2); XCTAssertEqual(field.document.tracks.count,1)
        withExtendedLifetime(subscriptions) {}
    }

    func testSettingsEditRejectsStaleFileAndCanPrepareAgainOffMain() async throws {
        let directory = try directory(), settings = AppSettings(directory: directory)
        var backup = Backup.AppSettings(); backup.mgrsDigits = 8; backup.nightMode = true
        let desired = backup, snapshot = settings.restoreSnapshot()
        let prepared = try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return try snapshot.prepare(desired)
        }.value
        settings.mgrsDigits = 6
        XCTAssertFalse(try settings.publishRestore(prepared))
        XCTAssertEqual(AppSettings(directory: directory).mgrsDigits,6)
        let fresh = settings.restoreSnapshot()
        let rebased = try await Task.detached { try fresh.prepare(desired) }.value
        XCTAssertTrue(try settings.publishRestore(rebased))
        XCTAssertEqual(AppSettings(directory: directory).backupSettings,desired)
    }

    func testLargeAcceptedBackupRestoresWhileMainActorKeepsServingEdits() async throws {
        let document = try await Task.detached(priority: .userInitiated) {
            var document = Backup.Document()
            document.folders = (0..<100).map { FolderInfo(name: "Folder \($0)") }
            document.waypoints = (0..<5000).map { Waypoint(id: "wp-\($0)",name: "Point \($0)",lat: 24+Double($0)*0.000001,lon: 54,folder: "Folder \($0%100)") }
            document.graphics = (0..<1000).map { index in
                Backup.Graphic(id: "route-\(index)",name: "Route \(index)",type: "route",points: (0..<10).map { .init(lat: 24+Double(index)*0.000001,lon: 54+Double($0)*0.00001) },folder: "Folder \(index%100)")
            }
            let points = (0..<50000).map { TrackPoint(lat: 24+Double($0%1000)*0.000001,lon: 54) }
            let (track,bytes) = try TrackCodec.imported(name: "Large track",points: points,now: 1000)
            document.tracks = [track]; document.trackFiles[track.id] = bytes
            // Exercise an actually accepted backup, including the existing
            // manifest/member budgets, rather than an oversized synthetic plan.
            return try Backup.importZip(Backup.exportZip(document))
        }.value
        let directory = try directory(), points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory)
        let local = points.add(.init(name: "Local",lat: 24,lon: 54))
        let state = RestoreHeartbeatState()
        let heartbeat = Task { @MainActor in
            var last = ProcessInfo.processInfo.systemUptime
            while !state.done {
                let now = ProcessInfo.processInfo.systemUptime
                state.maximumGap = max(state.maximumGap,now-last); last = now; state.pulses += 1
                if state.pulses == 2 { points.update(id: local.id,draft: .init(name: "Edited during restore",lat: 24,lon: 54)); points.select(local.id) }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        let start = ProcessInfo.processInfo.systemUptime
        let result = await BackupCoordinator.restore(document,waypoints: points,fieldData: field,settings: settings)
        let elapsed = ProcessInfo.processInfo.systemUptime-start
        state.done = true; await heartbeat.value
        XCTAssertFalse(result.contains("stopped"),result)
        XCTAssertGreaterThan(state.pulses,2)
        let reopened = WaypointStore(directory: directory)
        XCTAssertEqual(reopened.waypoints.count,5001)
        XCTAssertEqual(reopened.waypoints.first { $0.id == local.id }?.name,"Edited during restore")
        XCTAssertEqual(reopened.selectedId,local.id)
        let durable = FieldDataStore(directory: directory)
        XCTAssertEqual(durable.document.graphics.count,1000)
        XCTAssertEqual(try durable.points(for: document.tracks[0].id).count,50000)
        let metrics = String(format: "5000 imported waypoints, 1000 routes, 50000 track points; restore %.3f s; main-actor pulses %d; largest observed pulse gap %.3f s",elapsed,state.pulses,state.maximumGap)
        print("[staged-restore-benchmark] \(metrics)")
        let attachment = XCTAttachment(string: metrics); attachment.name = "staged-restore-benchmark"; attachment.lifetime = .keepAlways; add(attachment)
        // Timing is recorded, not a hardware-dependent CI pass threshold. This
        // does not measure rendering a large library's actual SwiftUI cards.
    }
}

@MainActor
private final class RestoreHeartbeatState {
    var done = false
    var pulses = 0
    var maximumGap = 0.0
}
