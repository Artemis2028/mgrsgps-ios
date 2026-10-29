import CoreLocation
import GridFixCore
import SwiftUI
import WatchConnectivity
import WatchKit
import UserNotifications

@MainActor
final class WatchModel: NSObject, ObservableObject, CLLocationManagerDelegate, WCSessionDelegate, UNUserNotificationCenterDelegate {
    @Published private(set) var snapshot = WatchSnapshot()
    @Published private(set) var takScene = WatchTAKScene()
    @Published private(set) var guideSnapshot: WatchGuideSnapshot?
    @Published private(set) var mapSnapshot: WatchMapSnapshot?
    @Published private(set) var mapSyncStatus = "No phone map sync yet"
    @Published private(set) var fix: CLLocation?
    @Published private(set) var headingSample: WatchHeadingSample?
    @Published private(set) var compassAvailable = false
    private var headingSessionUptime: TimeInterval?
    @Published private(set) var reachable = false
    @Published private(set) var hasSync = false
    @Published private(set) var status = "GPS idle"
    @Published private(set) var reducedAccuracy = false
    @Published private(set) var steering = WatchSteeringSession()
    private var steeringTick: Task<Void,Never>?
    private var steeringPlayback: Task<Void,Never>?
    private var steeringGeneration = UUID()
    @Published private(set) var wristLane = WatchLaneSession()
    @Published private(set) var wristLaneError: String?
    private var wristPlayback: Task<Void,Never>?
    private var wristTick: Task<Void,Never>?
    private var wristStart: Task<Void,Never>?
    private var wristStartToken = UUID()
    private var wristNotice: Task<Void,Never>?
    private var wristNoticeId: String?
    @Published private(set) var wristStarting = false
    private var backgroundLocation: CLBackgroundActivitySession?
    @Published var keepWristAlertsRunning = UserDefaults.standard.bool(forKey:"watch.wrist.background") {
        didSet {
            UserDefaults.standard.set(keepWristAlertsRunning,forKey:"watch.wrist.background")
            // Changing execution scope requires a fresh explicit Start.
            if oldValue != keepWristAlertsRunning,wristLane.active { stopWristLane("Mode changed · start again") }
        }
    }
    private var wristGeneration = UUID()
    private var guideScene = WatchGuideScene()
    private let guideCacheKey = "watch.guide.cache.v1"
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
        if let data = UserDefaults.standard.data(forKey: guideCacheKey),let cached = WatchGuideScene.decodeCache(data) { guideScene = cached }
        else if let data = UserDefaults.standard.data(forKey: WatchGuideSnapshot.contextKey),let saved = WatchGuideSnapshot.decode(data) { guideScene = .legacy(saved) }
        guideSnapshot = guideScene.snapshot
        if let data = UserDefaults.standard.data(forKey:"watch.tak.cache.v1"),let cache = WatchTAKScene.decodeCache(data) { takScene = cache }
        let notifications = UNUserNotificationCenter.current()
        notifications.delegate = self
        notifications.setNotificationCategories([UNNotificationCategory(identifier:"WRIST_LANE",
            actions:[UNNotificationAction(identifier:"STOP_WRIST_LANE",title:"Stop wrist alerts",options:[.destructive])],intentIdentifiers:[])])
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
            stopHeading(); stopSteering("Paused · start steering again")
            wristLane.leaveForeground(backgroundAvailable: backgroundLocation != nil && authorized)
            if !wristLane.active { stopWristLane(wristLane.status) }
            if !backgroundWristActive { manager.stopUpdatingLocation(); status = "GPS paused" }
        }
    }

    private var backgroundWristActive: Bool {
        wristLane.active && wristLane.continuesInBackground && backgroundLocation != nil
    }
    private var locationExecutionActive: Bool { foreground || backgroundWristActive }

    private var authorized: Bool {
        manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
    }

    private func startAuthorized() {
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
        guard authorized else {
            stopWristLane("Location permission required")
            manager.stopUpdatingLocation(); stopHeading(); stopSteering("Location permission required")
            fix = nil; fixTimestampUptime = nil
            status = manager.authorizationStatus == .notDetermined ? "Allow location for grid" : "Location disabled"
            return
        }
        guard locationExecutionActive else { return }
        status = "Acquiring GPS"
        manager.startUpdatingLocation()
        if foreground, headingSessionUptime == nil {
            compassAvailable = CLLocationManager.headingAvailable()
            if compassAvailable {
                headingSessionUptime = ProcessInfo.processInfo.systemUptime
                manager.headingFilter = kCLHeadingFilterNone
                manager.startUpdatingHeading()
            }
        }
    }

    private func stopHeading() {
        manager.stopUpdatingHeading(); headingSessionUptime = nil; headingSample = nil
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        let now = ProcessInfo.processInfo.systemUptime
        let age = Date().timeIntervalSince(heading.timestamp)
        let degrees = heading.trueHeading, accuracy = heading.headingAccuracy
        Task { @MainActor in
            guard self.foreground, self.authorized, let session = self.headingSessionUptime else { return }
            guard age.isFinite, age >= 0 else { self.headingSample = nil; self.tickSteering(); return }
            self.headingSample = WatchHeadingSample(trueDegrees: degrees,accuracy: accuracy,
                sampleUptime: now-age,sessionUptime: session,nowUptime: ProcessInfo.processInfo.systemUptime)
            self.tickSteering()
        }
    }
    func heading(at date: Date) -> Double? {
        guard foreground,usable(at:date),let fix,let headingSample,
              headingSample.isFresh(nowUptime:ProcessInfo.processInfo.systemUptime) else { return nil }
        return snapshot.bearing(trueDegrees:headingSample.trueDegrees,lat:fix.coordinate.latitude,
                                lon:fix.coordinate.longitude,altitude:fix.altitude,date:date)
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-watchLocationDiagnostics") {
            print("Watch GPS callback: age=\(initialAge), accuracy=\(latest.horizontalAccuracy), foreground=\(foreground), authorized=\(authorized), precise=\(manager.accuracyAuthorization == .fullAccuracy)")
        }
        #endif
        guard locationExecutionActive else { return }
        guard authorized,
              WatchFixPolicy.accepts(lat: latest.coordinate.latitude, lon: latest.coordinate.longitude,
                                     accuracy: latest.horizontalAccuracy, age: initialAge) else {
            loseWristFix(); return
        }
        fixTimestampUptime = ProcessInfo.processInfo.systemUptime - initialAge
        fix = latest; status = "Watch location"
        tickWristLane(); tickSteering()
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.loseWristFix() }
    }

    private func loseWristFix() {
        cancelWristPlayback(); clearWristNotice(); wristLane.invalidateFix()
        cancelSteeringPlayback(); steering.invalidateSensors()
        fix = nil; fixTimestampUptime = nil; headingSample = nil; status = "GPS unavailable"
        // Transient location failures wait for fresh GPS; revoked permission
        // releases the platform owner and requires a new user Start.
        if !authorized { stopWristLane("Location permission required"); stopSteering("Location permission required"); manager.stopUpdatingLocation(); stopHeading() }
    }

    func usable(at date: Date) -> Bool {
        guard let fix, let fixTimestampUptime else { return false }
        return WatchFixPolicy.isUsable(authorized: authorized, precise: manager.accuracyAuthorization == .fullAccuracy,
                                       foreground: locationExecutionActive, lat: fix.coordinate.latitude, lon: fix.coordinate.longitude,
                                       accuracy: fix.horizontalAccuracy, timestampUptime: fixTimestampUptime,
                                       nowUptime: ProcessInfo.processInfo.systemUptime)
    }

    func startWristLane(_ lane: WatchLaneOverlay) {
        stopSteering(); stopWristLane()
        guard foreground else { wristLaneError = "Open the watch app to start"; return }
        guard authorized, manager.accuracyAuthorization == .fullAccuracy else {
            wristLaneError = "Precise watch location is required"; return
        }
        guard mapSnapshot?.laneOverlays.contains(lane) == true else { wristLaneError = "Choose a current cached lane"; return }
        if keepWristAlertsRunning,
           !(Bundle.main.object(forInfoDictionaryKey:"UIBackgroundModes") as? [String] ?? []).contains("location") {
            wristLaneError = "Background location is unavailable"; return
        }
        let token = wristStartToken
        wristStarting = true
        wristStart = Task { [weak self] in
            guard let self else { return }
            if self.keepWristAlertsRunning {
                let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])) == true
                guard !Task.isCancelled,self.wristStartToken == token else { return }
                guard granted else {
                    self.wristStarting = false; self.wristLaneError = "Allow notifications for screen-off alerts"; return
                }
            }
            guard !Task.isCancelled,self.wristStartToken == token else { return }
            guard self.foreground,self.authorized,self.manager.accuracyAuthorization == .fullAccuracy,
                  self.mapSnapshot?.laneOverlays.contains(lane) == true else {
                self.wristStarting = false; self.wristLaneError = "Open the watch app and start again"; return
            }
            self.wristStarting = false
            self.armWristLane(lane)
        }
    }
    private func armWristLane(_ lane: WatchLaneOverlay) {
        do {
            try wristLane.start(lane,continueInBackground:keepWristAlertsRunning)
            wristLaneError = nil
            if keepWristAlertsRunning {
                wristNoticeId = "gridfix.wrist.lane."+UUID().uuidString
                manager.activityType = .otherNavigation
                manager.allowsBackgroundLocationUpdates = true
                backgroundLocation = CLBackgroundActivitySession()
                manager.startUpdatingLocation()
            }
            wristTick = Task { [weak self] in
                while !Task.isCancelled {
                    guard self?.wristLane.active == true else { return }
                    self?.tickWristLane()
                    do { try await Task.sleep(for:.seconds(1)) } catch { return }
                }
            }
            tickWristLane()
        } catch { wristLaneError = error.localizedDescription }
    }
    func stopWristLane(_ message: String = "Wrist alerts off") {
        wristStartToken = UUID(); wristStart?.cancel(); wristStart = nil; wristStarting = false
        cancelWristPlayback(); wristTick?.cancel(); wristTick = nil
        clearWristNotice(); wristNoticeId = nil
        wristLane.stop(message)
        backgroundLocation?.invalidate(); backgroundLocation = nil
        manager.allowsBackgroundLocationUpdates = false
        if !foreground { manager.stopUpdatingLocation(); status = "GPS paused" }
    }
    private func clearWristNotice() {
        guard wristNotice != nil else { return }
        wristNotice?.cancel(); wristNotice = nil
        if let id = wristNoticeId {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:[id])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:[id])
        }
    }
    private func postWristNotice() {
        guard backgroundWristActive,!foreground,usable(at:Date()),let id = wristNoticeId,let lane = wristLane.lane else { return }
        let content = UNMutableNotificationContent()
        content.title = lane.name; content.body = wristLane.status
        content.sound = .default; content.categoryIdentifier = "WRIST_LANE"
        wristNotice?.cancel()
        wristNotice = Task { [weak self] in
            guard let self,!Task.isCancelled,self.wristNoticeId == id,self.backgroundWristActive,!self.foreground,self.usable(at:Date()) else { return }
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:id,content:content,trigger:nil))
                if Task.isCancelled || self.wristNoticeId != id || !self.backgroundWristActive || !self.usable(at:Date()) {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:[id])
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:[id])
                }
            } catch {
                guard self.wristNoticeId == id else { return }
                self.stopWristLane("Screen-off alerts unavailable")
            }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.identifier
        Task { @MainActor in
            let present = self.wristNoticeId == id && self.backgroundWristActive && !self.foreground && self.usable(at:Date())
            completionHandler(present ? [.banner,.sound] : [])
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier,action = response.actionIdentifier
        // UIKit's watch response completion performs state restoration and must
        // run on the main thread. An async delegate thunk can resume off-main
        // after MainActor.run returns, so complete this callback explicitly here.
        Task { @MainActor in
            if action == "STOP_WRIST_LANE",self.wristNoticeId == id { self.stopWristLane() }
            if id.hasPrefix("gridfix.wrist.lane.") { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:[id]) }
            completionHandler()
        }
    }
    private func cancelWristPlayback() {
        wristGeneration = UUID(); wristPlayback?.cancel(); wristPlayback = nil
    }
    func tickWristLane() {
        guard wristLane.active else { return }
        guard locationExecutionActive, usable(at: Date()), let fix, let fixTimestampUptime else {
            cancelWristPlayback(); clearWristNotice(); wristLane.invalidateFix(); return
        }
        let previous = wristLane.decision?.state
        let pulse = wristLane.update(position: .init(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude),
                                     accuracy: fix.horizontalAccuracy, fixTime: fixTimestampUptime,
                                     now: ProcessInfo.processInfo.systemUptime, usable: true)
        if wristLane.decision?.state == .inside || wristLane.decision?.state == .notYet { clearWristNotice() }
        if !foreground {
            cancelWristPlayback()
            if wristLane.takeBackgroundNotice() != nil { postWristNotice() }
            return
        }
        if let pulse {
            cancelWristPlayback()
            let generation = wristGeneration, waveform = pulse.waveform
            wristPlayback = Task { [weak self] in
                for index in waveform.indices where index % 2 == 0 && index+1 < waveform.count {
                    if waveform[index] > 0 {
                        do { try await Task.sleep(nanoseconds: UInt64(waveform[index])*1_000_000) } catch { return }
                    }
                    guard let self, !Task.isCancelled, self.foreground, self.wristLane.active,
                          self.wristGeneration == generation, self.usable(at: Date()) else { return }
                    // watchOS supplies native effects, not phone-style arbitrary
                    // continuous waveforms. Physical distinction remains a gate.
                    WKInterfaceDevice.current().play(waveform[index+1] > 100 ? .notification : .click)
                    do { try await Task.sleep(nanoseconds: UInt64(waveform[index+1])*1_000_000) } catch { return }
                }
            }
        } else if previous != wristLane.decision?.state { cancelWristPlayback() }
    }
    var steeringStartProblem: String? {
        guard foreground else { return "Open the watch app" }
        guard snapshot.target != nil else { return "Select a waypoint" }
        guard !wristLane.active && !wristStarting else { return "Stop wrist alerts first" }
        guard compassAvailable else { return "Watch compass unavailable" }
        guard usable(at:Date()) else { return "Needs fresh precise GPS" }
        guard heading(at:Date()) != nil else { return "Needs calibrated watch compass" }
        return nil
    }
    var canStartSteering: Bool { steeringStartProblem == nil }
    func startSteering() {
        guard canStartSteering,let target = snapshot.target else { return }
        stopSteering()
        guard steering.start(target) else { return }
        steeringTick = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.steering.active else { return }
                self.tickSteering()
                do { try await Task.sleep(for:.milliseconds(250)) } catch { return }
            }
        }
    }
    func stopSteering(_ message: String = "Steering off") {
        cancelSteeringPlayback(); steeringTick?.cancel(); steeringTick = nil; steering.stop(message)
    }
    private func cancelSteeringPlayback() {
        steeringGeneration = UUID(); steeringPlayback?.cancel(); steeringPlayback = nil
    }
    private func tickSteering() {
        guard steering.active else { return }
        steering.validateTarget(snapshot.target)
        guard steering.active else { stopSteering(steering.status); return }
        guard foreground,usable(at:Date()),heading(at:Date()) != nil,let fix,let fixTimestampUptime,let headingSample,
              headingSample.isFresh(nowUptime:ProcessInfo.processInfo.systemUptime) else {
            cancelSteeringPlayback(); steering.invalidateSensors(); return
        }
        let previous = steering.decision?.cue
        let pulse = steering.update(position:.init(lat:fix.coordinate.latitude,lon:fix.coordinate.longitude),
                                    accuracy:fix.horizontalAccuracy,fixTime:fixTimestampUptime,
                                    heading:headingSample,now:ProcessInfo.processInfo.systemUptime,usable:true)
        guard let pulse else {
            if steering.decision?.cue != previous { cancelSteeringPlayback() }
            return
        }
        cancelSteeringPlayback()
        let token = steeringGeneration
        // Native watch effects approximate the shared short/long pulse contract.
        // Physical distinction/orientation remains a verification gate.
        let pattern: [(Duration,WKHapticType)]
        switch pulse {
        case .right: pattern = [(.zero,.click),(.milliseconds(160),.click)]
        case .left: pattern = [(.zero,.notification)]
        case .arrival: pattern = [(.zero,.notification),(.milliseconds(600),.notification)]
        case .onCourse: pattern = [(.zero,.click)]
        default: return
        }
        steeringPlayback = Task { [weak self] in
            for (delay,effect) in pattern {
                do { try await Task.sleep(for:delay) } catch { return }
                guard let self,!Task.isCancelled,self.foreground,self.steering.active,
                      self.steeringGeneration == token,self.snapshot.target == self.steering.target,
                      self.heading(at:Date()) != nil else { return }
                WKInterfaceDevice.current().play(effect)
            }
        }
    }

    private func validateWristScene() {
        wristLane.validateScene(mapSnapshot?.laneOverlays ?? [])
        if !wristLane.active { stopWristLane(wristLane.status) }
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
        guard let data = context[WatchGuideSnapshot.contextKey] as? Data,let incoming = WatchGuideSnapshot.decode(data),
              guideScene.apply(incoming,now: Date(),uptime: ProcessInfo.processInfo.systemUptime) else { return }
        guideSnapshot = guideScene.snapshot
        if let cache = guideScene.encodedCache() {
            UserDefaults.standard.set(cache,forKey: guideCacheKey)
            UserDefaults.standard.removeObject(forKey: WatchGuideSnapshot.contextKey)
        }
    }
    func guideFresh(at date: Date) -> Bool { guideScene.isFresh(now: date,uptime: ProcessInfo.processInfo.systemUptime) }
    func guideStatus(at date: Date) -> String { guideScene.displayStatus(now: date,uptime: ProcessInfo.processInfo.systemUptime) }
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
        steering.validateTarget(incoming.target)
        if !steering.active { stopSteering(steering.status) }
        UserDefaults.standard.set(data, forKey: cacheKey)
        if let mapData = context[WatchMapSnapshot.contextKey] as? Data {
            if let map = WatchMapSnapshot.decode(mapData) {
                if map.shouldApply(over: mapSnapshot) {
                    mapSnapshot = map; mapSyncStatus = "Cached phone overlay"
                    validateWristScene()
                    UserDefaults.standard.set(mapData, forKey: WatchMapSnapshot.contextKey)
                } else { mapSyncStatus = "Older map update ignored · cached overlay" }
            } else { mapSyncStatus = "Rejected map update · cached overlay" }
        } else if context["gridfix.map.error"] != nil {
            mapSyncStatus = "Phone map unavailable · cached overlay"
        } else {
            mapSnapshot = nil; mapSyncStatus = "Phone map sync unsupported"
            validateWristScene()
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
