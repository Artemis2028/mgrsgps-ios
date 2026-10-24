import CoreLocation
import Combine
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
private final class PracticeGuideDriver: NavigationLocationDriver {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var precise = true, servicesEnabled = true, hasCompass = true, updating = false
    var stopCount = 0
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var onHeading: ((NavigationHeading) -> Void)?
    func requestPermission() {}
    func start() { updating = true }
    func stop() { updating = false; stopCount += 1 }
}
@MainActor
private final class PracticeGuideFeedback: NavigationFeedback {
    var status = "Test feedback"
    func prepare() async {}
    func begin() {}
    func emit(_ pulse: NavigationPulse,name: String) {}
    func cancelPlayback() {}
    func stop() {}
}

@MainActor
final class PracticeIntegrationTests: XCTestCase {
    private struct Fixture {
        let directory: URL, waypoints: WaypointStore, field: FieldDataStore, navigation: NavigationSession
        let first: Waypoint, second: Waypoint
    }
    private func fixture(driver: NavigationLocationDriver? = nil,feedback: NavigationFeedback? = nil) throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let waypoints = WaypointStore(directory: dir), field = FieldDataStore(directory: dir)
        let a = waypoints.add(.init(name: "A",lat: 24,lon: 54,folder: "Drill")), b = waypoints.add(.init(name: "B",lat: 24.01,lon: 54,folder: "Drill"))
        let nav = NavigationSession(directory: dir,store: waypoints,field: field,settings: AppSettings(directory: dir),driver: driver,feedback: feedback,foreground: { true },scheduleTicks: false)
        return .init(directory: dir,waypoints: waypoints,field: field,navigation: nav,first: a,second: b)
    }
    private func fix(_ waypoint: Waypoint,accuracy: Double = 2,up: Double = 100) -> Fix {
        .init(lat: waypoint.lat,lon: waypoint.lon,accuracyMeters: accuracy,altitudeMeters: nil,speedMetersPerSecond: nil,timestamp: Date(),timestampUptime: up)
    }
    func testHiddenFolderCourseLocksSelectionAndRouteFollowingWithoutRewritingRoutePoints() throws {
        let f = try fixture(), course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        f.waypoints.setFolderVisible("Drill",visible: false); course.startFolder("Drill")
        XCTAssertEqual(f.waypoints.selectedId,f.first.id); XCTAssertTrue(f.waypoints.practiceNavigationLocked)
        f.waypoints.select(f.second.id); XCTAssertEqual(f.waypoints.selectedId,f.first.id)
        let route = Backup.Graphic(id: "route",name: "Patrol",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 25,lon: 54)])
        try f.field.saveGraphic(route); f.navigation.follow(route)
        XCTAssertFalse(f.navigation.running); XCTAssertTrue(f.navigation.error?.contains("practice course") == true)
        XCTAssertEqual(f.waypoints.waypoints.count,2)
    }
    func testForegroundPreciseFixesScoreTimedSplitsAndPersistHistory() throws {
        let f = try fixture(); var wall = 1000.0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,now: { Date(timeIntervalSince1970: wall) },uptime: { 100 })
        course.startFolder("Drill")
        course.receive(fix(f.first)); XCTAssertEqual(course.active?.nextIndex,0)
        course.setForeground(true)
        course.receive(fix(f.first,accuracy: 26)); course.receive(fix(f.first,up: 80)); XCTAssertEqual(course.active?.nextIndex,0)
        wall += 1; course.receive(fix(f.first)); XCTAssertEqual(course.active?.nextIndex,1); XCTAssertEqual(f.waypoints.selectedId,f.second.id)
        wall += 1; course.receive(fix(f.second)); XCTAssertNil(course.active); XCTAssertFalse(f.waypoints.practiceNavigationLocked)
        XCTAssertEqual(f.field.document.courseHistory.first?.total,2000); XCTAssertEqual(f.field.document.courseHistory.first?.splits,[1000,1000])
        XCTAssertEqual(FieldDataStore(directory: f.directory).document.courseHistory.count,1)
        XCTAssertNil(PracticeCourseStore(directory: f.directory).active)
    }
    func testDeletedFutureCheckpointPersistsPauseAndOnlyOriginalIDRestoresSameRun() throws {
        let f = try fixture(), original = f.waypoints.waypoints
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        course.startFolder("Drill"); let run = course.active?.runID
        f.waypoints.delete(ids: [f.second.id]); course.reconcile()
        XCTAssertEqual(course.active?.missingIDs,[f.second.id]); XCTAssertNil(f.waypoints.selectedId)
        _ = f.waypoints.add(.init(name: "B",lat: f.second.lat,lon: f.second.lon,folder: "Drill")); course.reconcile()
        XCTAssertTrue(course.active?.paused == true)
        let reopened = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        XCTAssertEqual(reopened.active?.runID,run); XCTAssertTrue(reopened.active?.paused == true)
        _ = try f.waypoints.restore(waypoints: original,folders: []); reopened.reconcile()
        XCTAssertFalse(reopened.active?.paused ?? true); XCTAssertEqual(f.waypoints.selectedId,f.first.id)
    }
    func testStaleEndCannotAbandonReplacementAndGeneratedPointsRemainAfterEnd() throws {
        let f = try fixture(), course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,uptime: { 100 })
        course.startFolder("Drill"); let old = course.active?.runID; course.end(expectedRunID: old)
        course.startRandom(count: 3,radius: 500,fix: fix(f.first))
        let current = course.active?.runID; XCTAssertNotNil(current); XCTAssertNotEqual(old,current)
        course.end(expectedRunID: old); XCTAssertEqual(course.active?.runID,current)
        course.end(expectedRunID: current); XCTAssertNil(course.active); XCTAssertEqual(f.waypoints.waypoints.count,5); XCTAssertTrue(f.field.document.courseHistory.isEmpty)
    }
    func testDeletingFutureCheckpointStopsRunningGuideAndClearsTarget() async throws {
        let driver = PracticeGuideDriver(), feedback = PracticeGuideFeedback()
        let f = try fixture(driver: driver,feedback: feedback)
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        course.startFolder("Drill"); f.navigation.startGuide()
        let deadline = Date().addingTimeInterval(5)
        while !f.navigation.running && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(f.navigation.running); XCTAssertTrue(driver.updating)
        f.waypoints.delete(ids: [f.second.id]); course.reconcile()
        XCTAssertFalse(f.navigation.running); XCTAssertFalse(driver.updating)
        XCTAssertTrue(course.active?.paused == true); XCTAssertNil(f.waypoints.selectedId)
        let stops = driver.stopCount
        for _ in 0..<5 { course.reconcile() }
        XCTAssertEqual(driver.stopCount,stops,"A stable missing checkpoint must not repeatedly stop/persist the guide on every UI timer tick")
    }
    func testRecoveredCourseClearsInterruptedRouteWithoutRestartingGPS() async throws {
        let driver = PracticeGuideDriver(), feedback = PracticeGuideFeedback()
        let f = try fixture(driver: driver,feedback: feedback)
        let route = Backup.Graphic(id: "interrupted-route",name: "Patrol",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)])
        try f.field.saveGraphic(route); f.navigation.follow(route)
        let deadline = Date().addingTimeInterval(5)
        while !f.navigation.running && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(f.navigation.running)
        // Simulate death after course save but before the old route is cleared.
        try PracticeCourseStore(directory: f.directory).save(PracticeCourse(name: "Drill",waypointIDs: [f.first.id,f.second.id],startedAt: 100))
        f.navigation.pause()
        let restoredNav = NavigationSession(directory: f.directory,store: f.waypoints,field: f.field,settings: AppSettings(directory: f.directory),driver: driver,feedback: feedback,scheduleTicks: false)
        XCTAssertNotNil(restoredNav.progress)
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: restoredNav)
        XCTAssertNotNil(course.active); XCTAssertNil(restoredNav.progress)
        XCTAssertFalse(restoredNav.running); XCTAssertFalse(driver.updating); XCTAssertEqual(f.waypoints.selectedId,f.first.id)
    }
    func testHistoryCommittedBeforeFailedActiveClearRecoversExactlyOnce() throws {
        let f = try fixture(); var wall = 1000.0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,now: { Date(timeIntervalSince1970: wall) },uptime: { 100 })
        course.startFolder("Drill"); course.setForeground(true); wall += 1; course.receive(fix(f.first))
        let path = f.directory.appendingPathComponent("practice-course-v1.json")
        var retained: Data?
        let observer = f.field.$document.dropFirst().sink { doc in
            guard !doc.courseHistory.isEmpty, retained == nil else { return }
            retained = try? Data(contentsOf: path)
            try? FileManager.default.removeItem(at: path); try? FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        }
        wall += 1; course.receive(fix(f.second)); observer.cancel()
        XCTAssertTrue(course.active?.done == true); XCTAssertEqual(f.field.document.courseHistory.count,1); XCTAssertNotNil(course.error)
        course.end(expectedRunID: course.active?.runID); XCTAssertNotNil(course.active)
        try FileManager.default.removeItem(at: path); try XCTUnwrap(retained).write(to: path)
        let reopened = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        XCTAssertNil(reopened.active); XCTAssertEqual(f.field.document.courseHistory.count,1)
    }
}
