import CoreLocation
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
private final class RecordingTestDriver: RecordingLocationDriver {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var precise = true
    var servicesEnabled = true
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var updating = false
    var requestedPermission = false
    func requestPermission() { requestedPermission = true }
    func start() { updating = true }
    func stop() { updating = false }
}

@MainActor
private final class RecordingTestClock {
    var date = Date(timeIntervalSince1970: 1_700_000_000)
    var uptime = 1000.0
    var foreground = true
    func advance(_ seconds: Double) { date.addTimeInterval(seconds); uptime += seconds }
    func location(_ lat: Double, secondsAgo: Double = 0, verticalAccuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: 54), altitude: 15,
                   horizontalAccuracy: 5, verticalAccuracy: verticalAccuracy, timestamp: date.addingTimeInterval(-secondsAgo))
    }
}

@MainActor
final class TrackRecorderIntegrationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(predicate(), "Recorder did not reach the expected state")
        if !predicate() { throw NSError(domain: "Recorder timeout", code: 1) }
    }
    private func recorder(_ directory: URL, _ field: FieldDataStore, _ driver: RecordingTestDriver, _ clock: RecordingTestClock) async throws -> TrackRecorder {
        let recorder = TrackRecorder(directory: directory, fieldData: field, driver: driver,
                                     now: { clock.date }, uptime: { clock.uptime }, isForeground: { clock.foreground })
        try await wait { recorder.phase == .idle }
        return recorder
    }

    func testBatchedFixesContinueWhenForegroundPositionManagerStopsAndQueuedFixesFinishBeforeSave() async throws {
        let dir = try directory(), field = FieldDataStore(directory: dir), driver = RecordingTestDriver(), clock = RecordingTestClock()
        let rec = try await recorder(dir, field, driver, clock)
        rec.start(); try await wait { rec.phase == .recording }
        clock.advance(2); driver.onLocations?([clock.location(24)])
        try await wait { rec.active?.pointCount == 1 }
        let live=try XCTUnwrap(rec.liveActivitySession(settings:AppSettings(directory:dir)))
        XCTAssertTrue(live.state.detail.contains("1 saved points"));XCTAssertTrue(live.state.hasFreshFix(at:clock.date,uptime:clock.uptime))
        clock.foreground = false
        LocationService().stop() // independent position/heading manager
        XCTAssertTrue(driver.updating)
        clock.advance(10)
        driver.onLocations?([clock.location(24.0001, secondsAgo: 5), clock.location(24.0002, verticalAccuracy: 0)])
        rec.stop(name: "Patrol") // must wait for both queued fixes
        try await wait { rec.phase == .idle }
        XCTAssertNil(rec.liveActivitySession(settings:AppSettings(directory:dir)))
        XCTAssertFalse(driver.updating)
        let track = try XCTUnwrap(field.document.tracks.first)
        XCTAssertEqual(track.name, "Patrol"); XCTAssertEqual(track.pointCount, 3)
        let points = try field.points(for: track.id)
        XCTAssertEqual(points.map(\.lat), [24, 24.0001, 24.0002])
        XCTAssertEqual(points[0].altitudeMeters, 15)
        XCTAssertNil(points[2].altitudeMeters, "Invalid altitude must not become a fake GPX height")
        driver.onLocations?([clock.location(25)])
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(try field.points(for: track.id).count, 3)
        XCTAssertFalse(try TrackRecordingJournal(directory: dir).hasPendingSession)
    }

    func testPermissionLossStopsAndKeepsSavedPoints() async throws {
        let dir = try directory(), field = FieldDataStore(directory: dir), driver = RecordingTestDriver(), clock = RecordingTestClock()
        let rec = try await recorder(dir, field, driver, clock)
        rec.start(); try await wait { rec.phase == .recording }
        clock.advance(2); driver.onLocations?([clock.location(24)])
        try await wait { rec.active?.pointCount == 1 }
        driver.precise = false; driver.onAuthorization?()
        XCTAssertFalse(driver.updating)
        try await wait { rec.phase == .idle }
        XCTAssertEqual(field.document.tracks.first?.pointCount, 1)
        XCTAssertTrue(rec.failure?.contains("permission changed") == true)
        rec.start()
        XCTAssertEqual(rec.phase, .idle)
        XCTAssertFalse(driver.updating)
    }

    func testPermissionRequestStartsOnlyAfterGrantWhileForeground() async throws {
        let dir = try directory(), field = FieldDataStore(directory: dir), driver = RecordingTestDriver(), clock = RecordingTestClock()
        driver.authorization = .notDetermined
        let rec = try await recorder(dir, field, driver, clock)
        rec.start()
        XCTAssertEqual(rec.phase, .requestingPermission); XCTAssertTrue(driver.requestedPermission)
        clock.foreground = false; driver.authorization = .authorizedWhenInUse; driver.onAuthorization?()
        XCTAssertEqual(rec.phase, .idle); XCTAssertFalse(driver.updating)
        clock.foreground = true; rec.start(); try await wait { rec.phase == .recording }
        rec.stop(); try await wait { rec.phase == .idle }
        XCTAssertEqual(field.document.tracks.first?.pointCount, 0)
    }

    func testTransientLocationErrorWaitsButDeniedErrorFinalizes() async throws {
        let dir = try directory(), field = FieldDataStore(directory: dir), driver = RecordingTestDriver(), clock = RecordingTestClock()
        let rec = try await recorder(dir, field, driver, clock)
        rec.start(); try await wait { rec.phase == .recording }
        driver.onFailure?(CLError(.locationUnknown))
        XCTAssertTrue(driver.updating); XCTAssertEqual(rec.phase, .recording)
        clock.advance(2); driver.onLocations?([clock.location(24)])
        try await wait { rec.active?.pointCount == 1 }
        driver.onFailure?(CLError(.denied))
        try await wait { rec.phase == .idle }
        XCTAssertEqual(field.document.tracks.first?.pointCount, 1)
        XCTAssertNotNil(rec.failure)
    }

    func testFailedFinalizationCanRetryWithoutLosingJournalOrDuplicatingTrack() async throws {
        let dir = try directory(), field = FieldDataStore(directory: dir), driver = RecordingTestDriver(), clock = RecordingTestClock()
        let rec = try await recorder(dir, field, driver, clock)
        rec.start(); try await wait { rec.phase == .recording }
        clock.advance(2); driver.onLocations?([clock.location(24)])
        try await wait { rec.active?.pointCount == 1 }
        let blocked = dir.appendingPathComponent("field-data-v1.zip")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        rec.stop(name: "Keep me")
        try await wait { rec.phase == .recoveryRequired }
        XCTAssertTrue(field.document.tracks.isEmpty)
        XCTAssertTrue(try TrackRecordingJournal(directory: dir).hasPendingSession)
        try FileManager.default.removeItem(at: blocked)
        rec.recover(); try await wait { rec.phase == .idle }
        XCTAssertEqual(field.document.tracks.count, 1)
        XCTAssertEqual(field.document.tracks.first?.name, "Keep me")
        XCTAssertNil(rec.failure)
        XCTAssertFalse(try TrackRecordingJournal(directory: dir).hasPendingSession)
    }

    func testRelaunchRecoversInterruptedLogWithoutStartingGPS() async throws {
        let dir = try directory(), field = FieldDataStore(directory: dir), driver = RecordingTestDriver(), clock = RecordingTestClock()
        let journal = try TrackRecordingJournal(directory: dir)
        try journal.start(now: 1_700_000_000_000, uptime: 1000)
        _ = try journal.append(.init(point: .init(lat: 24, lon: 54, time: 1_700_000_001_000), accuracyMeters: 5, uptime: 1001))
        let rec = try await recorder(dir, field, driver, clock)
        XCTAssertFalse(driver.updating); XCTAssertEqual(rec.phase, .idle)
        XCTAssertEqual(field.document.tracks.first?.pointCount, 1)
        XCTAssertTrue(rec.message?.contains("Recovered") == true)
    }

    func testCorruptJournalIsPreservedUntilExplicitDiscard() async throws {
        let dir = try directory(), field = FieldDataStore(directory: dir), driver = RecordingTestDriver(), clock = RecordingTestClock()
        let folder = dir.appendingPathComponent("LiveRecording")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("session.json"), raw = Data("corrupt".utf8)
        try raw.write(to: file)
        let rec = TrackRecorder(directory: dir, fieldData: field, driver: driver, now: { clock.date }, uptime: { clock.uptime })
        try await wait { rec.phase == .recoveryRequired }
        XCTAssertEqual(try Data(contentsOf: file), raw)
        rec.discard(); try await wait { rec.phase == .idle }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testRealDriverAndJournalAreConfiguredForLockedScreenRecording() throws {
        XCTAssertTrue((Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true)
        let driver = CoreLocationRecordingDriver()
        #if targetEnvironment(simulator)
        XCTAssertEqual(driver.authorization, .authorizedWhenInUse, "Recording tests must exercise While Using permission, not an earlier Always grant")
        #endif
        guard driver.authorization == .authorizedWhenInUse || driver.authorization == .authorizedAlways else {
            throw XCTSkip("Simulator needs Location permission for the real-driver configuration check")
        }
        driver.start(); defer { driver.stop() }
        XCTAssertTrue(driver.backgroundEnabled)
        XCTAssertTrue(driver.showsIndicator)
        XCTAssertFalse(driver.automaticallyPauses)
        let dir = try directory(), journal = try TrackRecordingJournal(directory: dir)
        try journal.start(now: 1_700_000_000_000, uptime: 1000)
        for name in ["LiveRecording", "LiveRecording/session.json", "LiveRecording/points.txt"] {
            #if !targetEnvironment(simulator)
            let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
            XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
            #else
            // Simulator files have no Data Protection class. Assert those
            // attributes on a physical device; still exercise creation here.
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path))
            #endif
        }
    }
}
