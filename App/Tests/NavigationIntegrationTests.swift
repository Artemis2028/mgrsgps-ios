import CoreLocation
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
private final class GuideTestDriver: NavigationLocationDriver {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var precise = true, servicesEnabled = true, hasCompass = true, updating = false
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var onHeading: ((NavigationHeading) -> Void)?
    func requestPermission() {}
    func start() { updating = true }
    func stop() { updating = false }
}
@MainActor
private final class GuideTestFeedback: NavigationFeedback {
    var status = "Test feedback"
    var pulses: [NavigationPulse] = []
    var active = false
    func prepare() async {}
    func begin() { active = true }
    func emit(_ pulse: NavigationPulse,name: String) { if active { pulses.append(pulse) } }
    func cancelPlayback() {}
    func stop() { active = false }
}

@MainActor
final class NavigationIntegrationTests: XCTestCase {
    private func setup() throws -> (URL,WaypointStore,FieldDataStore,AppSettings) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let settings = AppSettings(directory: dir); settings.declinationOverride = 0; settings.guideHoldOffSec = 0; settings.guideHeartbeatSec = 0
        return (dir,WaypointStore(directory: dir),FieldDataStore(directory: dir),settings)
    }
    private func route(_ field: FieldDataStore) throws -> Backup.Graphic {
        let r = Backup.Graphic(id: UUID().uuidString,name: "Patrol",type: "route",points: [.init(lat: 0,lon: 0),.init(lat: 0,lon: 0.001),.init(lat: 0.001,lon: 0.001)],createdAt: 1)
        try field.saveGraphic(r); return r
    }
    private func fix(_ lat: Double,_ lon: Double,_ date: Double,accuracy: Double = 2) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat,longitude: lon),altitude: 0,horizontalAccuracy: accuracy,verticalAccuracy: -1,timestamp: Date(timeIntervalSince1970: date))
    }
    private func wait(_ p: () -> Bool) async throws {
        let end = Date().addingTimeInterval(5)
        while !p() && Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(p())
    }
    func testRouteAdvancesInOrderOncePerFreshFixAndCompletesInBackground() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        var date = 1000.0, up = 100.0, foreground = true
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { foreground },scheduleTicks: false)
        let r = try route(field); nav.follow(r); try await wait { nav.running }
        driver.onLocations?([fix(0,0,date)])
        XCTAssertEqual(nav.progress?.index,1)
        driver.onLocations?([fix(0,0.001,date)]) // same timestamp cannot score another point
        XCTAssertEqual(nav.progress?.index,1)
        foreground = false; date += 1; up += 1
        driver.onLocations?([fix(0,0.001,date)])
        XCTAssertEqual(nav.progress?.index,2); XCTAssertTrue(driver.updating)
        date += 1; up += 1; driver.onLocations?([fix(0.001,0.001,date)])
        XCTAssertTrue(nav.progress?.complete == true); XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating)
        XCTAssertTrue(feedback.pulses.contains(.checkpoint)); XCTAssertEqual(feedback.pulses.last,.complete)
    }
    func testPauseResumeAndInterruptedRelaunchNeverStartGPSAutomatically() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        nav.pause(); XCTAssertFalse(driver.updating); XCTAssertTrue(nav.progress?.paused == true)
        nav.resume(); try await wait { nav.running }
        let other = GuideTestDriver()
        let reloaded = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: other,feedback: GuideTestFeedback(),foreground: { true },scheduleTicks: false)
        XCTAssertFalse(reloaded.running); XCTAssertFalse(other.updating); XCTAssertTrue(reloaded.progress?.paused == true)
        XCTAssertTrue(reloaded.status.contains("interrupted")); nav.stop()
    }
    func testHeadingFreshnessHoldDirectionAndPermissionLoss() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let wp = store.add(WaypointDraft(name: "East",lat: 0,lon: 0.01)); store.select(wp.id)
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { true },scheduleTicks: false)
        nav.startGuide(); try await wait { nav.running }
        driver.onHeading?(.init(magnetic: 105,accuracy: 5,timestamp: Date(timeIntervalSince1970: date)))
        driver.onLocations?([fix(0,0,date)])
        XCTAssertEqual(nav.decision?.cue,.left); XCTAssertTrue(feedback.pulses.contains(.left))
        up += 3; date += 3; nav.tick()
        XCTAssertEqual(nav.decision?.cue,.unavailable)
        driver.precise = false; driver.onAuthorization?()
        XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating); XCTAssertNotNil(nav.error)
        driver.precise = true; nav.startGuide(); try await wait { nav.running }
        nav.setHaptics(false)
        XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating); XCTAssertFalse(feedback.active)
    }
    func testRouteChangeOrTargetRemovalStopsSafely() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),foreground: { true },scheduleTicks: false)
        var r = try route(field); nav.follow(r); try await wait { nav.running }
        r.points[1].lon += 0.001; try field.saveGraphic(r)
        try await wait { !nav.running }; XCTAssertTrue(nav.error?.contains("changed") == true)
        nav.follow(r); try await wait { nav.running }
        let future = try XCTUnwrap(store.waypoints.first { $0.sourceRouteId == r.id && $0.sourceRoutePointIndex == 2 })
        store.delete(ids: [future.id])
        try await wait { !nav.running }; XCTAssertNotNil(nav.error)
    }
    func testAccuracyAndStaleSamplesCannotAdvanceRoute() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        driver.onLocations?([fix(0,0,980),fix(0,0,1000,accuracy: 30)])
        XCTAssertEqual(nav.progress?.index,0)
        driver.onLocations?([fix(0,0,1000,accuracy: 2)])
        XCTAssertEqual(nav.progress?.index,1); nav.stop()
    }
    func testSettingsPersistAndAndroidBackupApplyPreservesGuideFields() throws {
        let (dir,_,_,settings) = try setup()
        settings.guideAllowance = 20; settings.guideHoldOffSec = 3; settings.guideMode = 1; settings.guideCorridorM = 200
        let reloaded = AppSettings(directory: dir)
        XCTAssertEqual(reloaded.guideAllowance,20); XCTAssertEqual(reloaded.guideMode,1)
        var s = reloaded.backupSettings; s.guideHeartbeatSec = 60; s.guideAllowance = 15
        try reloaded.applyBackup(s)
        let final = AppSettings(directory: dir)
        XCTAssertEqual(final.guideHeartbeatSec,60); XCTAssertEqual(final.guideAllowance,15); XCTAssertEqual(final.guideCorridorM,200)
    }
    func testWallClockAdjustmentDoesNotBlockFreshRouteFixes() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        driver.onLocations?([fix(0,0,date)]); XCTAssertEqual(nav.progress?.index,1)
        date = 400; up += 1
        driver.onLocations?([fix(0,0.001,date)]); XCTAssertEqual(nav.progress?.index,2)
        nav.stop()
    }
    func testQuietBoundaryDetectionIsIndependentOfSteeringGuide() async throws {
        let (dir,store,field,settings) = try setup(), guideDriver = GuideTestDriver(), boundaryDriver = GuideTestDriver()
        let feedback = GuideTestFeedback(), boundaryAlerts = QuietBoundaryAlerts()
        let boundary = BoundaryMonitor(directory: dir,driver: boundaryDriver,alerts: boundaryAlerts,now: { Date(timeIntervalSince1970: 1002) },foreground: { true })
        let area = BoundaryArea(name: "Safe area",vertices: [.init(lat: -0.001,lon: -0.001),.init(lat: -0.001,lon: 0.001),.init(lat: 0.001,lon: 0.001),.init(lat: 0.001,lon: -0.001)])
        XCTAssertTrue(boundary.save(area)); boundary.start(area); try await wait { boundary.running }
        boundaryDriver.onLocations?([fix(0,0,1000),fix(0,0,1002)])
        let wp = store.add(WaypointDraft(name: "East",lat: 0,lon: 0.01)); store.select(wp.id)
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: guideDriver,feedback: feedback,now: { Date(timeIntervalSince1970: 1002) },uptime: { 100 },foreground: { true },scheduleTicks: false)
        nav.startGuide(); try await wait { nav.running }
        guideDriver.onHeading?(.init(magnetic: 105,accuracy: 5,timestamp: Date(timeIntervalSince1970: 1002)))
        guideDriver.onLocations?([fix(0,0,1002)])
        XCTAssertTrue(feedback.pulses.contains(.left)); XCTAssertEqual(boundaryAlerts.crossings,0)
        XCTAssertTrue(boundary.status.contains("quiet")); nav.stop(); XCTAssertTrue(boundaryDriver.updating)
        boundary.stop()
    }
    func testFailedProgressWriteStopsAndRetainsUnscoredCheckpoint() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        let file = dir.appendingPathComponent("navigation-session-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        driver.onLocations?([fix(0,0,1000)])
        XCTAssertFalse(nav.running); XCTAssertEqual(nav.progress?.index,0); XCTAssertFalse(driver.updating); XCTAssertNotNil(nav.error)
    }
}

@MainActor
private final class QuietBoundaryAlerts: BoundaryAlerting {
    let status = "Test alerts"
    var crossings = 0
    func prepare() async {}
    func begin() {}
    func crossing(name: String) { crossings += 1 }
    func stop() {}
}
