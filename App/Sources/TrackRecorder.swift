import CoreLocation
import GridFixCore
import SwiftUI

@MainActor
protocol RecordingLocationDriver: AnyObject {
    var authorization: CLAuthorizationStatus { get }
    var precise: Bool { get }
    var servicesEnabled: Bool { get }
    var onLocations: (([CLLocation]) -> Void)? { get set }
    var onAuthorization: (() -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    func requestPermission()
    func start()
    func stop()
}

/// Dedicated manager: leaving the foreground stops the position/compass manager,
/// never this one. Each recorder or boundary monitor owns its own instance;
/// only an explicit recording/monitoring action enables background location.
@MainActor
final class CoreLocationRecordingDriver: NSObject, RecordingLocationDriver, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var authorization: CLAuthorizationStatus { manager.authorizationStatus }
    var precise: Bool { manager.accuracyAuthorization == .fullAccuracy }
    // Core Location reports .denied when services are disabled globally. Avoid
    // a synchronous locationServicesEnabled() query on the UI thread per fix.
    var servicesEnabled: Bool { authorization != .denied && authorization != .restricted }
    // Internal for integration checks against the real Core Location manager.
    var backgroundEnabled: Bool { manager.allowsBackgroundLocationUpdates }
    var automaticallyPauses: Bool { manager.pausesLocationUpdatesAutomatically }
    var showsIndicator: Bool { manager.showsBackgroundLocationIndicator }

    override init() { super.init(); manager.delegate = self }
    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func start() {
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }
    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { onLocations?(locations) }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onAuthorization?() }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { onFailure?(error) }
}

/// Serial disk work keeps fsync and log parsing off the main thread.
private final class RecordingWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.gridfix.track-log", qos: .utility)
    private let directory: URL
    private var journal: TrackRecordingJournal?
    init(directory: URL) { self.directory = directory }
    func perform<T: Sendable>(_ action: @escaping @Sendable (TrackRecordingJournal) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.journal == nil { self.journal = try TrackRecordingJournal(directory: self.directory) }
                    continuation.resume(returning: try action(self.journal!))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func discard() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let path = self.directory.appendingPathComponent("LiveRecording", isDirectory: true)
                    if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
                    self.journal = nil
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

@MainActor
final class TrackRecorder: ObservableObject {
    enum Phase: Equatable { case recovering, idle, requestingPermission, preparing, recording, saving, recoveryRequired }
    @Published private(set) var phase: Phase = .recovering
    @Published private(set) var active: RecordingSummary?
    @Published private(set) var message: String?
    @Published private(set) var failure: String?
    @Published private(set) var lastAcceptedAt: Date?
    @Published private(set) var lastGPSAt: Date?
    @Published private(set) var hasRecoveryNotice = false
    private let worker: RecordingWorker
    private let fieldData: FieldDataStore
    private let driver: RecordingLocationDriver
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let isForeground: @MainActor () -> Bool
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var canStart: Bool { phase == .idle }
    var canStop: Bool { phase == .recording }
    var needsSettings: Bool { driver.authorization == .denied || driver.authorization == .restricted || !driver.precise || !driver.servicesEnabled }

    init(directory: URL? = nil, fieldData: FieldDataStore, driver: RecordingLocationDriver? = nil,
         now: @escaping () -> Date = Date.init, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         isForeground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.fieldData = fieldData; self.driver = driver ?? CoreLocationRecordingDriver()
        self.now = now; self.uptime = uptime; self.isForeground = isForeground
        worker = RecordingWorker(directory: directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!)
        self.driver.onLocations = { [weak self] in self?.receive($0) }
        self.driver.onAuthorization = { [weak self] in self?.authorizationChanged() }
        self.driver.onFailure = { [weak self] in self?.locationFailed($0) }
        recover()
    }

    func start() {
        guard phase == .idle || phase == .requestingPermission else { return }
        guard isForeground() else { phase = .idle; failure = "Open the app before starting a recording."; return }
        failure = nil; message = nil; hasRecoveryNotice = false
        guard driver.servicesEnabled else { phase = .idle; failure = "Enable Location Services to record a track."; return }
        if driver.authorization == .notDetermined {
            phase = .requestingPermission; driver.requestPermission(); return
        }
        guard driver.authorization == .authorizedWhenInUse || driver.authorization == .authorizedAlways, driver.precise else {
            phase = .idle; failure = "Recording needs location permission with Precise Location enabled. Earlier tracks are kept."; return
        }
        phase = .preparing; generation = UUID(); lastAcceptedAt = nil; lastGPSAt = nil
        let token = generation, time = millis, startUptime = uptime()
        enqueue { [weak self] in
            guard let self else { return }
            do {
                let summary = try await self.worker.perform { try $0.start(now: time, uptime: startUptime) }
                guard self.generation == token else { return }
                self.active = summary
                guard self.isForeground(), self.hasLocationPermission else {
                    self.phase = .recording
                    self.stop(reason: "Recording did not start because the app left the foreground or location permission changed. Try again with the app open.")
                    return
                }
                self.driver.start(); self.phase = .recording
                self.message = "Waiting for an accurate GPS fix. You can lock the screen while recording."
            } catch {
                self.active = nil; self.phase = .recoveryRequired
                self.failure = "Recording could not start. Check storage and location permission. Any existing journal is kept. \(error.localizedDescription)"
            }
        }
    }

    func stop(name: String? = nil, reason: String? = nil) {
        guard phase == .recording else { return }
        // Stop delivery now; previously queued samples finish in order, then seal.
        driver.stop(); phase = .saving
        if let reason { failure = reason }
        beginFinishingTask()
        enqueue { [weak self] in
            await self?.finish(name: name)
        }
    }

    func discard() {
        guard phase == .recording || phase == .recoveryRequired else { return }
        driver.stop(); phase = .saving
        beginFinishingTask()
        enqueue { [weak self] in
            guard let self else { return }
            do {
                try await self.worker.discard()
                self.active = nil; self.phase = .idle; self.message = "Recording discarded"; self.failure = nil
            } catch { self.phase = .recoveryRequired; self.failure = "Could not discard the recording. Its journal is kept. \(error.localizedDescription)" }
            self.endFinishingTask()
        }
    }

    func recover() {
        guard phase == .recovering || phase == .recoveryRequired else { return }
        phase = .recovering
        enqueue { [weak self] in
            guard let self else { return }
            do {
                let pending = try await self.worker.perform { $0.hasPendingSession }
                if pending { await self.finish(recovered: true) }
                else { self.phase = .idle; self.failure = nil }
            } catch {
                self.phase = .recoveryRequired
                self.failure = "The recording journal could not be read. It was kept. \(error.localizedDescription)"
            }
        }
    }

    func acknowledgeNotice() {
        if phase == .idle { failure = nil; hasRecoveryNotice = false }
    }

    // Also used by integration tests through an injected location driver.
    private func receive(_ locations: [CLLocation]) {
        guard phase == .recording else { return }
        guard hasLocationPermission else { stop(reason: "Recording stopped because precise location permission changed. Earlier saved points are kept."); return }
        let token = generation, received = now(), receivedUptime = uptime()
        let samples = locations.compactMap { location -> RecordingSample? in
            let age = received.timeIntervalSince(location.timestamp)
            // Core Location can deliver a cached fix when updates start. Batched
            // real updates are processed in order, not just locations.last.
            guard age >= -1, location.timestamp.timeIntervalSince1970.isFinite else { return nil }
            let time = location.timestamp.timeIntervalSince1970 * 1000
            guard time >= 0, time < Double(Int64.max) else { return nil }
            let altitude = location.verticalAccuracy.isFinite && location.verticalAccuracy > 0 && location.altitude.isFinite ? location.altitude : nil
            return RecordingSample(point: TrackPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude,
                                                     time: Int64(time.rounded()), altitudeMeters: altitude),
                                   accuracyMeters: location.horizontalAccuracy, uptime: receivedUptime - max(0, age))
        }
        if let latest = samples.last(where: { $0.accuracyMeters.isFinite && (0...30).contains($0.accuracyMeters) }) {
            lastGPSAt = Date(timeIntervalSince1970: Double(latest.point.time) / 1000)
            message = nil
        }
        enqueue { [weak self] in
            guard let self, self.generation == token else { return }
            for sample in samples {
                do {
                    if let summary = try await self.worker.perform({ try $0.append(sample) }) {
                        self.active = summary; self.lastAcceptedAt = Date(timeIntervalSince1970: Double(sample.point.time) / 1000)
                        self.message = nil
                    }
                } catch {
                    self.failure = "Recording stopped because a point could not be saved. Earlier saved points are kept. \(error.localizedDescription)"
                    if self.phase == .recording { self.stop() }
                    return
                }
            }
        }
    }

    private var hasLocationPermission: Bool {
        (driver.authorization == .authorizedWhenInUse || driver.authorization == .authorizedAlways) && driver.precise && driver.servicesEnabled
    }
    private var millis: Int64 { Int64((now().timeIntervalSince1970 * 1000).rounded()) }
    private func authorizationChanged() {
        if phase == .requestingPermission, driver.authorization != .notDetermined { start() }
        else if phase == .recording, !hasLocationPermission {
            stop(reason: "Recording stopped because precise location permission changed. Earlier saved points are kept.")
        }
    }
    private func locationFailed(_ error: Error) {
        guard phase == .recording else { return }
        if (error as? CLError)?.code == .denied {
            stop(reason: "Recording stopped because location access is unavailable. Earlier saved points are kept.")
        } else { message = "GPS is temporarily unavailable. Recording is waiting for a new fix." }
    }
    private func finish(name: String? = nil, recovered: Bool = false) async {
        do {
            let time = millis
            let discardEmpty = recovered || failure != nil
            let document = try await worker.perform { try $0.finish(now: time, name: name, discardEmpty: discardEmpty) }
            if let document { try fieldData.saveRecordedTrack(document) }
            try await worker.perform { try $0.clear() }
            active = nil; phase = .idle
            if recovered { failure = nil }
            hasRecoveryNotice = recovered && document != nil
            message = document == nil ? "No GPS points were saved." : (recovered ? "Recovered interrupted recording. Saved points are in Routes & tracks." : "Track saved in Routes & tracks")
        } catch {
            phase = .recoveryRequired
            failure = "Recording stopped, but its saved track could not be finalized. The journal is kept; retry saving or reopen the app. \(error.localizedDescription)"
        }
        endFinishingTask()
    }
    private func enqueue(_ action: @escaping @MainActor () async -> Void) {
        let previous = operation
        operation = Task { await previous?.value; await action() }
    }
    // Gives a permission/storage failure's final publication a bounded chance
    // to finish in the background. Durability never depends on this grace time.
    private func beginFinishingTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save recorded track") { [weak self] in
            Task { @MainActor in self?.endFinishingTask() }
        }
    }
    private func endFinishingTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}
