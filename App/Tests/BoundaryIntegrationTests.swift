import CoreLocation
import GridFixCore
import MapLibre
import XCTest
@testable import MGRSGPS

@MainActor
private final class BoundaryTestDriver: RecordingLocationDriver {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var precise = true, servicesEnabled = true, updating = false
    var requests = 0
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    func requestPermission() { requests += 1 }
    func start() { updating = true }
    func stop() { updating = false }
}
@MainActor
private final class TestBoundaryAlerts: BoundaryAlerting {
    var status = "Test notifications"
    var active = false
    var crossings: [String] = []
    func prepare() async {}
    func begin() { active = true }
    func crossing(name: String) { if active { crossings.append(name) } }
    func stop() { active = false }
}

private actor BoundaryStageGate {
    private var armed = false
    private(set) var arrived = false
    private var continuation: CheckedContinuation<Void,Never>?
    func arm() { armed = true; arrived = false }
    func hold() async {
        guard armed else { return }
        armed = false; arrived = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class BoundaryIntegrationTests: XCTestCase {
    private func point(_ x: Double,_ y: Double) -> GeoPoint { GeoPoint(lat: y/111_319.49,lon: x/111_319.49) }
    private var area: BoundaryArea { BoundaryArea(name: "Patrol",vertices: [point(0,0),point(100,0),point(100,100),point(0,100)]) }
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    private func wait(_ test: () -> Bool) async throws {
        let end = Date().addingTimeInterval(5)
        while !test() && Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(test())
    }
    private func assertSave(_ monitor: BoundaryMonitor,_ area: BoundaryArea,expected: Bool = true,file: StaticString = #filePath,line: UInt = #line) async {
        let saved = await monitor.save(area)
        XCTAssertEqual(saved,expected,monitor.error ?? "Boundary save result",file: file,line: line)
    }
    private func fix(_ x: Double,_ y: Double,_ time: Double,accuracy: Double = 2) -> CLLocation {
        let p = point(x,y)
        return CLLocation(coordinate: .init(latitude: p.lat,longitude: p.lon),altitude: 0,horizontalAccuracy: accuracy,verticalAccuracy: -1,timestamp: Date(timeIntervalSince1970: time))
    }
    func testBackupRestoreIsAdditiveDurableAndNeverStartsImportedMonitor() async throws {
        let dir = try directory(), driver = BoundaryTestDriver(), alerts = TestBoundaryAlerts()
        let monitor = BoundaryMonitor(directory: dir,driver: driver,alerts: alerts)
        var local = area; local.name = "Locally edited"; await assertSave(monitor,local)
        var stale = local; stale.name = "Old backup name"
        var imported = area; imported.name = "Imported quiet area"
        let plan = try Backup.importZip(Backup.exportZip(.init(quietBoundaries: [stale,imported])))
        let points = WaypointStore(directory: dir), field = FieldDataStore(directory: dir), settings = AppSettings(directory: dir)
        let result = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,boundaries: monitor)
        XCTAssertTrue(result.contains("1 quiet boundary"),result); XCTAssertEqual(monitor.areas,[local,imported])
        XCTAssertFalse(monitor.running); XCTAssertFalse(driver.updating); XCTAssertFalse(alerts.active); XCTAssertEqual(driver.requests,0)
        let file = dir.appendingPathComponent("boundaries-v1.json"), bytes = try Data(contentsOf: file)
        let retry = try await monitor.restore(plan.quietBoundaries)
        XCTAssertEqual(retry,0); XCTAssertEqual(try Data(contentsOf: file),bytes)
        let reopened = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        XCTAssertEqual(reopened.areas,[local,imported]); XCTAssertFalse(reopened.running)
    }
    func testBoundaryRestoreFailureAndCancelledConfirmedRetry() async throws {
        let dir = try directory(), monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        let a = area, file = dir.appendingPathComponent("boundaries-v1.json")
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        do { _ = try await monitor.restore([a]); XCTFail("Must not publish after failed rename") } catch {}
        XCTAssertTrue(monitor.areas.isEmpty)
        try FileManager.default.removeItem(at: file)
        let task = Task { try await monitor.restore([a]) }; task.cancel()
        let count = try await task.value
        XCTAssertEqual(count,1); XCTAssertEqual(monitor.areas,[a]); XCTAssertFalse(monitor.running)
        let bad = BoundaryArea(id: "bad",name: "Invalid",vertices: [])
        let bytes = try Data(contentsOf: file)
        do { _ = try await monitor.restore([area,bad]); XCTFail("No partial malformed restore") } catch {}
        XCTAssertEqual(monitor.areas,[a]); XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testRestorePreservesAlreadyRunningBoundaryAndDoesNotStartImportedArea() async throws {
        let dir = try directory(), driver = BoundaryTestDriver(), alerts = TestBoundaryAlerts()
        let monitor = BoundaryMonitor(directory: dir,driver: driver,alerts: alerts,foreground: { true })
        let a = area; await assertSave(monitor,a); monitor.start(a); try await wait { monitor.running }
        let imported = area
        let count = try await monitor.restore([imported])
        XCTAssertEqual(count,1); XCTAssertEqual(monitor.activeID,a.id); XCTAssertTrue(driver.updating); XCTAssertTrue(alerts.active)
        let reopened = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        XCTAssertEqual(reopened.areas,[a,imported]); XCTAssertFalse(reopened.running)
        monitor.stop(); await monitor.waitForPersistence()
    }
    func testMissingBoundaryStoreRejectsBeforeOtherSectionsMutate() async throws {
        let dir = try directory(), points = WaypointStore(directory: dir), field = FieldDataStore(directory: dir), settings = AppSettings(directory: dir)
        let plan = Backup.Document(waypoints: [.init(name: "Must not be added",lat: 24,lon: 54)],quietBoundaries: [area])
        let result = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings)
        XCTAssertTrue(result.contains("storage is unavailable"),result); XCTAssertTrue(result.contains("No records added"),result)
        XCTAssertTrue(points.waypoints.isEmpty)
    }
    func testBoundaryPhaseFailureReportsPriorWaypointsAndRetryFinishesSettings() async throws {
        let dir = try directory(), monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        let points = WaypointStore(directory: dir), field = FieldDataStore(directory: dir), settings = AppSettings(directory: dir)
        var plan = Backup.Document(waypoints: [.init(name: "Imported point",lat: 24,lon: 54)],quietBoundaries: [area])
        plan.settings.mgrsDigits = 6
        let file = dir.appendingPathComponent("boundaries-v1.json")
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        let failed = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,boundaries: monitor)
        XCTAssertTrue(failed.contains("Already restored: 1 waypoints"),failed)
        XCTAssertEqual(points.waypoints.count,1); XCTAssertTrue(monitor.areas.isEmpty); XCTAssertEqual(settings.mgrsDigits,10)
        try FileManager.default.removeItem(at: file)
        let retry = await BackupCoordinator.restore(plan,waypoints: points,fieldData: field,settings: settings,boundaries: monitor)
        XCTAssertFalse(retry.contains("stopped"),retry); XCTAssertTrue(retry.contains("1 quiet boundary"),retry)
        XCTAssertEqual(points.waypoints.count,1); XCTAssertEqual(monitor.areas,plan.quietBoundaries); XCTAssertEqual(settings.mgrsDigits,6)
        XCTAssertFalse(monitor.running)
    }
    func testExternalBoundaryReplacementIsKeptBeforeRestoreOrOrdinarySave() async throws {
        let dir = try directory(), monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        let original = area; await assertSave(monitor,original)
        let external = area, file = dir.appendingPathComponent("boundaries-v1.json")
        let bytes = try JSONEncoder().encode(BoundaryMonitor.Document(areas: [external]))
        try bytes.write(to: file,options: .atomic)
        do { _ = try await monitor.restore([area]); XCTFail("An external replacement must be kept") } catch {}
        XCTAssertEqual(monitor.areas,[original]); XCTAssertEqual(try Data(contentsOf: file),bytes)
        await assertSave(monitor,original,expected: false); XCTAssertEqual(try Data(contentsOf: file),bytes)
        let reopened = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        XCTAssertEqual(reopened.areas,[external]); XCTAssertFalse(reopened.running)
    }
    func testMaximumBoundaryRestoreAllowsMainActorProgressAndReopensEveryVertex() async throws {
        let dir = try directory(), monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        let vertices = (0..<256).map { i in
            let angle = Double(i) * 2 * Double.pi / 256
            return GeoPoint(lat: 24 + 0.001 * sin(angle),lon: 54 + 0.001 * cos(angle))
        }
        let areas = (0..<100).map { BoundaryArea(id: "max-\($0)",name: "Quiet perimeter \($0)",vertices: vertices) }
        var beats = 0
        let pulse = Task { while !Task.isCancelled { beats += 1; try? await Task.sleep(nanoseconds: 1_000_000) } }
        defer { pulse.cancel() }
        let count = try await monitor.restore(areas)
        XCTAssertEqual(count,100); XCTAssertGreaterThan(beats,2)
        XCTAssertEqual(monitor.areas,areas); XCTAssertFalse(monitor.running)
        let prepared = await Task.detached { BoundaryMonitor.prepareStartup(directory: dir) }.value
        let reopened = BoundaryMonitor(directory: dir,startup: prepared,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        XCTAssertFalse(reopened.loadFailed); XCTAssertEqual(reopened.areas,areas); XCTAssertFalse(reopened.running)
    }
    func testBackgroundCrossingQuietInsideNoRepeatsAndReentry() async throws {
        let driver = BoundaryTestDriver(), alerts = TestBoundaryAlerts(), dir = try directory()
        var foreground = true, clock = Date(timeIntervalSince1970: 100)
        let monitor = BoundaryMonitor(directory: dir,driver: driver,alerts: alerts,now: { clock },foreground: { foreground })
        let a = area; await assertSave(monitor,a); monitor.start(a)
        try await wait { monitor.running }
        func send(_ x: Double,_ y: Double,_ t: Double) {
            clock = Date(timeIntervalSince1970: t); driver.onLocations?([fix(x,y,t)])
        }
        send(50,50,100); send(50,50,102); send(60,60,103)
        XCTAssertEqual(alerts.crossings,[]); XCTAssertTrue(monitor.status.contains("quiet"))
        foreground = false // Root stops its foreground location manager; this driver stays alive.
        send(150,50,104); send(150,50,106); send(180,50,107)
        XCTAssertTrue(driver.updating); XCTAssertEqual(alerts.crossings,["Patrol"]); XCTAssertEqual(monitor.crossingCount,1)
        send(50,50,108); send(50,50,110); send(50,150,111); send(50,150,113)
        XCTAssertEqual(alerts.crossings,["Patrol","Patrol"])
        clock = Date(timeIntervalSince1970: 125); monitor.refresh()
        XCTAssertFalse(monitor.hasFreshFix)
        monitor.stop(); send(50,50,126); send(150,50,129)
        XCTAssertFalse(driver.updating); XCTAssertFalse(alerts.active); XCTAssertEqual(monitor.crossingCount,2); await monitor.waitForPersistence()
    }
    func testNoAutomaticRestartAfterRelaunchAndEditsAreDurable() async throws {
        let dir = try directory(), driver = BoundaryTestDriver()
        let first = BoundaryMonitor(directory: dir,driver: driver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; await assertSave(first,a); first.start(a); try await wait { first.running }
        var edited = a; edited.name = "Changed"
        await assertSave(first,edited,expected: false); await first.delete(a); XCTAssertEqual(first.areas.count,1)
        let file = dir.appendingPathComponent("boundaries-v1.json"),bytes = try Data(contentsOf: file)
        let prepared = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return BoundaryMonitor.prepareStartup(directory: dir)
        }.value
        let secondDriver = BoundaryTestDriver(),secondAlerts = TestBoundaryAlerts()
        let second = BoundaryMonitor(directory: dir,startup: prepared,driver: secondDriver,alerts: secondAlerts,foreground: { true })
        XCTAssertEqual(second.areas,[a]); XCTAssertFalse(second.running); XCTAssertFalse(secondDriver.updating)
        XCTAssertFalse(secondAlerts.active); XCTAssertEqual(secondDriver.requests,0)
        XCTAssertEqual(try Data(contentsOf: file),bytes)
        XCTAssertTrue(second.status.contains("interrupted"))
        first.stop(); await first.waitForPersistence()
        // The old instance wrote its stop after the startup snapshot. A real
        // reopened editor loads that latest file before saving its edits.
        let editable = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        await assertSave(editable,edited)
        let third = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts(),foreground: { true })
        XCTAssertEqual(third.areas.first?.name,"Changed"); await third.delete(edited); XCTAssertTrue(third.areas.isEmpty)
    }
    func testPermissionFlowAndLossStopWithoutDeletingBoundary() async throws {
        let driver = BoundaryTestDriver(); driver.authorization = .notDetermined
        let monitor = BoundaryMonitor(directory: try directory(),driver: driver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; await assertSave(monitor,a); monitor.start(a)
        XCTAssertEqual(driver.requests,1); XCTAssertFalse(driver.updating)
        driver.authorization = .authorizedWhenInUse; driver.onAuthorization?()
        try await wait { monitor.running }
        driver.precise = false; driver.onAuthorization?()
        XCTAssertFalse(monitor.running); XCTAssertFalse(driver.updating); XCTAssertEqual(monitor.areas,[a]); XCTAssertNotNil(monitor.error); await monitor.waitForPersistence()
    }
    func testStaleAndInaccurateLocationsAndStartingOutsideAreSilent() async throws {
        let driver = BoundaryTestDriver(), alerts = TestBoundaryAlerts()
        let monitor = BoundaryMonitor(directory: try directory(),driver: driver,alerts: alerts,now: { Date(timeIntervalSince1970: 110) },foreground: { true })
        let a = area; await assertSave(monitor,a); monitor.start(a); try await wait { monitor.running }
        driver.onLocations?([fix(150,50,100),fix(150,50,103),fix(150,50,105)])
        XCTAssertEqual(alerts.crossings,[])
        driver.onLocations?([fix(50,50,106,accuracy: 100),fix(50,50,1)])
        XCTAssertEqual(alerts.crossings,[])
        monitor.stop(); await monitor.waitForPersistence()
    }
    func testCorruptFileIsKeptAndNeverOverwritten() async throws {
        let dir = try directory(), file = dir.appendingPathComponent("boundaries-v1.json")
        try Data("broken-boundary-data".utf8).write(to: file)
        let monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts(),foreground: { true })
        XCTAssertTrue(monitor.loadFailed); await assertSave(monitor,area,expected: false)
        XCTAssertEqual(try String(contentsOf: file),"broken-boundary-data")
    }
    func testWorkerBoundaryStartupKeepsCorruptInvalidAndOversizedLibrariesReadOnly() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("boundaries-v1.json")
        let saved = area
        var invalid = saved; invalid.vertices = [point(0,0),point(100,0),point(50,0)]
        let samples = [Data("malformed CAFÉ".utf8),
                       try JSONEncoder().encode(BoundaryMonitor.Document(areas: [saved,saved])),
                       try JSONEncoder().encode(BoundaryMonitor.Document(areas: [invalid])),
                       Data(repeating: 0x20,count: 2*1024*1024+1)]
        for bytes in samples {
            try bytes.write(to: file,options: .atomic)
            let prepared = await Task.detached { BoundaryMonitor.prepareStartup(directory: dir) }.value
            let driver = BoundaryTestDriver(),alerts = TestBoundaryAlerts()
            let monitor = BoundaryMonitor(directory: dir,startup: prepared,driver: driver,alerts: alerts,foreground: { true })
            XCTAssertTrue(monitor.loadFailed); XCTAssertNotNil(monitor.error); await assertSave(monitor,area,expected: false)
            monitor.start(area)
            XCTAssertFalse(monitor.running); XCTAssertFalse(driver.updating); XCTAssertFalse(alerts.active)
            XCTAssertEqual(try Data(contentsOf: file),bytes)
        }
    }
    func testBoundarySourceChangesAndWrongDirectoryCannotInstallPreparedAreas() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("boundaries-v1.json")
        let missing = BoundaryMonitor.prepareStartup(directory: dir)
        let original = try JSONEncoder().encode(BoundaryMonitor.Document(areas: [area]))
        try original.write(to: file,options: .atomic)
        XCTAssertThrowsError(try missing.validate())
        let beforeReplace = BoundaryMonitor.prepareStartup(directory: dir)
        var newer = area; newer.name = "Newer boundary"
        let replacement = try JSONEncoder().encode(BoundaryMonitor.Document(areas: [newer]))
        try replacement.write(to: file,options: .atomic)
        XCTAssertThrowsError(try beforeReplace.validate())
        let driver = BoundaryTestDriver(),alerts = TestBoundaryAlerts()
        let stale = BoundaryMonitor(directory: dir,startup: beforeReplace,driver: driver,alerts: alerts,foreground: { true })
        XCTAssertTrue(stale.loadFailed); XCTAssertTrue(stale.areas.isEmpty); await assertSave(stale,area,expected: false)
        XCTAssertEqual(try Data(contentsOf: file),replacement)
        let valid = BoundaryMonitor.prepareStartup(directory: dir)
        let wrong = BoundaryMonitor(directory: try directory(),startup: valid,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        XCTAssertTrue(wrong.loadFailed); XCTAssertTrue(wrong.areas.isEmpty)
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try valid.validate())
        let fresh = BoundaryMonitor(directory: dir,startup: BoundaryMonitor.prepareStartup(directory: dir),driver: driver,alerts: alerts)
        XCTAssertFalse(fresh.loadFailed); XCTAssertFalse(fresh.running); XCTAssertFalse(driver.updating)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testFailedPublicationKeepsExistingBoundaryAndCanRetry() async throws {
        let dir = try directory(), driver = BoundaryTestDriver()
        let monitor = BoundaryMonitor(directory: dir,driver: driver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; await assertSave(monitor,a)
        let file = dir.appendingPathComponent("boundaries-v1.json"), saved = dir.appendingPathComponent("saved.json")
        try FileManager.default.moveItem(at: file,to: saved)
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        var changed = a; changed.name = "Changed"
        await assertSave(monitor,changed,expected: false); XCTAssertEqual(monitor.areas,[a])
        try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: saved,to: file)
        await assertSave(monitor,changed); XCTAssertEqual(monitor.areas,[changed])
    }
    func testRecordingAndBoundaryMonitoringHaveIndependentLifetimes() async throws {
        let dir = try directory(), recordingDriver = BoundaryTestDriver(), boundaryDriver = BoundaryTestDriver()
        let field = FieldDataStore(directory: dir)
        let recorder = TrackRecorder(directory: dir,fieldData: field,driver: recordingDriver,isForeground: { true })
        let monitor = BoundaryMonitor(directory: dir,driver: boundaryDriver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; await assertSave(monitor,a)
        try await wait { recorder.phase == .idle }
        recorder.start(); monitor.start(a)
        try await wait { recorder.phase == .recording && monitor.running }
        monitor.stop(); XCTAssertTrue(recordingDriver.updating); XCTAssertFalse(boundaryDriver.updating)
        monitor.start(a); try await wait { monitor.running }
        recorder.stop(name: "Concurrent patrol"); try await wait { recorder.phase == .idle }
        XCTAssertTrue(boundaryDriver.updating); XCTAssertFalse(recordingDriver.updating)
        monitor.stop(); await monitor.waitForPersistence()
    }
    func testRealManagerSupportsBackgroundAndDoesNotAutomaticallyPause() async throws {
        let driver = CoreLocationRecordingDriver()
        let monitor = BoundaryMonitor(directory: try directory(),driver: driver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; await assertSave(monitor,a); monitor.start(a); try await wait { monitor.running || monitor.error != nil }
        guard monitor.running else { throw XCTSkip("Simulator needs precise While Using location permission") }
        XCTAssertTrue(driver.backgroundEnabled); XCTAssertTrue(driver.showsIndicator); XCTAssertFalse(driver.automaticallyPauses)
        monitor.stop(); XCTAssertFalse(driver.backgroundEnabled); await monitor.waitForPersistence()
    }
    private func awaitStage(_ gate: BoundaryStageGate) async throws {
        let end = Date().addingTimeInterval(5)
        while !(await gate.arrived),Date() < end { try await Task.sleep(nanoseconds: 1_000_000) }
        let arrived = await gate.arrived
        XCTAssertTrue(arrived,"Write must reach independent file staging")
    }
    func testStoppedPreparingWriteCannotResurrectMonitoring() async throws {
        let dir = try directory(),gate = BoundaryStageGate(),driver = BoundaryTestDriver(),alerts = TestBoundaryAlerts()
        let monitor = BoundaryMonitor(directory: dir,driver: driver,alerts: alerts,foreground: { true },stage: { doc,file in
            let staged = try await BoundaryMonitor.stageDocument(doc,to: file)
            await gate.hold(); return staged
        })
        let a = area; await assertSave(monitor,a)
        await gate.arm(); monitor.start(a); try await awaitStage(gate)
        XCTAssertTrue(monitor.preparing); XCTAssertFalse(driver.updating)
        monitor.stop()
        XCTAssertFalse(monitor.preparing); XCTAssertFalse(monitor.running); XCTAssertFalse(driver.updating); XCTAssertFalse(alerts.active)
        await gate.release(); await monitor.waitForPersistence()
        XCTAssertFalse(monitor.running); XCTAssertFalse(monitor.writing); XCTAssertFalse(alerts.active)
        let saved = try JSONDecoder().decode(BoundaryMonitor.Document.self,from: Data(contentsOf: dir.appendingPathComponent("boundaries-v1.json")))
        XCTAssertNil(saved.interruptedID); XCTAssertEqual(saved.areas,[a])
        monitor.start(a); try await wait { monitor.running }
        monitor.stop(); await monitor.waitForPersistence()
    }
    func testImmediateStopAndQueuedRestartKeepLatestInterruptionMarker() async throws {
        let dir = try directory(),gate = BoundaryStageGate(),driver = BoundaryTestDriver(),alerts = TestBoundaryAlerts()
        let monitor = BoundaryMonitor(directory: dir,driver: driver,alerts: alerts,foreground: { true },stage: { doc,file in
            let staged = try await BoundaryMonitor.stageDocument(doc,to: file)
            await gate.hold(); return staged
        })
        let a = area; await assertSave(monitor,a); monitor.start(a); try await wait { monitor.running }
        await gate.arm(); monitor.stop()
        XCTAssertFalse(driver.updating); XCTAssertFalse(alerts.active); XCTAssertFalse(monitor.running)
        try await awaitStage(gate)
        monitor.start(a); XCTAssertTrue(monitor.preparing)
        await gate.release(); try await wait { monitor.running && !monitor.writing }
        let saved = try JSONDecoder().decode(BoundaryMonitor.Document.self,from: Data(contentsOf: dir.appendingPathComponent("boundaries-v1.json")))
        XCTAssertEqual(saved.interruptedID,a.id); XCTAssertEqual(saved.areas,[a])
        XCTAssertTrue(driver.updating); XCTAssertTrue(alerts.active)
        monitor.stop(); await monitor.waitForPersistence()
    }
    func testConfirmedEditAndQueuedRestoreSerializeWithoutLosingEitherChange() async throws {
        let dir = try directory(),gate = BoundaryStageGate()
        let monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts(),stage: { doc,file in
            let staged = try await BoundaryMonitor.stageDocument(doc,to: file)
            await gate.hold(); return staged
        })
        let a = area; await assertSave(monitor,a)
        var edited = a; edited.name = "Edited CAFÉ"
        await gate.arm()
        let edit = Task { await monitor.save(edited) }
        try await awaitStage(gate)
        let imported = area
        let restore = Task { try await monitor.restore([imported]) }
        // Dismissing a confirmed action does not roll back its durable intent.
        edit.cancel(); restore.cancel()
        await gate.release()
        let saved = await edit.value,count = try await restore.value
        XCTAssertTrue(saved); XCTAssertEqual(count,1); XCTAssertEqual(monitor.areas,[edited,imported]); XCTAssertFalse(monitor.writing)
        let reopened = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        XCTAssertEqual(reopened.areas,[edited,imported]); XCTAssertFalse(reopened.running)
        let deletedStale = await monitor.delete(a)
        XCTAssertFalse(deletedStale); XCTAssertEqual(monitor.areas,[edited,imported])
    }
    func testExternalReplacementDuringStagingRejectsEditAndKeepsEveryExternalByte() async throws {
        let dir = try directory(),gate = BoundaryStageGate()
        let monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts(),stage: { doc,file in
            let staged = try await BoundaryMonitor.stageDocument(doc,to: file)
            await gate.hold(); return staged
        })
        let a = area; await assertSave(monitor,a)
        var edited = a; edited.name = "Must not replace external file"
        await gate.arm(); let edit = Task { await monitor.save(edited) }
        try await awaitStage(gate)
        let external = area,file = dir.appendingPathComponent("boundaries-v1.json")
        let bytes = try JSONEncoder().encode(BoundaryMonitor.Document(areas: [external]))
        try bytes.write(to: file,options: .atomic)
        await gate.release(); let saved = await edit.value
        XCTAssertFalse(saved); XCTAssertNotNil(monitor.error); XCTAssertEqual(monitor.areas,[a]); XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testMaximumOrdinaryEditAndDeleteKeepMainActorResponsiveAndAllOtherVertices() async throws {
        let dir = try directory(),monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        let vertices = (0..<256).map { i in
            let angle = Double(i) * 2 * Double.pi / 256
            return GeoPoint(lat: 24 + 0.001 * sin(angle),lon: 54 + 0.001 * cos(angle))
        }
        var expected = (0..<100).map { BoundaryArea(id: "max-\($0)",name: "Quiet perimeter \($0)",vertices: vertices) }
        _ = try await monitor.restore(expected)
        var edited = expected[50]; edited.name = "Edited large perimeter"; expected[50] = edited
        var beats = 0
        let pulse = Task { while !Task.isCancelled { beats += 1; try? await Task.sleep(nanoseconds: 1_000_000) } }
        defer { pulse.cancel() }
        await assertSave(monitor,edited)
        XCTAssertGreaterThan(beats,0,"Geometry/encoding/file staging must yield the UI thread")
        let deleted = await monitor.delete(expected[25]); XCTAssertTrue(deleted); expected.remove(at: 25)
        let prepared = await Task.detached { BoundaryMonitor.prepareStartup(directory: dir) }.value
        let reopened = BoundaryMonitor(directory: dir,startup: prepared,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts())
        XCTAssertEqual(reopened.areas,expected); XCTAssertFalse(reopened.running); XCTAssertFalse(monitor.writing)
    }

}
