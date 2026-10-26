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
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition())
    }
    private func fix(_ waypoint: Waypoint,accuracy: Double = 2,up: Double = 100) -> Fix {
        .init(lat: waypoint.lat,lon: waypoint.lon,accuracyMeters: accuracy,altitudeMeters: nil,speedMetersPerSecond: nil,timestamp: Date(),timestampUptime: up)
    }
    func testBlockedScoreDoesNotPublishOrBuzzEarlyAndDuplicatesScoreOnce() async throws {
        let f = try fixture(), gate = PracticeSaveGate(); var buzzes = 0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,uptime: { 100 },prepareCourse: { try gate.prepare($0,$1) },scoreFeedback: { buzzes += 1 })
        course.startFolder("Drill"); try await wait { !course.working }; course.setForeground(true)
        gate.arm(); course.receive(fix(f.first)); try await wait { gate.entered }
        XCTAssertTrue(course.working); XCTAssertEqual(course.active?.nextIndex,0); XCTAssertEqual(buzzes,0)
        XCTAssertEqual(PracticeCourseStore(directory: f.directory).active?.nextIndex,0)
        course.receive(fix(f.first)); course.receive(fix(f.first)); course.reconcile()
        gate.release(); try await wait { !course.working && gate.returned }
        XCTAssertEqual(course.active?.nextIndex,1); XCTAssertEqual(buzzes,1)
        XCTAssertEqual(PracticeCourseStore(directory: f.directory).active?.nextIndex,1)
    }
    func testEndDuringBlockedScoreCannotPublishLateScoreOrBuzz() async throws {
        let f = try fixture(), gate = PracticeSaveGate(); var buzzes = 0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,uptime: { 100 },prepareCourse: { try gate.prepare($0,$1) },scoreFeedback: { buzzes += 1 })
        course.startFolder("Drill"); try await wait { !course.working }; course.setForeground(true)
        gate.arm(); course.receive(fix(f.first)); try await wait { gate.entered }
        course.end(expectedRunID: course.active?.runID); gate.release()
        try await wait { !course.working && gate.returned }
        XCTAssertNil(course.active); XCTAssertNil(PracticeCourseStore(directory: f.directory).active)
        XCTAssertEqual(buzzes,0); XCTAssertTrue(f.field.document.courseHistory.isEmpty)
        XCTAssertFalse(f.waypoints.practiceNavigationLocked)
    }
    func testDeletedCheckpointDuringBlockedScoreCannotBeFound() async throws {
        let f = try fixture(), gate = PracticeSaveGate(); var buzzes = 0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,uptime: { 100 },prepareCourse: { try gate.prepare($0,$1) },scoreFeedback: { buzzes += 1 })
        course.startFolder("Drill"); try await wait { !course.working }; course.setForeground(true)
        gate.arm(); course.receive(fix(f.first)); try await wait { gate.entered }
        f.waypoints.delete(ids: [f.first.id]); gate.release()
        try await wait { !course.working && gate.returned }
        XCTAssertEqual(course.active?.nextIndex,0); XCTAssertTrue(course.active?.paused == true)
        XCTAssertEqual(PracticeCourseStore(directory: f.directory).active?.nextIndex,0)
        XCTAssertEqual(buzzes,0); XCTAssertNil(f.waypoints.selectedId)
    }
    func testAcceptedForegroundScoreFinishesAfterBackgroundWithoutMoreScoring() async throws {
        let f = try fixture(), gate = PracticeSaveGate(); var buzzes = 0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,uptime: { 100 },prepareCourse: { try gate.prepare($0,$1) },scoreFeedback: { buzzes += 1 })
        course.startFolder("Drill"); try await wait { !course.working }; course.setForeground(true)
        gate.arm(); course.receive(fix(f.first)); try await wait { gate.entered }
        course.setForeground(false); course.receive(fix(f.second)); gate.release()
        try await wait { !course.working && gate.returned }
        XCTAssertEqual(course.active?.nextIndex,1); XCTAssertEqual(buzzes,0)
        course.receive(fix(f.second)); XCTAssertEqual(course.active?.nextIndex,1)
    }
    func testFailedStartRetriesSameRequestAndDoesNotLockOrdinaryTargetChoice() async throws {
        let f = try fixture(), gate = PracticeSaveGate(); var wall = 1000.0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,now: { Date(timeIntervalSince1970: wall) },prepareCourse: { try gate.prepare($0,$1) })
        let file = f.directory.appendingPathComponent("practice-course-v1.json")
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        course.startFolder("Drill"); try await wait { !course.working }
        XCTAssertNil(course.active); XCTAssertTrue(course.hasPendingWrite); XCTAssertFalse(course.locked)
        let id = gate.proposedIDs.first!
        wall = 1200; try FileManager.default.removeItem(at: file)
        course.retryWrite(); try await wait { !course.working }
        XCTAssertEqual(course.active?.runID,id); XCTAssertEqual(course.active?.startedAt,1_000_000)
        XCTAssertFalse(course.hasPendingWrite); XCTAssertTrue(f.waypoints.practiceNavigationLocked)
    }
    func testFailedCourseStartKeepsExistingOrdinaryGuideRunning() async throws {
        let driver = PracticeGuideDriver(), feedback = PracticeGuideFeedback()
        let f = try fixture(driver: driver,feedback: feedback)
        try f.waypoints.selectDurably(f.first.id); f.navigation.startGuide(); try await wait { f.navigation.running }
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        try FileManager.default.createDirectory(at: f.directory.appendingPathComponent("practice-course-v1.json"),withIntermediateDirectories: false)
        course.startFolder("Drill"); try await wait { !course.working }
        XCTAssertTrue(course.hasPendingWrite); XCTAssertFalse(course.locked)
        XCTAssertTrue(f.navigation.running); XCTAssertTrue(driver.updating)
        try f.waypoints.selectDurably(f.second.id)
        XCTAssertEqual(f.waypoints.selectedId,f.second.id)
        f.navigation.stop(); try await wait { !f.navigation.saving }
    }
    func testFailedRandomStartRetryKeepsOneSetOfGeneratedCheckpoints() async throws {
        let f = try fixture(), course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,uptime: { 100 })
        let file = f.directory.appendingPathComponent("practice-course-v1.json")
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        course.startRandom(count: 3,radius: 500,fix: fix(f.first)); try await wait { !course.working }
        let ids = f.waypoints.waypoints.map(\.id)
        XCTAssertEqual(ids.count,5); XCTAssertTrue(course.hasPendingWrite)
        course.startRandom(count: 3,radius: 500,fix: fix(f.first))
        XCTAssertEqual(f.waypoints.waypoints.map(\.id),ids)
        try FileManager.default.removeItem(at: file); course.retryWrite(); try await wait { !course.working }
        XCTAssertEqual(course.active?.waypointIDs,Array(ids.dropFirst(2)))
        XCTAssertEqual(f.waypoints.waypoints.map(\.id),ids)
        course.end(expectedRunID: course.active?.runID); try await wait { !course.working }
        XCTAssertEqual(f.waypoints.waypoints.map(\.id),ids)
    }
    func testFailedScoreRetryKeepsAcceptedTimeAndDoesNotRetryFromTimers() async throws {
        let f = try fixture(); var wall = 1000.0, buzzes = 0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,now: { Date(timeIntervalSince1970: wall) },uptime: { 100 },scoreFeedback: { buzzes += 1 })
        course.startFolder("Drill"); try await wait { !course.working }; course.setForeground(true)
        let file = f.directory.appendingPathComponent("practice-course-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        wall += 1; course.receive(fix(f.first)); try await wait { !course.working }
        XCTAssertEqual(course.active?.nextIndex,0); XCTAssertTrue(course.hasPendingWrite); XCTAssertEqual(buzzes,0)
        for _ in 0..<3 { course.receive(fix(f.first)); course.reconcile() }
        XCTAssertFalse(course.working)
        wall = 1200; try FileManager.default.removeItem(at: file); course.retryWrite(); try await wait { !course.working }
        XCTAssertEqual(course.active?.foundAt,[1_001_000]); XCTAssertEqual(buzzes,1)
        XCTAssertEqual(PracticeCourseStore(directory: f.directory).active?.foundAt,[1_001_000])
    }
    func testFailedUnlockPreferenceAfterEndIsActuallyRetried() async throws {
        let f = try fixture(), course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        course.startFolder("Drill"); try await wait { !course.working }
        let path = f.directory.appendingPathComponent("waypoints-v1.json")
        var blocked = false
        let observer = course.$active.dropFirst().sink { value in
            guard value == nil, !blocked else { return }; blocked = true
            try? FileManager.default.removeItem(at: path); try? FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        }
        course.end(expectedRunID: course.active?.runID); try await wait { !course.working }; observer.cancel()
        XCTAssertNil(course.active); XCTAssertTrue(course.hasPendingWrite); XCTAssertTrue(f.waypoints.practiceNavigationSavePending)
        try FileManager.default.removeItem(at: path); course.retryWrite()
        XCTAssertFalse(course.hasPendingWrite); XCTAssertFalse(f.waypoints.practiceNavigationSavePending); XCTAssertNil(course.error)
        XCTAssertEqual(WaypointStore(directory: f.directory).selectedId,f.waypoints.selectedId)
    }
    func testDamagedResetCanRecoverAfterTargetWriteFailure() async throws {
        let f = try fixture(), file = f.directory.appendingPathComponent("practice-course-v1.json")
        let broken = Data("SYNTHETIC unreadable course".utf8); try broken.write(to: file)
        let targetFile = f.directory.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: targetFile); try FileManager.default.createDirectory(at: targetFile,withIntermediateDirectories: false)
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        XCTAssertTrue(course.damaged); XCTAssertTrue(course.hasPendingWrite)
        try FileManager.default.removeItem(at: targetFile); course.resetDamaged()
        XCTAssertFalse(course.damaged); XCTAssertFalse(course.hasPendingWrite); XCTAssertFalse(course.blockedByStorage)
        XCTAssertFalse(f.waypoints.practiceNavigationLocked)
        let archived = try FileManager.default.contentsOfDirectory(at: f.directory,includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("practice-course-damaged-") }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archived)),broken)
    }
    func testHiddenFolderCourseLocksSelectionAndRouteFollowingWithoutRewritingRoutePoints() async throws {
        let f = try fixture(), course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        f.waypoints.setFolderVisible("Drill",visible: false); course.startFolder("Drill"); try await wait { !course.working && !course.finalizing }
        XCTAssertEqual(f.waypoints.selectedId,f.first.id); XCTAssertTrue(f.waypoints.practiceNavigationLocked)
        f.waypoints.select(f.second.id); XCTAssertEqual(f.waypoints.selectedId,f.first.id)
        let route = Backup.Graphic(id: "route",name: "Patrol",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 25,lon: 54)])
        try f.field.saveGraphic(route); f.navigation.follow(route)
        XCTAssertFalse(f.navigation.running); XCTAssertTrue(f.navigation.error?.contains("practice course") == true)
        XCTAssertEqual(f.waypoints.waypoints.count,2)
    }
    func testForegroundPreciseFixesScoreTimedSplitsAndPersistHistory() async throws {
        let f = try fixture(); var wall = 1000.0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,now: { Date(timeIntervalSince1970: wall) },uptime: { 100 })
        course.startFolder("Drill"); try await wait { !course.working && !course.finalizing }
        course.receive(fix(f.first)); XCTAssertEqual(course.active?.nextIndex,0)
        course.setForeground(true)
        course.receive(fix(f.first,accuracy: 26)); course.receive(fix(f.first,up: 80)); XCTAssertEqual(course.active?.nextIndex,0)
        wall += 1; course.receive(fix(f.first)); try await wait { !course.working }; XCTAssertEqual(course.active?.nextIndex,1); XCTAssertEqual(f.waypoints.selectedId,f.second.id)
        wall += 1; course.receive(fix(f.second)); try await wait { !course.working && !course.finalizing }; XCTAssertNil(course.active); XCTAssertFalse(f.waypoints.practiceNavigationLocked)
        XCTAssertEqual(f.field.document.courseHistory.first?.total,2000); XCTAssertEqual(f.field.document.courseHistory.first?.splits,[1000,1000])
        XCTAssertEqual(FieldDataStore(directory: f.directory).document.courseHistory.count,1)
        XCTAssertNil(PracticeCourseStore(directory: f.directory).active)
    }
    func testDeletedFutureCheckpointPersistsPauseAndOnlyOriginalIDRestoresSameRun() async throws {
        let f = try fixture(), original = f.waypoints.waypoints
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        course.startFolder("Drill"); try await wait { !course.working && !course.finalizing }; let run = course.active?.runID
        f.waypoints.delete(ids: [f.second.id]); course.reconcile(); try await wait { !course.working }
        XCTAssertEqual(course.active?.missingIDs,[f.second.id]); XCTAssertNil(f.waypoints.selectedId)
        _ = f.waypoints.add(.init(name: "B",lat: f.second.lat,lon: f.second.lon,folder: "Drill")); course.reconcile(); try await wait { !course.working }
        XCTAssertTrue(course.active?.paused == true)
        let reopened = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        XCTAssertEqual(reopened.active?.runID,run); XCTAssertTrue(reopened.active?.paused == true)
        _ = try f.waypoints.restore(waypoints: original,folders: []); reopened.reconcile(); try await wait { !reopened.working && !reopened.finalizing }
        XCTAssertFalse(reopened.active?.paused ?? true); XCTAssertEqual(f.waypoints.selectedId,f.first.id)
    }
    func testStaleEndCannotAbandonReplacementAndGeneratedPointsRemainAfterEnd() async throws {
        let f = try fixture(), course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,uptime: { 100 })
        course.startFolder("Drill"); try await wait { !course.working && !course.finalizing }; let old = course.active?.runID; course.end(expectedRunID: old); try await wait { !course.working }
        course.startRandom(count: 3,radius: 500,fix: fix(f.first)); try await wait { !course.working }
        let current = course.active?.runID; XCTAssertNotNil(current); XCTAssertNotEqual(old,current)
        course.end(expectedRunID: old); try await wait { !course.working }; XCTAssertEqual(course.active?.runID,current)
        course.end(expectedRunID: current); try await wait { !course.working }; XCTAssertNil(course.active); XCTAssertEqual(f.waypoints.waypoints.count,5); XCTAssertTrue(f.field.document.courseHistory.isEmpty)
    }
    func testDeletingFutureCheckpointStopsRunningGuideAndClearsTarget() async throws {
        let driver = PracticeGuideDriver(), feedback = PracticeGuideFeedback()
        let f = try fixture(driver: driver,feedback: feedback)
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        course.startFolder("Drill"); try await wait { !course.working && !course.finalizing }; f.navigation.startGuide()
        let deadline = Date().addingTimeInterval(5)
        while !f.navigation.running && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(f.navigation.running); XCTAssertTrue(driver.updating)
        f.waypoints.delete(ids: [f.second.id]); course.reconcile(); try await wait { !course.working }
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
        f.navigation.pause(); try await wait { !f.navigation.saving }
        let restoredNav = NavigationSession(directory: f.directory,store: f.waypoints,field: f.field,settings: AppSettings(directory: f.directory),driver: driver,feedback: feedback,scheduleTicks: false)
        XCTAssertNotNil(restoredNav.progress)
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: restoredNav)
        XCTAssertNotNil(course.active); XCTAssertNil(restoredNav.progress)
        XCTAssertFalse(restoredNav.running); XCTAssertFalse(driver.updating); XCTAssertEqual(f.waypoints.selectedId,f.first.id)
    }
    func testFailedHistoryPublicationKeepsCompletedRunAndRetryFinishesExactlyOnce() async throws {
        let f = try fixture(); var wall = 1000.0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,now: { Date(timeIntervalSince1970: wall) },uptime: { 100 })
        course.startFolder("Drill"); try await wait { !course.working && !course.finalizing }; course.setForeground(true); wall += 1; course.receive(fix(f.first)); try await wait { !course.working }
        let path = f.directory.appendingPathComponent("field-data-v1.zip")
        try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        wall += 1; course.receive(fix(f.second))
        try await wait { course.active?.done == true }
        XCTAssertTrue(PracticeCourseStore(directory: f.directory).active?.done == true)
        // A second receipt/reconcile must not start a second finalizer or abandon.
        course.receive(fix(f.second)); course.reconcile(); course.end(expectedRunID: course.active?.runID)
        try await wait { !course.working && !course.finalizing }
        XCTAssertNotNil(course.error); XCTAssertTrue(course.blockedByStorage)
        XCTAssertTrue(course.active?.done == true); XCTAssertTrue(f.field.document.courseHistory.isEmpty)
        XCTAssertTrue(PracticeCourseStore(directory: f.directory).active?.done == true)
        let retainedError = course.error
        for _ in 0..<3 { course.receive(fix(f.second)); course.reconcile() }
        XCTAssertFalse(course.finalizing); XCTAssertEqual(course.error,retainedError,"A timer must not retry a failed full-archive save every second")
        let subscription = f.field.$document.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        defer { subscription.cancel() }
        try FileManager.default.removeItem(at: path)
        course.retryResult(); try await wait { !course.working && !course.finalizing }
        XCTAssertNil(course.active); XCTAssertNotNil(course.summary); XCTAssertFalse(course.blockedByStorage)
        XCTAssertEqual(FieldDataStore(directory: f.directory).document.courseHistory.count,1)
        XCTAssertNil(PracticeCourseStore(directory: f.directory).active)
        course.reconcile(); XCTAssertEqual(f.field.document.courseHistory.count,1)
    }
    func testHistoryCommittedBeforeFailedActiveClearRecoversExactlyOnce() async throws {
        let f = try fixture(); var wall = 1000.0
        let course = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation,now: { Date(timeIntervalSince1970: wall) },uptime: { 100 })
        course.startFolder("Drill"); try await wait { !course.working && !course.finalizing }; course.setForeground(true); wall += 1; course.receive(fix(f.first)); try await wait { !course.working }
        let path = f.directory.appendingPathComponent("practice-course-v1.json")
        var retained: Data?
        let observer = f.field.$document.dropFirst().sink { doc in
            guard !doc.courseHistory.isEmpty, retained == nil else { return }
            retained = try? Data(contentsOf: path)
            try? FileManager.default.removeItem(at: path); try? FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        }
        wall += 1; course.receive(fix(f.second)); try await wait { !course.working && !course.finalizing }; observer.cancel()
        XCTAssertTrue(course.active?.done == true); XCTAssertEqual(f.field.document.courseHistory.count,1); XCTAssertNotNil(course.error)
        course.end(expectedRunID: course.active?.runID); XCTAssertNotNil(course.active)
        try FileManager.default.removeItem(at: path); try XCTUnwrap(retained).write(to: path)
        let reopened = PracticeSession(directory: f.directory,waypoints: f.waypoints,field: f.field,navigation: f.navigation)
        try await wait { !reopened.working && !reopened.finalizing }
        XCTAssertNil(reopened.active); XCTAssertEqual(f.field.document.courseHistory.count,1)
    }
}

private final class PracticeSaveGate: @unchecked Sendable {
    private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
    private var armed = false, didEnter = false, didReturn = false
    private var ids: [String?] = []
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return didEnter }
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    var proposedIDs: [String?] { lock.lock(); defer { lock.unlock() }; return ids }
    func arm() { lock.lock(); armed = true; didEnter = false; didReturn = false; lock.unlock() }
    func release() { semaphore.signal() }
    func prepare(_ snapshot: PracticeCourseStore.SaveSnapshot,_ value: PracticeCourse?) throws -> PracticeCourseStore.PreparedSave {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); ids.append(value?.runID); let block = armed; armed = false
        if block { didEnter = true }; lock.unlock()
        defer { if block { lock.lock(); didReturn = true; lock.unlock() } }
        if block, semaphore.wait(timeout: .now()+5) != .success { throw PracticeCourseError.invalid("Test course gate timed out") }
        return try snapshot.prepare(value)
    }
}
