import CoreLocation
import GridFixCore
import SwiftUI
import WatchConnectivity

@MainActor
final class WatchModel: NSObject, ObservableObject, CLLocationManagerDelegate, WCSessionDelegate {
    @Published private(set) var snapshot = WatchSnapshot()
    @Published private(set) var takScene = WatchTAKScene()
    @Published private(set) var guideSnapshot: WatchGuideSnapshot?
    @Published private(set) var mapSnapshot: WatchMapSnapshot?
    @Published private(set) var mapSyncStatus = "No phone map sync yet"
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
        if let data = UserDefaults.standard.data(forKey: WatchMapSnapshot.contextKey), let saved = WatchMapSnapshot.decode(data) {
            mapSnapshot = saved; mapSyncStatus = "Cached phone overlay"
        }
        if let data = UserDefaults.standard.data(forKey:WatchGuideSnapshot.contextKey) { guideSnapshot = WatchGuideSnapshot.decode(data) }
        if let data = UserDefaults.standard.data(forKey:"watch.tak.cache.v1"),let cache = WatchTAKScene.decodeCache(data) { takScene = cache }
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

    private func applyTAK(_ context: [String:Any],complete: Bool = false) {
        if let data = context[WatchTAKSnapshot.contextKey] as? Data,let incoming = WatchTAKSnapshot.decode(data) {
            var next = takScene
            if next.apply(incoming,now:Date(),uptime:ProcessInfo.processInfo.systemUptime) {
                takScene = next
                if let cache = next.encodedCache() { UserDefaults.standard.set(cache,forKey:"watch.tak.cache.v1") }
            }
        } else if complete && context[WatchTAKSnapshot.contextKey] == nil { takScene.clear(); UserDefaults.standard.removeObject(forKey:"watch.tak.cache.v1") }
    }
    func remoteItems(at date: Date) -> [WatchTAKSnapshot.Item] {
        takScene.visible(now:date,uptime:ProcessInfo.processInfo.systemUptime)
    }
    private func applyGuide(_ context: [String:Any]) {
        guard let data = context[WatchGuideSnapshot.contextKey] as? Data,let incoming = WatchGuideSnapshot.decode(data),incoming.shouldApply(over:guideSnapshot) else { return }
        guideSnapshot = incoming
        UserDefaults.standard.set(data,forKey:WatchGuideSnapshot.contextKey)
    }
    private func requestGuide() {
        let session = WCSession.default
        guard session.activationState == .activated,session.isReachable else { return }
        session.sendMessage(["gridfix.guide.request":true,"gridfix.tak.request":true],replyHandler:nil,errorHandler:{ _ in })
    }
    private func apply(_ context: [String: Any]) {
        applyGuide(context)
        guard let data = context[WatchSnapshot.contextKey] as? Data,
              let incoming = WatchSnapshot.decode(data) else { return }
        // The map revision belongs to this complete context generation. Reject an old
        // generation before applying its target/settings, so a delayed clear cannot be undone.
        if let mapData = context[WatchMapSnapshot.contextKey] as? Data,
           let map = WatchMapSnapshot.decode(mapData), !map.shouldApply(over: mapSnapshot) {
            mapSyncStatus = "Older context ignored · cached overlay"
            return
        }
        applyTAK(context,complete:true)
        snapshot = incoming; hasSync = true
        UserDefaults.standard.set(data, forKey: cacheKey)
        if let mapData = context[WatchMapSnapshot.contextKey] as? Data {
            if let map = WatchMapSnapshot.decode(mapData) {
                if map.shouldApply(over: mapSnapshot) {
                    mapSnapshot = map; mapSyncStatus = "Cached phone overlay"
                    UserDefaults.standard.set(mapData, forKey: WatchMapSnapshot.contextKey)
                } else { mapSyncStatus = "Older map update ignored · cached overlay" }
            } else { mapSyncStatus = "Rejected map update · cached overlay" }
        } else if context["gridfix.map.error"] != nil {
            mapSyncStatus = "Phone map unavailable · cached overlay"
        } else {
            mapSnapshot = nil; mapSyncStatus = "Phone map sync unsupported"
            UserDefaults.standard.removeObject(forKey: WatchMapSnapshot.contextKey)
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.reachable = session.isReachable; self.apply(session.receivedApplicationContext); self.requestGuide() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachable = session.isReachable; self.requestGuide() }
    }
    nonisolated func session(_ session: WCSession,didReceiveMessage message: [String:Any]) {
        Task { @MainActor in self.applyGuide(message); self.applyTAK(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in self.apply(session.receivedApplicationContext) }
    }
}
