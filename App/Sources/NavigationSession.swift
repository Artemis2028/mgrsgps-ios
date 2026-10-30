import Combine
import CoreLocation
import GridFixCore
import SwiftUI

@MainActor
final class NavigationSession: ObservableObject {
    fileprivate struct Saved: Codable, Sendable { var progress: RouteFollowingProgress?; var active: Bool; var haptics: Bool }
    @Published private(set) var progress: RouteFollowingProgress?
    @Published private(set) var running = false
    @Published private(set) var preparing = false
    @Published private(set) var saving = false
    private var queuedLocation: CLLocation?
    private var practiceFeedbackSuspended = false
    @Published private(set) var haptics = false
    @Published private(set) var status = "Navigation guide off"
    @Published private(set) var decision: GuideDecision?
    @Published private(set) var error: String?
    @Published private(set) var feedbackStatus = ""
    @Published private(set) var arrivals = 0
    @Published private(set) var lane: NavLane?
    @Published private(set) var laneDecision: LaneDecision?
    @Published private(set) var laneProblem: String?
    private let laneStore: NavigationLaneStore?
    private struct LaneKey: Equatable { var id: String; var left: [GeoPoint]; var right: [GeoPoint]; var backstop: [GeoPoint]; var objective:GeoPoint? }
    private var laneKey: LaneKey?
    private var laneGuide: LaneGuideState?
    private var laneLeftWasDrawnAsRight = false
    private var guideEvaluatedAt: TimeInterval?
    private var laneCadence = LaneCueCadence()
    private var laneUnavailableAt = 0.0
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
    private let stageSession: @Sendable (Data,URL) throws -> PreparedAtomicFile
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

    struct PreparedStartup: Sendable {
        fileprivate let file: URL
        fileprivate let stamp: SourceStamp?
        fileprivate let saved: Saved?
        fileprivate let error: String?
        func validate() throws {
            guard SourceStamp.read(file) == stamp else { throw StartupFailure.changed }
        }
    }
    enum StartupFailure: LocalizedError {
        case changed
        var errorDescription: String? { "Saved navigation session changed while opening. Try again." }
    }
    fileprivate struct SourceStamp: Equatable, Sendable {
        let size: UInt64,inode: UInt64,volume: UInt64
        let modified: Date?
        static func read(_ file: URL) -> Self? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { return nil }
            return .init(size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                         inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                         volume: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                         modified: attributes[.modificationDate] as? Date)
        }
    }
    nonisolated static func prepareStartup(directory: URL? = nil) -> PreparedStartup {
        let file = (directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!).appendingPathComponent("navigation-session-v1.json")
        let stamp = SourceStamp.read(file)
        guard FileManager.default.fileExists(atPath: file.path) else { return .init(file: file,stamp: stamp,saved: nil,error: nil) }
        do {
            guard stamp.map({ $0.size < 2 * 1024 * 1024 }) ?? true else { throw BoundaryError.invalid("Navigation state is too large.") }
            let data = try Data(contentsOf: file,options: .mappedIfSafe)
            guard data.count < 2 * 1024 * 1024 else { throw BoundaryError.invalid("Navigation state is too large.") }
            let saved = try JSONDecoder().decode(Saved.self,from: data)
            if let p = saved.progress {
                guard (2...10_000).contains(p.points.count),(0...p.points.count).contains(p.index),p.points.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite && (-90...90).contains($0.lat) && (-180...180).contains($0.lon) }) else { throw BoundaryError.invalid("Invalid route progress.") }
            }
            return .init(file: file,stamp: stamp,saved: saved,error: nil)
        } catch { return .init(file: file,stamp: stamp,saved: nil,error: "Navigation state was kept: \(error.localizedDescription). Clear the session to start again.") }
    }

    init(directory: URL? = nil, store: WaypointStore, field: FieldDataStore, settings: AppSettings,startup: PreparedStartup? = nil,
         driver: NavigationLocationDriver? = nil, feedback: NavigationFeedback? = nil, lanes: NavigationLaneStore? = nil,
         now: @escaping () -> Date = Date.init, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         foreground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }, scheduleTicks: Bool = true,
         stageSession: @escaping @Sendable (Data,URL) throws -> PreparedAtomicFile = { try PreparedAtomicFile(data: $0,destination: $1,lockCompatible: true) }) {
        self.store = store; self.field = field; self.settings = settings
        self.laneStore = lanes
        self.driver = driver ?? CoreLocationNavigationDriver(); self.feedback = feedback ?? SystemNavigationFeedback()
        self.now = now; self.uptime = uptime; self.foreground = foreground; self.scheduleTicks = scheduleTicks; self.stageSession = stageSession
        file = (directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!).appendingPathComponent("navigation-session-v1.json")
        let prepared = startup ?? Self.prepareStartup(directory: directory)
        do {
            guard prepared.file == file else { throw BoundaryError.invalid("Prepared navigation belongs to another saved session.") }
            try prepared.validate()
            if let failure = prepared.error { loaded = false; error = failure }
            else if let saved = prepared.saved {
                progress = saved.progress; progress?.paused = true
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
        store.$practiceNavigationSavePending.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.store.practiceNavigationSavePending { self.waitForPracticeTarget() }
                else { self.practiceTargetDidSave() }
            }
        }.store(in: &subscriptions)
        store.$selectedId.sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &subscriptions)
        store.$waypoints.sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &subscriptions)
        field.$document.sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &subscriptions)
        lanes?.$lanes.sink { [weak self] _ in Task { @MainActor in self?.tick() } }.store(in: &subscriptions)
    }
    private var permitted: Bool { (driver.authorization == .authorizedWhenInUse || driver.authorization == .authorizedAlways) && driver.precise && driver.servicesEnabled }
    func follow(_ route: Backup.Graphic,startIndex: Int = 0) {
        guard !store.practiceNavigationSavePending else { error = "Wait for the course target to finish saving, or retry its save."; return }
        guard !store.practiceNavigationLocked else { error = "End the practice course before following a route."; return }
        guard !running, !preparing, loaded else { return }
        guard route.type == "route", (2...10_000).contains(route.points.count), route.points.indices.contains(startIndex) else { error = "Choose a route with 2–10,000 vertices and a valid start point."; return }
        guard field.document.graphics.contains(route) else { error = "The route has changed. Reopen it before following."; return }
        guard foreground() else { error = "Open the app before starting navigation."; return }
        guard driver.servicesEnabled else { error = "Enable Location Services for navigation."; return }
        if driver.authorization == .notDetermined {
            preparing = true; error = nil
            pending = { [weak self] in self?.follow(route,startIndex: startIndex) }; driver.requestPermission(); return
        }
        guard permitted else { error = "Navigation needs While Using permission and Precise Location."; return }
        operation?.cancel(); saving = false
        preparing = true; error = nil; generation = UUID(); let token = generation
        operation = Task {
            do {
                try await RouteWaypointAction.generate(route,to: store,field: field) {
                    guard self.generation == token else { throw CancellationError() }
                    guard !self.store.practiceNavigationLocked else { throw BoundaryError.invalid("End the practice course before following a route.") }
                }
                guard generation == token else { return }
                preparing = false
                let points = route.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) }
                launch(progress: RouteFollowingProgress(routeID: route.id,name: route.name,points: points,index: startIndex),haptics: true)
            } catch {
                guard generation == token else { return }
                preparing = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
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
        guard field.ready else { error = "Wait for the field library to finish loading."; return }
        guard !store.practiceNavigationSavePending else { error = "Wait for the course target to finish saving, or retry its save."; return }
        guard laneStore?.ready ?? true else { error = laneStore?.error ?? "Loading navigation lanes. Try again in a moment."; return }
        guard requested == nil || !store.practiceNavigationLocked else { error = "End the practice course before following a route."; return }
        guard !running, !preparing, loaded else { return }
        guard foreground() else { error = "Open the app before starting navigation."; return }
        guard driver.servicesEnabled else { error = "Enable Location Services for navigation."; return }
        if driver.authorization == .notDetermined {
            preparing = true; pending = { [weak self] in self?.launch(progress: requested,haptics: enabled) }; driver.requestPermission(); return
        }
        guard permitted else { error = "Navigation needs While Using permission and Precise Location."; return }
        operation?.cancel(); saving = false
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
                let originalSelection = store.selectedId
                let targetIntent = try await WaypointEditAction.select(target.id,in: store) {
                    guard self.generation == token else { throw CancellationError() }
                    guard !self.store.practiceNavigationSavePending else { throw BoundaryError.invalid("The course target is still being saved.") }
                    guard self.foreground(), self.permitted else { throw BoundaryError.invalid("Start navigation with the app open and precise location enabled.") }
                    if let next {
                        guard !self.store.practiceNavigationLocked else { throw BoundaryError.invalid("End the practice course before following a route.") }
                        try self.validate(next)
                    } else {
                        guard self.store.selectedId == originalSelection,
                              self.store.waypoints.first(where: { $0.id == target.id }) == target else { throw BoundaryError.invalid("Navigation target changed. Start guidance again.") }
                    }
                }
                let lease = saveGrace(token); defer { endSaveGrace(lease) }
                try await persist(progress: next,active: true,haptics: enabled,token: token) {
                    guard !self.store.practiceNavigationSavePending, self.foreground(), self.permitted, self.store.selectedId == target.id, self.store.selectionIsCurrent(targetIntent) else { throw BoundaryError.invalid("Navigation target or location access changed. Start again.") }
                    if let next {
                        guard !self.store.practiceNavigationLocked else { throw BoundaryError.invalid("End the practice course before following a route.") }
                        try self.validate(next)
                    }
                }
                self.progress = next; haptics = enabled; running = true; preparing = false
                arrivals = 0; fix = nil; lastDate = nil; receiptClock = nil; heading = nil
                resetLeg(); feedback.begin(); feedbackStatus = feedback.status; driver.start()
                status = "Waiting for a fresh position and heading"
                startTicks()
            } catch {
                guard generation == token else { return }
                preparing = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
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
        guard !saving, !store.practiceNavigationSavePending else { return }
        guard running else { if enabled { startGuide() }; return }
        if !enabled && progress == nil { haptics = false; pause(); return }
        saving = true; let token = generation, requested = progress
        operation = Task {
            let lease = saveGrace(token); defer { endSaveGrace(lease) }
            do {
                try await persist(progress: requested,active: true,haptics: enabled,token: token) {
                    if let requested { try self.validate(requested) }
                    guard self.store.waypoints.contains(where: { $0.id == self.store.selectedId }) else { throw BoundaryError.invalid("Navigation target was removed.") }
                }
                haptics = enabled; saving = false; resetLeg(); reconcile(); drainLocation()
            } catch {
                guard generation == token else { return }
                saving = false; pause(reason: "Guide settings could not be saved: \(error.localizedDescription)")
            }
        }
    }
    func pause(reason: String? = nil,save: Bool = true) {
        generation = UUID(); operation?.cancel(); pending = nil; preparing = false; saving = false; queuedLocation = nil
        loop?.cancel(); driver.stop(); feedback.stop(); practiceFeedbackSuspended = false; running = false; fix = nil; heading = nil; decision = nil
        clearLane()
        progress?.paused = true; status = progress == nil ? "Navigation guide off" : "Route paused"
        if let reason { error = reason }
        if save && loaded { saveInactive() }
    }
    func stop() {
        pause(save: false); progress = nil; haptics = false; status = "Navigation stopped"
        if loaded { saveInactive() }
    }
    private func saveInactive() {
        let token = generation, requested = progress, enabled = haptics
        saving = true
        operation = Task {
            let lease = saveGrace(token); defer { endSaveGrace(lease) }
            do { try await persist(progress: requested,active: false,haptics: enabled,token: token); saving = false }
            catch {
                guard generation == token else { return }
                saving = false; self.error = "Navigation stopped; progress could not be saved: \(error.localizedDescription)"
            }
        }
    }
    func clearSavedSession() {
        pause(save: false)
        do {
            if !loaded, FileManager.default.fileExists(atPath: file.path) { try FileManager.default.moveItem(at: file,to: file.deletingLastPathComponent().appendingPathComponent("navigation-damaged-\(UUID().uuidString).json")) }
            let token = generation; saving = true; preparing = true
            operation = Task {
                let lease = saveGrace(token); defer { endSaveGrace(lease) }
                do {
                    try await persist(progress: nil,active: false,haptics: false,token: token)
                    loaded = true; progress = nil; haptics = false; error = nil; status = "Navigation guide off"; saving = false; preparing = false
                } catch {
                    guard generation == token else { return }
                    saving = false; preparing = false; self.error = error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func movePoint(_ delta: Int) {
        guard !saving, !preparing, !store.practiceNavigationLocked, var p = progress else { return }
        p.index = min(p.points.count,max(0,p.index+delta))
        transition(to: p,announce: false)
    }
    private func transition(to nextProgress: RouteFollowingProgress,announce: Bool) {
        guard !saving, let previous = progress else { return }
        let token = generation, wasRunning = running, originalTarget = store.selectedId
        let next = routeTarget(nextProgress)
        saving = true; decision = nil; feedback.cancelPlayback()
        operation = Task {
            let lease = saveGrace(token); defer { endSaveGrace(lease) }
            @MainActor func check(_ selected: String?) throws {
                try Task.checkCancellation()
                guard self.generation == token, self.progress == previous, self.running == wasRunning else { throw CancellationError() }
                guard !self.store.practiceNavigationLocked, self.store.selectedId == selected else { throw BoundaryError.invalid("Route paused because you chose another target or started a course.") }
                if wasRunning && !self.permitted { throw BoundaryError.invalid("Precise location permission changed.") }
                try self.validate(nextProgress)
            }
            do {
                try check(originalTarget)
                var targetIntent: UUID?
                if !nextProgress.complete {
                    guard let next else { throw BoundaryError.invalid("Next route waypoint is missing.") }
                    targetIntent = try await WaypointEditAction.select(next.id,in: store) { try check(originalTarget) }
                }
                try await persist(progress: nextProgress,active: wasRunning && !nextProgress.complete,haptics: haptics,token: token) {
                    try check(nextProgress.complete ? originalTarget : next?.id)
                    if let targetIntent, !self.store.selectionIsCurrent(targetIntent) { throw CancellationError() }
                }
                progress = nextProgress; saving = false
                if nextProgress.complete { queuedLocation = nil; finishRoute(); return }
                guard let next else { throw BoundaryError.invalid("Next route waypoint is missing.") }
                target = next; resetLeg(); resetTargetFeedback()
                status = wasRunning ? "Route advanced to point \(nextProgress.index+1) of \(nextProgress.points.count)" : "Route paused"
                if announce && wasRunning { feedback.emit(.checkpoint,name: "\(nextProgress.name) · point \(nextProgress.index+1): \(next.name)") }
                drainLocation()
            } catch {
                guard generation == token else { return }
                saving = false
                pause(reason: error is CancellationError ? "Route paused because a newer target was chosen." : "Route progress could not be saved: \(error.localizedDescription)")
            }
        }
    }
    private func queueLocation(_ locations: [CLLocation]) {
        let date = now(), up = uptime()
        if let previous = receiptClock, abs(date.timeIntervalSince(previous.0)-(up-previous.1)) > 2 { queuedLocation = nil }
        let usable = locations.filter { sample in
            let age = date.timeIntervalSince(sample.timestamp)
            return age >= 0 && NavigationFixPolicy.isUsable(lat: sample.coordinate.latitude,lon: sample.coordinate.longitude,accuracyMeters: sample.horizontalAccuracy,timestampUptime: up-age,nowUptime: up)
        }
        guard let latest = usable.max(by: { $0.timestamp < $1.timestamp }), queuedLocation.map({ latest.timestamp > $0.timestamp }) ?? true else { return }
        queuedLocation = latest
    }
    private func drainLocation() {
        let latest = queuedLocation; queuedLocation = nil
        if running, let latest { receive([latest]) }
    }
    func foregroundChanged(_ active: Bool) { feedback.cancelPlayback(); cues = GuideCueState(); cadence = GuideCadence(); if active { reconcile(); tick() } }
    private func resetTargetFeedback() {
        guard !practiceFeedbackSuspended else { return }
        guard running else { feedback.stop(); return }
        if let laneKey, NavLanes.forTarget(laneStore?.lanes ?? [],target: target)?.id == laneKey.id { feedback.cancelPlayback() }
        else { feedback.stop(); feedback.begin() }
    }
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
    func waitForPracticeTarget() {
        if preparing { pause(reason: "Wait for the course target to finish saving.") }
        guard running else { return }
        decision = nil; laneDecision = nil; guideEvaluatedAt = nil
        if !practiceFeedbackSuspended {
            // Stop invalidates async notification submissions as well as the
            // physical player. The guide's GPS/run remains active.
            feedback.stop(); practiceFeedbackSuspended = true
        }
        status = "Saving course target"
    }
    func practiceTargetDidSave() {
        guard !store.practiceNavigationSavePending else { waitForPracticeTarget(); return }
        reconcile()
        if running, practiceFeedbackSuspended { practiceFeedbackSuspended = false; feedback.begin() }
        drainLocation(); tick()
    }
    private func reconcile() {
        guard field.ready, running, !saving, !store.practiceNavigationSavePending else { return }
        if let p = progress {
            do { try validate(p) } catch { pause(reason: error.localizedDescription); return }
            if store.selectedId != target?.id { pause(reason: "Route paused because you chose another target.") }
        } else {
            guard let selected = store.waypoints.first(where: { $0.id == store.selectedId }) else { pause(reason: "Navigation target was removed or cleared."); return }
            if selected.id != target?.id || selected.lat != target?.lat || selected.lon != target?.lon {
                target = selected; resetLeg(); resetTargetFeedback()
            } else { target = selected }
        }
    }
    private func receive(_ locations: [CLLocation]) {
        guard running else { return }
        if !permitted { pause(reason: "Navigation stopped because precise location permission changed."); return }
        if saving || store.practiceNavigationSavePending { queueLocation(locations); tick(); return }
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
                transition(to: p,announce: true)
                queueLocation(locations.filter { $0.timestamp > l.timestamp })
                return
            }
        }
        tick()
    }
    private func finishRoute() {
        loop?.cancel(); driver.stop(); running = false; decision = nil; feedback.cancelPlayback()
        clearLane(); status = "Route complete"; feedback.emit(.complete,name: progress?.name ?? "Route")
    }
    func tick() {
        guard running, !saving else { return }
        if store.practiceNavigationSavePending { waitForPracticeTarget(); return }
        if store.selectedId != target?.id { reconcile() }
        guard running, let target else { return }
        defer { guideEvaluatedAt = uptime() }
        if !permitted { pause(reason: "Navigation stopped because precise location permission changed."); return }
        let up = uptime(), config = settings.guideConfiguration
        let usable = fix.flatMap { l -> CLLocation? in
            NavigationFixPolicy.isUsable(lat: l.coordinate.latitude,lon: l.coordinate.longitude,accuracyMeters: l.horizontalAccuracy,timestampUptime: fixTime,nowUptime: up) ? l : nil
        }
        let nav = usable.map { Geodesy.navInfo(fromLat: $0.coordinate.latitude,fromLon: $0.coordinate.longitude,toLat: target.lat,toLon: target.lon) }
        if guideLane(target: target,fix: usable,nav: nav,uptime: up) { return }
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
    private func clearLane() {
        if laneGuide != nil { cues = GuideCueState(); cadence = GuideCadence(); feedback.cancelPlayback() }
        lane = nil; laneDecision = nil; laneProblem = nil; laneKey = nil; laneGuide = nil
        laneCadence.reset(); laneUnavailableAt = 0
    }
    private func guideLane(target: Waypoint,fix: CLLocation?,nav: Geodesy.NavInfo?,uptime up: TimeInterval) -> Bool {
        guard let value = NavLanes.forTarget(laneStore?.lanes ?? [],target: target) else { if lane != nil || laneProblem != nil { clearLane() }; return false }
        if lane != value { lane = value }
        do {
            guard let l = NavLanes.points(value.left,graphics: field.document.graphics),let r = NavLanes.points(value.right,graphics: field.document.graphics),let b = NavLanes.points(value.backstop,graphics: field.document.graphics) else {
                throw LaneShapeErrorForApp("A linked lane line is missing.")
            }
            let objective=NavLanes.objective(value,graphics:field.document.graphics,waypoints:store.waypoints)
            let key = LaneKey(id: value.id,left: l,right: r,backstop: b,objective:objective)
            if key != laneKey {
                let entered = laneKey?.id == value.id && laneGuide.map {$0.state != .notYet} == true
                let shape = try LaneShape(leftDrawn: l,rightDrawn: r,backstopDrawn: b,objective:objective)
                laneLeftWasDrawnAsRight = shape.leftWasDrawnAsRight
                laneGuide = LaneGuideState(shape: shape,entered:entered)
                laneKey = key; laneCadence.reset(); laneUnavailableAt = 0; feedback.cancelPlayback()
            }
            var configuration = LaneGuideConfiguration(); configuration.warningMeters = Double(settings.laneWarningM); configuration.notInLaneReminderSeconds = Double(settings.laneReminderMin)*60
            laneGuide?.configuration = configuration
            laneProblem = nil; decision = nil
            guard let fix else {
                laneGuide?.invalidateFix(); laneDecision = nil
                status = "Nav lane · unavailable · waiting for a fresh, accurate location"
                if haptics && settings.laneGpsAlert && up >= laneUnavailableAt { feedback.emit(.unavailable,name: value.name); laneUnavailableAt = up+60 }
                feedbackStatus = feedback.status; return true
            }
            laneUnavailableAt = 0
            let result = laneGuide!.update(position: .init(lat: fix.coordinate.latitude,lon: fix.coordinate.longitude),accuracy: fix.horizontalAccuracy,fixTime: fixTime)
            laneDecision = result
            switch result.state {
            case .notYet: status = "Not in the lane yet · silent until you’re between the limits"
            case .inside: status = "Inside lane · silent"
            case .outLeft: status = "Past left limit · turn right"
            case .outRight: status = "Past right limit · turn left"
            case .overshot:
                status = "Past backstop · turn back"
                if let nav { status += String(format: " · %03.0f° T · %.0f m to %@",nav.bearingTrue,nav.distanceMeters,target.name) }
            }
            let arrived = arrival.update(target: target.id,distance: nav?.distanceMeters,accuracy: fix.horizontalAccuracy)
            if arrived { arrivals += 1 }
            var switches=LaneCues()
            switches.sides=settings.laneSideCues; switches.backstop=settings.laneBackstopCue
            switches.insideTick=settings.laneInsideTick; switches.reminder=settings.laneReminderMin>0
            laneCadence.cues=switches
            let pulse = laneCadence.next(decision: result,now: up)
            if haptics {
                if arrived { feedback.emit(.arrival,name: target.name) }
                if let pulse, !arrived || !foreground() {
                    let output: NavigationPulse
                    switch pulse {
                    case .turnRight: output = result.changed ? .laneLeftCrossing : .right
                    case .turnLeft: output = result.changed ? .laneRightCrossing : .left
                    case .overshot: output = result.changed ? .laneBackstopCrossing : .laneOvershot
                    case .backInside: output = .laneReentered
                    case .notInLane: output = .laneNotEntered
                    }
                    feedback.emit(output,name: "\(value.name) · \(status)")
                }
            }
            feedbackStatus = feedback.status; return true
        } catch {
            if laneGuide != nil { cues = GuideCueState(); cadence = GuideCadence(); feedback.cancelPlayback() }
            laneProblem = "\(error.localizedDescription) Using azimuth guidance."
            laneGuide = nil; laneKey = nil; laneDecision = nil; laneCadence.reset()
            return false
        }
    }
    private func persist(progress: RouteFollowingProgress?,active: Bool,haptics: Bool,token: UUID,
                         validate: @MainActor () throws -> Void = {}) async throws {
        let saved = Saved(progress: progress,active: active,haptics: haptics), destination = file, prepare = stageSession
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try JSONEncoder().encode(saved)
            guard data.count < 2 * 1024 * 1024 else { throw BoundaryError.invalid("Navigation session is too large to save.") }
            return try prepare(data,destination)
        }
        let staged = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        try validate()
        try staged.publish()
    }
    @MainActor private final class SaveLease {
        var identifier: UIBackgroundTaskIdentifier = .invalid
        func end() {
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid }
        }
    }
    private func saveGrace(_ token: UUID) -> SaveLease {
        let lease = SaveLease()
        lease.identifier = UIApplication.shared.beginBackgroundTask(withName: "Save navigation progress") { [weak self] in
            Task { @MainActor in
                lease.end()
                guard let self, self.generation == token else { return }
                self.pause(reason: "Navigation paused because iOS ended its save time. Resume with the app open.",save: false)
            }
        }
        return lease
    }
    private func endSaveGrace(_ lease: SaveLease) { lease.end() }
}

private struct LaneShapeErrorForApp: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension NavigationSession {
    func liveActivitySession() -> FieldActivitySession? {
        guard running,let target else { return nil }
        let usable=fix.flatMap { value in NavigationFixPolicy.isUsable(lat:value.coordinate.latitude,lon:value.coordinate.longitude,accuracyMeters:value.horizontalAccuracy,timestampUptime:fixTime,nowUptime:uptime()) ? value : nil }
        let distance=usable.map { Geodesy.navInfo(fromLat:$0.coordinate.latitude,fromLon:$0.coordinate.longitude,toLat:target.lat,toLon:target.lon).distanceMeters }
        let checkpoint=progress.map { " · CP \(min($0.index+1,$0.points.count))/\($0.points.count)" } ?? ""
        let title=String((progress?.name ?? target.name).prefix(80))
        let grid=usable.flatMap { MGRS.parts(lat:$0.coordinate.latitude,lon:$0.coordinate.longitude,digits:settings.mgrsDigits)?.full }
        let waiting = saving || store.practiceNavigationSavePending
        let state=FieldActivityState(title:title,status:waiting ? (store.practiceNavigationSavePending ? "Saving course target" : "Saving navigation progress") : String(status.prefix(160)),detail:waiting ? "Waiting for saved progress" : (distance.map { Format.distance(meters:$0,unit:settings.units) } ?? "Position unavailable")+checkpoint,
            grid:grid,fixDate:usable?.timestamp,fixExpiresAt:usable?.timestamp.addingTimeInterval(10),startedAt:nil,fixUptime:usable == nil ? nil : fixTime,night:settings.nightMode)
        return .init(id:progress.map { "route:"+$0.routeID } ?? "target:"+target.id,kind:"navigation",state:state)
    }
}

// Export the owner's confirmed decision only. Transport heartbeats cannot make
// a suspended loop, expired phone fix or unavailable heading appear usable.
extension NavigationSession {
    func watchGuideSnapshot(sourceID: String, revision: Int64) -> WatchGuideSnapshot {
        let date = now()
        let at = Int64(date.timeIntervalSince1970 * 1000)
        guard running, let target else { return .init(sourceID: sourceID,revision: revision,at: at,active: false) }
        if saving || store.practiceNavigationSavePending { return .init(sourceID:sourceID,revision:revision,at:at,active:true,available:false,targetName:String(target.name.prefix(120)),status:store.practiceNavigationSavePending ? "Saving course target" : "Saving navigation progress") }
        let up = uptime()
        let evaluated = guideEvaluatedAt.map { up >= $0 && up-$0 <= 2 } ?? false
        let position = permitted && fix.map { NavigationFixPolicy.isUsable(lat:$0.coordinate.latitude,lon:$0.coordinate.longitude,accuracyMeters:$0.horizontalAccuracy,timestampUptime:fixTime,nowUptime:up) } == true
        let hasLane = lane != nil && laneDecision != nil && laneProblem == nil
        let state: String? = hasLane ? laneDecision.map {
            switch $0.state { case .notYet: return "NOT_YET"; case .inside: return "INSIDE"; case .outLeft: return "OUT_LEFT"; case .outRight: return "OUT_RIGHT"; case .overshot: return "OVERSHOT" }
        } : nil
        var crossed: String?
        if hasLane, let lane, let state {
            let line: LaneLine? = state == "OUT_LEFT" ? (laneLeftWasDrawnAsRight ? lane.right : lane.left) : state == "OUT_RIGHT" ? (laneLeftWasDrawnAsRight ? lane.left : lane.right) : state == "OVERSHOT" ? lane.backstop : nil
            if let line { crossed = String(NavLanes.label(line,graphics:field.document.graphics,fallback: state == "OVERSHOT" ? "backstop" : "side limit").prefix(120)) }
        }
        return .init(sourceID:sourceID,revision:revision,at:at,active:true,available:evaluated && position && (hasLane || decision.map { $0.cue != .unavailable } == true),targetName:String(target.name.prefix(120)),status:String(status.prefix(160)),laneName:hasLane ? String((lane?.name ?? "Nav lane").prefix(120)) : nil,laneState:state,crossedLine:crossed)
    }
}
