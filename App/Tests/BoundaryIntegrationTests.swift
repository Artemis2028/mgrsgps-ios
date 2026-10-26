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
    private func fix(_ x: Double,_ y: Double,_ time: Double,accuracy: Double = 2) -> CLLocation {
        let p = point(x,y)
        return CLLocation(coordinate: .init(latitude: p.lat,longitude: p.lon),altitude: 0,horizontalAccuracy: accuracy,verticalAccuracy: -1,timestamp: Date(timeIntervalSince1970: time))
    }
    func testBackgroundCrossingQuietInsideNoRepeatsAndReentry() async throws {
        let driver = BoundaryTestDriver(), alerts = TestBoundaryAlerts(), dir = try directory()
        var foreground = true, clock = Date(timeIntervalSince1970: 100)
        let monitor = BoundaryMonitor(directory: dir,driver: driver,alerts: alerts,now: { clock },foreground: { foreground })
        let a = area; XCTAssertTrue(monitor.save(a)); monitor.start(a)
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
        XCTAssertFalse(driver.updating); XCTAssertFalse(alerts.active); XCTAssertEqual(monitor.crossingCount,2)
    }
    func testNoAutomaticRestartAfterRelaunchAndEditsAreDurable() async throws {
        let dir = try directory(), driver = BoundaryTestDriver()
        let first = BoundaryMonitor(directory: dir,driver: driver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; XCTAssertTrue(first.save(a)); first.start(a); try await wait { first.running }
        var edited = a; edited.name = "Changed"
        XCTAssertFalse(first.save(edited)); first.delete(a); XCTAssertEqual(first.areas.count,1)
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
        first.stop(); XCTAssertTrue(second.save(edited))
        let third = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts(),foreground: { true })
        XCTAssertEqual(third.areas.first?.name,"Changed"); third.delete(edited); XCTAssertTrue(third.areas.isEmpty)
    }
    func testPermissionFlowAndLossStopWithoutDeletingBoundary() async throws {
        let driver = BoundaryTestDriver(); driver.authorization = .notDetermined
        let monitor = BoundaryMonitor(directory: try directory(),driver: driver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; XCTAssertTrue(monitor.save(a)); monitor.start(a)
        XCTAssertEqual(driver.requests,1); XCTAssertFalse(driver.updating)
        driver.authorization = .authorizedWhenInUse; driver.onAuthorization?()
        try await wait { monitor.running }
        driver.precise = false; driver.onAuthorization?()
        XCTAssertFalse(monitor.running); XCTAssertFalse(driver.updating); XCTAssertEqual(monitor.areas,[a]); XCTAssertNotNil(monitor.error)
    }
    func testStaleAndInaccurateLocationsAndStartingOutsideAreSilent() async throws {
        let driver = BoundaryTestDriver(), alerts = TestBoundaryAlerts()
        let monitor = BoundaryMonitor(directory: try directory(),driver: driver,alerts: alerts,now: { Date(timeIntervalSince1970: 110) },foreground: { true })
        let a = area; XCTAssertTrue(monitor.save(a)); monitor.start(a); try await wait { monitor.running }
        driver.onLocations?([fix(150,50,100),fix(150,50,103),fix(150,50,105)])
        XCTAssertEqual(alerts.crossings,[])
        driver.onLocations?([fix(50,50,106,accuracy: 100),fix(50,50,1)])
        XCTAssertEqual(alerts.crossings,[])
        monitor.stop()
    }
    func testCorruptFileIsKeptAndNeverOverwritten() throws {
        let dir = try directory(), file = dir.appendingPathComponent("boundaries-v1.json")
        try Data("broken-boundary-data".utf8).write(to: file)
        let monitor = BoundaryMonitor(directory: dir,driver: BoundaryTestDriver(),alerts: TestBoundaryAlerts(),foreground: { true })
        XCTAssertTrue(monitor.loadFailed); XCTAssertFalse(monitor.save(area))
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
            XCTAssertTrue(monitor.loadFailed); XCTAssertNotNil(monitor.error); XCTAssertFalse(monitor.save(area))
            monitor.start(area)
            XCTAssertFalse(monitor.running); XCTAssertFalse(driver.updating); XCTAssertFalse(alerts.active)
            XCTAssertEqual(try Data(contentsOf: file),bytes)
        }
    }
    func testBoundarySourceChangesAndWrongDirectoryCannotInstallPreparedAreas() throws {
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
        XCTAssertTrue(stale.loadFailed); XCTAssertTrue(stale.areas.isEmpty); XCTAssertFalse(stale.save(area))
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
    func testFailedPublicationKeepsExistingBoundaryAndCanRetry() throws {
        let dir = try directory(), driver = BoundaryTestDriver()
        let monitor = BoundaryMonitor(directory: dir,driver: driver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; XCTAssertTrue(monitor.save(a))
        let file = dir.appendingPathComponent("boundaries-v1.json"), saved = dir.appendingPathComponent("saved.json")
        try FileManager.default.moveItem(at: file,to: saved)
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        var changed = a; changed.name = "Changed"
        XCTAssertFalse(monitor.save(changed)); XCTAssertEqual(monitor.areas,[a])
        try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: saved,to: file)
        XCTAssertTrue(monitor.save(changed)); XCTAssertEqual(monitor.areas,[changed])
    }
    func testRecordingAndBoundaryMonitoringHaveIndependentLifetimes() async throws {
        let dir = try directory(), recordingDriver = BoundaryTestDriver(), boundaryDriver = BoundaryTestDriver()
        let field = FieldDataStore(directory: dir)
        let recorder = TrackRecorder(directory: dir,fieldData: field,driver: recordingDriver,isForeground: { true })
        let monitor = BoundaryMonitor(directory: dir,driver: boundaryDriver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; XCTAssertTrue(monitor.save(a))
        try await wait { recorder.phase == .idle }
        recorder.start(); monitor.start(a)
        try await wait { recorder.phase == .recording && monitor.running }
        monitor.stop(); XCTAssertTrue(recordingDriver.updating); XCTAssertFalse(boundaryDriver.updating)
        monitor.start(a); try await wait { monitor.running }
        recorder.stop(name: "Concurrent patrol"); try await wait { recorder.phase == .idle }
        XCTAssertTrue(boundaryDriver.updating); XCTAssertFalse(recordingDriver.updating)
        monitor.stop()
    }
    func testRealManagerSupportsBackgroundAndDoesNotAutomaticallyPause() async throws {
        let driver = CoreLocationRecordingDriver()
        let monitor = BoundaryMonitor(directory: try directory(),driver: driver,alerts: TestBoundaryAlerts(),foreground: { true })
        let a = area; XCTAssertTrue(monitor.save(a)); monitor.start(a); try await wait { monitor.running || monitor.error != nil }
        guard monitor.running else { throw XCTSkip("Simulator needs precise While Using location permission") }
        XCTAssertTrue(driver.backgroundEnabled); XCTAssertTrue(driver.showsIndicator); XCTAssertFalse(driver.automaticallyPauses)
        monitor.stop(); XCTAssertFalse(driver.backgroundEnabled)
    }
}
