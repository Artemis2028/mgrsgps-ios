import Combine
import CoreLocation
import GridFixCore
import SwiftUI

@MainActor
final class NavigationSession: ObservableObject {
    private struct Saved: Codable { var progress: RouteFollowingProgress?; var active: Bool; var haptics: Bool }
    @Published private(set) var progress: RouteFollowingProgress?
    @Published private(set) var running = false
    @Published private(set) var preparing = false
    @Published private(set) var haptics = false
    @Published private(set) var status = "Navigation guide off"
    @Published private(set) var decision: GuideDecision?
    @Published private(set) var error: String?
    @Published private(set) var feedbackStatus = ""
    @Published private(set) var arrivals = 0
    private let store: WaypointStore
    private let field: FieldDataStore
    private let settings: AppSettings
    private let driver: NavigationLocationDriver
    private let feedback: NavigationFeedback
    private let file: URL
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let foreground: @MainActor () -> Bool
    private let scheduleTicks: Bool
    private var subscriptions = Set<AnyCancellable>()
    private var loop: Task<Void,Never>?
    private var operation: Task<Void,Never>?
    private var generation = UUID()
    private var pending: (() -> Void)?
    private var loaded = true
    private var target: Waypoint?
    private var fix: CLLocation?
    private var fixTime = 0.0
    private var lastDate: Date?
    private var receiptClock: (Date,Double)?
    private var heading: NavigationHeading?
    private var headingTime = 0.0
    private var origin: GeoPoint?
    private var cues = GuideCueState()
    private var cadence = GuideCadence()
    private var arrival = NavigationArrivalState()

    init(directory: URL? = nil, store: WaypointStore, field: FieldDataStore, settings: AppSettings,
         driver: NavigationLocationDriver? = nil, feedback: NavigationFeedback? = nil,
         now: @escaping () -> Date = Date.init, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         foreground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }, scheduleTicks: Bool = true) {
        self.store = store; self.field = field; self.settings = settings
        self.driver = driver ?? CoreLocationNavigationDriver(); self.feedback = feedback ?? SystemNavigationFeedback()
        self.now = now; self.uptime = uptime; self.foreground = foreground; self.scheduleTicks = scheduleTicks
        file = (directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!).appendingPathComponent("navigation-session-v1.json")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                guard data.count < 2 * 1024 * 1024 else { throw BoundaryError.invalid("Navigation state is too large.") }
                let saved = try JSONDecoder().decode(Saved.self,from: data)
                if let p = saved.progress {
                    guard (2...10_000).contains(p.points.count), (0...p.points.count).contains(p.index), p.points.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite && (-90...90).contains($0.lat) && (-180...180).contains($0.lon) }) else { throw BoundaryError.invalid("Invalid route progress.") }
                    progress = p; progress?.paused = true
                }
                haptics = saved.haptics
                status = saved.active ? "Navigation was interrupted. Resume explicitly with the app open." : (progress?.complete == true ? "Route complete" : (progress == nil ? "Navigation guide off" : "Route paused"))
            }
        } catch { loaded = false; self.error = "Navigation state was kept: \(error.localizedDescription). Clear the session to start again." }
        self.driver.onLocations = { [weak self] in self?.receive($0) }
        self.driver.onHeading = { [weak self] sample in
            guard let self, self.running else { return }
            let age = self.now().timeIntervalSince(sample.timestamp)
            self.heading = sample; self.headingTime = self.uptime()-max(0,age)
            if age < 0 || age > 2 { self.heading = nil }; self.tick()
        }
        self.driver.onAuthorization = { [weak self] in
            guard let self else { return }
            if self.driver.authorization != .notDetermined, let pending = self.pending { self.pending = nil; self.preparing = false; pending() }
            else if self.running && !self.permitted { self.pause(reason: "Navigation stopped because precise location permission changed.") }
        }
        self.driver.onFailure = { [weak self] error in
            guard let self, self.running else { return }
            if (error as? CLError)?.code == .denied { self.pause(reason: "Navigation stopped: location permission unavailable.") }
            else { self.fix = nil; self.tick() }
        }
        store.$selectedId.sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &subscriptions)
        store.$waypoints.sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &subscriptions)
        field.$document.sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &subscriptions)
    }
    private var permitted: Bool { (driver.authorization == .authorizedWhenInUse || driver.authorization == .authorizedAlways) && driver.precise && driver.servicesEnabled }
    func follow(_ route: Backup.Graphic,startIndex: Int = 0) {
        guard !running, !preparing, loaded else { return }
        guard route.type == "route", (2...10_000).contains(route.points.count), route.points.indices.contains(startIndex) else { error = "Choose a route with 2–10,000 vertices and a valid start point."; return }
        do {
            guard field.document.graphics.contains(route) else { throw BoundaryError.invalid("The route has changed. Reopen it before following.") }
            guard store.waypoints.filter({ $0.sourceRouteId != route.id }).count + route.points.count <= 10_000 else { throw BoundaryError.invalid("Route waypoints exceed the library limit. Remove unused waypoints first.") }
            let points = route.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) }
            try store.replaceRouteWaypoints(routeID: route.id,name: route.name,points: points,folder: route.folder)
            let p = RouteFollowingProgress(routeID: route.id,name: route.name,points: points,index: startIndex)
            launch(progress: p,haptics: true)
        } catch { self.error = error.localizedDescription }
    }
    func resume() {
        guard let p = progress, !p.complete else { return }
        launch(progress: p,haptics: haptics)
    }
    func startGuide() {
        guard store.waypoints.contains(where: { $0.id == store.selectedId }) else { error = "Choose a waypoint first."; return }
        launch(progress: nil,haptics: true)
    }
    private func launch(progress requested: RouteFollowingProgress?,haptics enabled: Bool) {
        guard !running, !preparing, loaded else { return }
        guard foreground() else { error = "Open the app before starting navigation."; return }
        guard driver.servicesEnabled else { error = "Enable Location Services for navigation."; return }
        if driver.authorization == .notDetermined {
            preparing = true; pending = { [weak self] in self?.launch(progress: requested,haptics: enabled) }; driver.requestPermission(); return
        }
        guard permitted else { error = "Navigation needs While Using permission and Precise Location."; return }
        preparing = true; error = nil; generation = UUID(); let token = generation
        operation = Task {
            await feedback.prepare()
            await waitForPermissionForeground(foreground)
            guard generation == token else { return }
            guard !Task.isCancelled, foreground(), permitted else { preparing = false; error = "Start navigation with the app open and precise location enabled."; return }
            do {
                var next = requested; next?.paused = false
                if let p = next {
                    try validate(p)
                    guard let wp = routeTarget(p) else { throw BoundaryError.invalid("A route waypoint is missing. Start the route again to regenerate it.") }
                    target = wp
                } else { target = store.waypoints.first { $0.id == store.selectedId } }
                guard let target else { throw BoundaryError.invalid("Navigation target is missing.") }
                try persist(progress: next,active: true,haptics: enabled)
                self.progress = next; haptics = enabled; running = true; preparing = false
                store.select(target.id); arrivals = 0; fix = nil; lastDate = nil; receiptClock = nil; heading = nil
                resetLeg(); feedback.begin(); feedbackStatus = feedback.status; driver.start()
                status = "Waiting for a fresh position and heading"
                startTicks()
            } catch { preparing = false; self.error = error.localizedDescription }
        }
    }
    private func startTicks() {
        guard scheduleTicks else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }; self?.tick()
            }
        }
    }
    func setHaptics(_ enabled: Bool) {
        guard running else { if enabled { startGuide() }; return }
        if !enabled && progress == nil { haptics = false; pause(); return }
        do { try persist(progress: progress,active: true,haptics: enabled); haptics = enabled; resetLeg() }
        catch { pause(reason: "Guide settings could not be saved: \(error.localizedDescription)") }
    }
    func pause(reason: String? = nil) {
        generation = UUID(); operation?.cancel(); pending = nil; preparing = false
        loop?.cancel(); driver.stop(); feedback.stop(); running = false; fix = nil; heading = nil; decision = nil
        progress?.paused = true; status = progress == nil ? "Navigation guide off" : "Route paused"
        if let reason { error = reason }
        do { if loaded { try persist(progress: progress,active: false,haptics: haptics) } }
        catch { self.error = "Navigation stopped; progress could not be saved: \(error.localizedDescription)" }
    }
    func stop() { pause(); progress = nil; status = "Navigation stopped"; do { if loaded { try persist(progress: nil,active: false,haptics: false) } } catch { self.error = error.localizedDescription } }
    func clearSavedSession() {
        pause()
        do {
            if !loaded, FileManager.default.fileExists(atPath: file.path) { try FileManager.default.moveItem(at: file,to: file.deletingLastPathComponent().appendingPathComponent("navigation-damaged-\(UUID().uuidString).json")) }
            try persist(progress: nil,active: false,haptics: false); loaded = true; progress = nil; haptics = false; error = nil; status = "Navigation guide off"
        } catch { self.error = error.localizedDescription }
    }
    func movePoint(_ delta: Int) {
        guard var p = progress else { return }
        p.index = min(p.points.count,max(0,p.index+delta))
        do {
            try persist(progress: p,active: running && !p.complete,haptics: haptics); progress = p
            if p.complete { finishRoute() }
            else if let wp = routeTarget(p) { target = wp; store.select(wp.id); resetLeg(); feedback.stop(); if running { feedback.begin() } }
        } catch { pause(reason: error.localizedDescription) }
    }
    func foregroundChanged(_ active: Bool) { feedback.cancelPlayback(); cues = GuideCueState(); cadence = GuideCadence(); if active { reconcile(); tick() } }
    private func resetLeg() { origin = nil; cues = GuideCueState(); cadence = GuideCadence(); arrival = NavigationArrivalState(); decision = nil; feedback.cancelPlayback() }
    private func routeTarget(_ p: RouteFollowingProgress) -> Waypoint? {
        guard !p.complete else { return nil }
        return store.waypoints.first { $0.sourceRouteId == p.routeID && $0.sourceRoutePointIndex == p.index }
    }
    private func validate(_ p: RouteFollowingProgress) throws {
        guard let route = field.document.graphics.first(where: { $0.id == p.routeID && $0.type == "route" }), route.points.map({ GeoPoint(lat: $0.lat,lon: $0.lon) }) == p.points else { throw BoundaryError.invalid("Route changed or was deleted. Start it again to use its current vertices.") }
        var owned: [Int: Waypoint] = [:]
        for waypoint in store.waypoints where waypoint.sourceRouteId == p.routeID {
            guard let index = waypoint.sourceRoutePointIndex else { continue }
            guard owned[index] == nil else { throw BoundaryError.invalid("Route waypoint ownership is ambiguous. Restart the route.") }
            owned[index] = waypoint
        }
        guard p.points.indices.allSatisfy({ index in
            owned[index]?.lat == p.points[index].lat && owned[index]?.lon == p.points[index].lon
        }) else { throw BoundaryError.invalid("Route waypoint changed or was deleted. Restart the route.") }
    }
    private func reconcile() {
        guard running else { return }
        if let p = progress {
            do { try validate(p) } catch { pause(reason: error.localizedDescription); return }
            if store.selectedId != target?.id { pause(reason: "Route paused because you chose another target.") }
        } else {
            guard let selected = store.waypoints.first(where: { $0.id == store.selectedId }) else { pause(reason: "Navigation target was removed or cleared."); return }
            if selected.id != target?.id || selected.lat != target?.lat || selected.lon != target?.lon {
                target = selected; resetLeg(); feedback.stop(); feedback.begin()
            } else { target = selected }
        }
    }
    private func receive(_ locations: [CLLocation]) {
        guard running else { return }
        if !permitted { pause(reason: "Navigation stopped because precise location permission changed."); return }
        reconcile(); guard running else { return }
        let date = now(), up = uptime()
        if let previous = receiptClock, abs(date.timeIntervalSince(previous.0)-(up-previous.1)) > 2 {
            lastDate = nil; fix = nil; heading = nil; cues = GuideCueState(); cadence = GuideCadence(); feedback.cancelPlayback()
        }
        receiptClock = (date,up)
        for l in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard lastDate.map({ l.timestamp > $0 }) ?? true else { continue }
            let age = date.timeIntervalSince(l.timestamp)
            let sampleTime = up-age
            guard age >= 0, NavigationFixPolicy.isUsable(lat: l.coordinate.latitude,lon: l.coordinate.longitude,accuracyMeters: l.horizontalAccuracy,timestampUptime: sampleTime,nowUptime: up) else { fix = nil; continue }
            fix = l; fixTime = sampleTime; lastDate = l.timestamp
            if origin == nil { origin = .init(lat: l.coordinate.latitude,lon: l.coordinate.longitude) }
            tick()
            guard var p = progress, !p.paused, let target else { continue }
            let nav = Geodesy.navInfo(fromLat: l.coordinate.latitude,fromLon: l.coordinate.longitude,toLat: target.lat,toLon: target.lon)
            if p.arrive(distance: nav.distanceMeters,accuracy: l.horizontalAccuracy) {
                do {
                    try persist(progress: p,active: !p.complete,haptics: haptics); progress = p
                    if p.complete { finishRoute(); return }
                    guard let next = routeTarget(p) else { pause(reason: "Next route waypoint is missing."); return }
                    self.target = next; store.select(next.id); resetLeg(); feedback.stop(); feedback.begin()
                    status = "Route advanced to point \(p.index+1) of \(p.points.count)"
                    feedback.emit(.checkpoint,name: "\(p.name) · point \(p.index+1): \(next.name)")
                } catch { pause(reason: "Route progress could not be saved: \(error.localizedDescription)"); return }
            }
        }
        tick()
    }
    private func finishRoute() {
        loop?.cancel(); driver.stop(); running = false; decision = nil; feedback.cancelPlayback()
        status = "Route complete"; feedback.emit(.complete,name: progress?.name ?? "Route")
    }
    func tick() {
        guard running, let target else { return }
        if !permitted { pause(reason: "Navigation stopped because precise location permission changed."); return }
        let up = uptime(), config = settings.guideConfiguration
        let usable = fix.flatMap { l -> CLLocation? in
            NavigationFixPolicy.isUsable(lat: l.coordinate.latitude,lon: l.coordinate.longitude,accuracyMeters: l.horizontalAccuracy,timestampUptime: fixTime,nowUptime: up) ? l : nil
        }
        let nav = usable.map { Geodesy.navInfo(fromLat: $0.coordinate.latitude,fromLon: $0.coordinate.longitude,toLat: target.lat,toLon: target.lon) }
        var trueHeading: Double?
        if let l = usable {
            if driver.hasCompass, let h = heading, (0...25).contains(h.accuracy), h.magnetic.isFinite, (0..<360).contains(h.magnetic), up >= headingTime, up-headingTime <= 2 {
                if let dec = DeclinationService(overrideDegrees: settings.declinationOverride).declination(lat: l.coordinate.latitude,lon: l.coordinate.longitude,heightMeters: l.altitude,isCurrentPosition: false).degreesEast { trueHeading = h.magnetic+dec }
            } else if !driver.hasCompass, l.speed > 0.5, l.course >= 0, l.courseAccuracy >= 0, l.courseAccuracy <= 25 { trueHeading = l.course }
        }
        let leg = origin.map { Geodesy.navInfo(fromLat: $0.lat,fromLon: $0.lon,toLat: target.lat,toLon: target.lon) }.flatMap { $0.distanceMeters > 1 ? $0.bearingTrue : nil }
        let cross: Double? = usable.flatMap { l in origin.flatMap { o in leg.map { az in
            let n = Geodesy.navInfo(fromLat: o.lat,fromLon: o.lon,toLat: l.coordinate.latitude,toLon: l.coordinate.longitude)
            return GuideCueState.crossTrack(distance: n.distanceMeters,bearing: n.bearingTrue,leg: az)
        } } }
        let d = cues.update(now: up,heading: trueHeading,bearing: nav?.bearingTrue,leg: leg,crossTrack: cross,distance: nav?.distanceMeters,config: config)
        decision = d
        if usable == nil { status = "Unavailable · waiting for a fresh, accurate location" }
        else if d.cue == .unavailable { status = "Unavailable · waiting for a reliable heading" }
        else if d.outsideCorridor { status = "Off the leg line · rejoin the leg" }
        else { switch d.cue { case .left: status = "Turn left · one long pulse"; case .right: status = "Turn right · two short taps"; case .onBearing: status = "On course · ±\(settings.guideAllowance)°"; case .unavailable: break } }
        let arrived = arrival.update(target: target.id,distance: nav?.distanceMeters,accuracy: usable?.horizontalAccuracy)
        if arrived { arrivals += 1 }
        if haptics, let pulse = cadence.pulse(now: up,decision: d,arrived: arrived,heartbeat: config.heartbeat) { feedback.emit(pulse,name: target.name) }
        if feedbackStatus != feedback.status { feedbackStatus = feedback.status }
    }
    private func persist(progress: RouteFollowingProgress?,active: Bool,haptics: Bool) throws {
        let data = try JSONEncoder().encode(Saved(progress: progress,active: active,haptics: haptics))
        guard data.count < 2 * 1024 * 1024 else { throw BoundaryError.invalid("Navigation session is too large to save.") }
        try data.write(to: file,options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}
