import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class BackupSnapshotTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }; return url
    }
    func testSharedSnapshotKeepsEverySavedSectionAndProtectedRoundTrip() async throws {
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"android-backup-contract",withExtension:"zip"))
        var plan = try Backup.importZip(Data(contentsOf:url))
        plan.navLanes = [.init(id:"settings-lane",name:"Creek",left:.init(graphicId:plan.graphics[0].id),right:.init(points:[.init(lat:24,lon:54),.init(lat:24.001,lon:54)]),backstop:.init(points:[.init(lat:24.4549,lon:54.3783),.init(lat:24.4549,lon:54.3793)]),scope:.checkpoint,targetId:plan.waypoints[0].id,createdAt:1)]
        plan.quietBoundaries = [.init(name:"Quiet area",vertices:[.init(lat:24,lon:54),.init(lat:24,lon:54.001),.init(lat:24.001,lon:54.001)])]
        try Backup.validate(plan)
        let dir = try directory(), points = WaypointStore(directory:dir), field = FieldDataStore(directory:dir), settings = AppSettings(directory:dir)
        let lanes = NavigationLaneStore(directory:dir), boundaries = BoundaryMonitor(directory:dir)
        await lanes.waitUntilLoaded()
        let result = await BackupCoordinator.restore(plan,waypoints:points,fieldData:field,settings:settings,lanes:lanes,boundaries:boundaries)
        XCTAssertFalse(result.contains("stopped"),result)
        let snapshot = try BackupCoordinator.snapshot(waypoints:points,fieldData:field,settings:settings,lanes:lanes,boundaries:boundaries)
        let archive = try await BackupPreparation.encode(snapshot)
        let sealed = try await BackupPreparation.protect(archive,password:"fixture password")
        let reopened = try Backup.importZip(BackupCrypto.open(sealed,password:"fixture password"))
        XCTAssertEqual(reopened.waypoints,snapshot.waypoints); XCTAssertEqual(reopened.folders,snapshot.folders)
        XCTAssertEqual(reopened.graphics,plan.graphics); XCTAssertEqual(reopened.tracks,snapshot.tracks)
        XCTAssertEqual(reopened.trackFiles,snapshot.trackFiles); XCTAssertEqual(reopened.courseHistory,plan.courseHistory)
        XCTAssertEqual(reopened.settings,settings.backupSettings); XCTAssertEqual(reopened.navLanes,plan.navLanes)
        XCTAssertEqual(reopened.quietBoundaries,plan.quietBoundaries); XCTAssertFalse(boundaries.running)
    }
    func testUnavailableSavedLibrariesRefusePartialBackupAndPreserveFiles() async throws {
        let dir = try directory(), points = WaypointStore(directory:dir), settings = AppSettings(directory:dir)
        let lanes = NavigationLaneStore(directory:dir); await lanes.waitUntilLoaded()
        let bad = Data("Original unreadable saved library".utf8)
        let index = dir.appendingPathComponent("field-data-v2.json"); try bad.write(to:index)
        let damagedField = FieldDataStore(directory:dir), healthyBoundary = BoundaryMonitor(directory:dir)
        XCTAssertThrowsError(try BackupCoordinator.snapshot(waypoints:points,fieldData:damagedField,settings:settings,lanes:lanes,boundaries:healthyBoundary))
        XCTAssertEqual(try Data(contentsOf:index),bad)
        try FileManager.default.removeItem(at:index)
        let boundaryFile = dir.appendingPathComponent("boundaries-v1.json"); try bad.write(to:boundaryFile)
        let field = FieldDataStore(directory:dir), damagedBoundary = BoundaryMonitor(directory:dir)
        XCTAssertThrowsError(try BackupCoordinator.snapshot(waypoints:points,fieldData:field,settings:settings,lanes:lanes,boundaries:damagedBoundary))
        XCTAssertEqual(try Data(contentsOf:boundaryFile),bad)
        let laneFile = dir.appendingPathComponent("nav-lanes-v1.json"); try bad.write(to:laneFile)
        let damagedLanes = NavigationLaneStore(directory:dir); await damagedLanes.waitUntilLoaded()
        XCTAssertThrowsError(try BackupCoordinator.snapshot(waypoints:points,fieldData:field,settings:settings,lanes:damagedLanes,boundaries:healthyBoundary))
        XCTAssertEqual(try Data(contentsOf:laneFile),bad)
    }
}
