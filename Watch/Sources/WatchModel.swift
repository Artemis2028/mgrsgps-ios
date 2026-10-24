import CoreLocation
import GridFixCore
import SwiftUI
import WatchConnectivity

@MainActor
final class WatchModel: NSObject, ObservableObject, CLLocationManagerDelegate, WCSessionDelegate {
    @Published private(set) var snapshot = WatchSnapshot()
    @Published private(set) var fix: CLLocation?
    @Published private(set) var reachable = false
    @Published private(set) var hasSync = false
    @Published private(set) var status = "GPS idle"
    @Published private(set) var reducedAccuracy = false
    private let manager = CLLocationManager()
    private var foreground = false
    private var fixTimestampUptime: TimeInterval?
    private let cacheKey = "watch.snapshot.v1"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey), let saved = WatchSnapshot.decode(data) {
            snapshot = saved; hasSync = true
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func setActive(_ active: Bool) {
        foreground = active
        if active {
            if manager.authorizationStatus == .notDetermined {
                status = "Allow location for grid"
                manager.requestWhenInUseAuthorization()
            } else { startAuthorized() }
        } else {
            manager.stopUpdatingLocation()
            status = "GPS paused"
        }
    }

    private var authorized: Bool {
        manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
    }

    private func startAuthorized() {
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
        guard authorized else {
            manager.stopUpdatingLocation()
            fix = nil; fixTimestampUptime = nil
            status = manager.authorizationStatus == .notDetermined ? "Allow location for grid" : "Location disabled"
            return
        }
        guard foreground else { return }
        status = "Acquiring GPS"
        manager.startUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.startAuthorized() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.receive(latest) }
    }
    private func receive(_ latest: CLLocation) {
        let initialAge = Date().timeIntervalSince(latest.timestamp)
        guard foreground, authorized,
              WatchFixPolicy.accepts(lat: latest.coordinate.latitude, lon: latest.coordinate.longitude,
                                     accuracy: latest.horizontalAccuracy, age: initialAge) else { return }
        fixTimestampUptime = ProcessInfo.processInfo.systemUptime - initialAge
        fix = latest; status = "Watch location"
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.status = "GPS unavailable" }
    }

    func usable(at date: Date) -> Bool {
        guard let fix, let fixTimestampUptime else { return false }
        return WatchFixPolicy.isUsable(authorized: authorized, precise: manager.accuracyAuthorization == .fullAccuracy,
                                       foreground: foreground, lat: fix.coordinate.latitude, lon: fix.coordinate.longitude,
                                       accuracy: fix.horizontalAccuracy, timestampUptime: fixTimestampUptime,
                                       nowUptime: ProcessInfo.processInfo.systemUptime)
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context[WatchSnapshot.contextKey] as? Data,
              let incoming = WatchSnapshot.decode(data) else { return }
        // WC application context is the authoritative latest state, including nil target.
        snapshot = incoming; hasSync = true
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let connected = session.isReachable
        Task { @MainActor in self.reachable = connected; self.apply(context) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let connected = session.isReachable
        Task { @MainActor in self.reachable = connected }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}
