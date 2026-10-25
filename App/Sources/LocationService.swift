import CoreLocation
import Foundation
import GridFixCore
import UIKit

/// The fix, graded the way the Android app grades it.
///
/// One deliberate difference: **iOS exposes no satellite count.** Core Location
/// gives `horizontalAccuracy` and nothing about GNSS status, so the grade and
/// the trusted precision come from accuracy alone and the satellite line is
/// simply absent. Faking a count would be worse than omitting it.
struct Fix: Equatable {
    let lat: Double
    let lon: Double
    let accuracyMeters: Double
    let altitudeMeters: Double?
    /// Ground speed when Core Location reports a usable value; nil otherwise.
    let speedMetersPerSecond: Double?
    let timestamp: Date
    let timestampUptime: TimeInterval
    let courseDegrees: Double?

    init(lat: Double, lon: Double, accuracyMeters: Double, altitudeMeters: Double?,
         speedMetersPerSecond: Double?, timestamp: Date, timestampUptime: TimeInterval, courseDegrees: Double? = nil) {
        self.lat = lat; self.lon = lon; self.accuracyMeters = accuracyMeters
        self.altitudeMeters = altitudeMeters; self.speedMetersPerSecond = speedMetersPerSecond
        self.timestamp = timestamp; self.timestampUptime = timestampUptime; self.courseDegrees = courseDegrees
    }

    init(location: CLLocation, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lat = location.coordinate.latitude; lon = location.coordinate.longitude
        accuracyMeters = location.horizontalAccuracy
        altitudeMeters = location.verticalAccuracy >= 0 && location.altitude.isFinite ? location.altitude : nil
        speedMetersPerSecond = location.speed.isFinite && location.speed >= 0 ? location.speed : nil
        courseDegrees = location.course.isFinite && (0..<360).contains(location.course) ? location.course : nil
        timestamp = location.timestamp; timestampUptime = uptime - now.timeIntervalSince(location.timestamp)
    }

    /// 0 to 5, from horizontal accuracy.
    var grade: Int {
        guard accuracyMeters.isFinite, accuracyMeters >= 0 else { return 0 }
        switch accuracyMeters {
        case 0...5: return 5
        case 5...10: return 4
        case 10...20: return 3
        case 20...50: return 2
        default: return 1
        }
    }

    var gradeWord: String {
        switch grade {
        case 5: return "EXCELLENT"
        case 4: return "GOOD"
        case 3: return "FAIR"
        case 2: return "POOR"
        case 1: return "DEGRADED"
        default: return "NO FIX"
        }
    }

    /// The finest MGRS precision the error circle actually supports. Reading a
    /// 10-digit grid off a 30 m fix is false confidence, and the operator
    /// should be told which digits mean something.
    var trustedDigits: Int {
        guard accuracyMeters.isFinite, accuracyMeters >= 0 else { return 4 }
        switch accuracyMeters {
        case 0...1: return 10
        case 1...5: return 8
        case 5...50: return 6
        default: return 4
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var fix: Fix?
    /// Only a recent, precise, authorised fix may create a waypoint or drive navigation.
    @Published private(set) var usableFix: Fix?
    @Published private(set) var quality: PositionFixQuality?
    @Published private(set) var usableHeading: CLHeading?
    /// Latest compass sample. Nil until Core Location reports one. A negative
    /// headingAccuracy means the sample is not a heading — callers must not
    /// treat 0 as "north" when this is nil or invalid.
    @Published private(set) var heading: CLHeading?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// True when the user granted only coarse location: kilometre-scale error,
    /// which makes every grid on screen a lie. The UI must say so, not degrade
    /// quietly. This is the iOS twin of Android's approximate-location gate.
    @Published private(set) var reducedAccuracy = false

    private let manager: CLLocationManager
    private var headingUptime: TimeInterval?
    private var minimumHeadingUptime: TimeInterval = 0
    private var headingActive = false
    private var active = false
    private var compassEnabled = false
    var hasCompass: Bool { CLLocationManager.headingAvailable() }

    override convenience init() { self.init(manager: CLLocationManager()) }
    init(manager: CLLocationManager) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        authorization = manager.authorizationStatus
        refreshAccuracyAuthorization()
    }

    func start() {
        active = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        startHeading()
        refreshFixValidity()
    }

    func stop() {
        active = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        headingActive = false
        heading = nil; usableHeading = nil; headingUptime = nil
    }

    func refreshFixValidity() {
        let now = ProcessInfo.processInfo.systemUptime
        let nextQuality = fix.map { PositionFixQuality(fix: $0, nowUptime: now) }
        if quality != nextQuality { quality = nextQuality }
        let freshHeading = headingUptime.map { DisplayHeadingPolicy.isFresh(timestampUptime: $0, nowUptime: now) } == true
        let nextHeading = freshHeading ? heading : nil
        if usableHeading !== nextHeading { usableHeading = nextHeading }
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse,
              !reducedAccuracy, let fix,
              NavigationFixPolicy.isUsable(lat: fix.lat, lon: fix.lon, accuracyMeters: fix.accuracyMeters,
                                           timestampUptime: fix.timestampUptime,
                                           nowUptime: ProcessInfo.processInfo.systemUptime) else {
            if usableFix != nil { usableFix = nil }
            return
        }
        if usableFix != fix { usableFix = fix }
    }

    /// Main-screen heading follows the actual window, independently of the
    /// navigation driver whose compass stays referenced to the hardware top.
    func setDisplayOrientation(_ orientation: UIInterfaceOrientation) {
        guard let device = DisplayHeadingPolicy.deviceOrientation(orientation), manager.headingOrientation != device else { return }
        manager.headingOrientation = device
        minimumHeadingUptime = ProcessInfo.processInfo.systemUptime
        heading = nil; usableHeading = nil; headingUptime = nil
    }

    private func startHeading() {
        guard active, compassEnabled, hasCompass else { return }
        if !headingActive { minimumHeadingUptime = ProcessInfo.processInfo.systemUptime }
        headingActive = true
        manager.headingFilter = 1
        manager.startUpdatingHeading()
    }

    func setCompassEnabled(_ enabled: Bool) {
        guard compassEnabled != enabled else { return }
        compassEnabled = enabled
        if enabled { startHeading() }
        else {
            manager.stopUpdatingHeading(); headingActive = false
            heading = nil; usableHeading = nil; headingUptime = nil
        }
    }

    private func refreshAccuracyAuthorization() {
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let f = Fix(location: l)
        Task { @MainActor [weak self] in
            guard let self, self.active, self.authorization == .authorizedAlways || self.authorization == .authorizedWhenInUse else { return }
            self.fix = f
            self.refreshFixValidity()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            self.refreshAccuracyAuthorization()
            if status != .authorizedAlways && status != .authorizedWhenInUse {
                self.fix = nil; self.heading = nil; self.headingUptime = nil
            }
            self.refreshFixValidity()
            if self.active && (status == .authorizedWhenInUse || status == .authorizedAlways) {
                m.startUpdatingLocation()
                self.startHeading()
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let sampleUptime = ProcessInfo.processInfo.systemUptime - Date().timeIntervalSince(newHeading.timestamp)
        Task { @MainActor [weak self] in
            guard let self, self.headingActive, sampleUptime >= self.minimumHeadingUptime,
                  self.authorization == .authorizedAlways || self.authorization == .authorizedWhenInUse else { return }
            let valid = newHeading.headingAccuracy.isFinite && (0...25).contains(newHeading.headingAccuracy)
                && newHeading.magneticHeading.isFinite && (0..<360).contains(newHeading.magneticHeading)
                && newHeading.trueHeading.isFinite
            self.heading = valid ? newHeading : nil
            self.headingUptime = self.heading == nil ? nil : sampleUptime
            self.refreshFixValidity()
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // A denied or momentarily unavailable fix is not an error state worth
        // shouting about; the readout already shows NO FIX.
    }
}
