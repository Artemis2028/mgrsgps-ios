import Combine
import GridFixCore
import SwiftUI

@MainActor
final class PracticeSession: ObservableObject {
    @Published private(set) var active: PracticeCourse?
    @Published private(set) var summary: Backup.CourseResult?
    @Published private(set) var blockedByStorage = false
    @Published private(set) var finalizing = false
    private var finalization: Task<Void,Never>?
    private var failedFinalizationRunID: String?
    @Published private(set) var error: String?
    private let saved: PracticeCourseStore
    private let waypoints: WaypointStore
    private let field: FieldDataStore
    private let navigation: NavigationSession
    private var subscriptions = Set<AnyCancellable>()
    private var reconciling = false
    private var foreground = false
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    var damaged: Bool { saved.loadError != nil }
    var locked: Bool { active != nil || damaged }

    init(directory: URL?,waypoints: WaypointStore,field: FieldDataStore,navigation: NavigationSession,
         now: @escaping () -> Date = Date.init,uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        saved = PracticeCourseStore(directory: directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!)
        self.waypoints = waypoints; self.field = field; self.navigation = navigation; self.now = now; self.uptime = uptime
        active = saved.active; error = saved.loadError
        waypoints.$waypoints.sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &subscriptions)
        reconcile()
    }
    func setForeground(_ value: Bool) { foreground = value; if value { reconcile() } }
    func startFolder(_ folder: String) {
        guard !locked else { return }
        do {
            let points = waypoints.waypoints.filter { $0.folder == folder }
            try begin(name: folder,ids: points.map(\.id))
        } catch { self.error = error.localizedDescription }
    }
    func startRandom(count: Int,radius: Int,fix: Fix?) {
        guard !locked else { return }
        do {
            guard let fix, NavigationFixPolicy.isUsable(lat: fix.lat,lon: fix.lon,accuracyMeters: fix.accuracyMeters,timestampUptime: fix.timestampUptime,nowUptime: uptime()) else { throw PracticeCourseError.invalid("A recent, precise GPS fix is required to scatter checkpoints.") }
            let points = try PracticeCourseGenerator.scatter(origin: .init(lat: fix.lat,lon: fix.lon),count: count,radius: radius)
            let folder = "Course "+String(Format.dtg(now()).prefix(7))
            let added = try waypoints.addPracticePoints(folder: folder,points: points)
            do { try begin(name: folder,ids: added.map(\.id)) }
            catch { throw PracticeCourseError.invalid("Checkpoints were saved in \(folder), but the course could not start: \(error.localizedDescription)") }
        } catch { self.error = error.localizedDescription }
    }
    private func begin(name: String,ids: [String]) throws {
        let course = try PracticeCourse(name: name,waypointIDs: ids,startedAt: millis)
        try saved.save(course)
        if navigation.progress != nil { navigation.stop() }
        active = course; summary = nil; error = nil; reconcile()
    }
    func reconcile() {
        guard !reconciling, !finalizing else { return }
        if let failedFinalizationRunID, saved.active?.runID == failedFinalizationRunID, saved.active?.done == true { return }
        let recovering = blockedByStorage
        blockedByStorage = false
        reconciling = true; defer { reconciling = false; if recovering && !blockedByStorage { error = nil } }
        do {
            if damaged { try waypoints.setPracticeNavigationTarget(nil,locked: true); if navigation.running || navigation.preparing { navigation.pause() }; return }
            guard var course = saved.active else {
                active = nil
                if waypoints.practiceNavigationLocked { try waypoints.setPracticeNavigationTarget(waypoints.selectedId,locked: false) }
                return
            }
            if navigation.progress != nil { navigation.stop() }
            course.reconcile(availableIDs: Set(waypoints.waypoints.map(\.id)))
            if course != saved.active { try saved.save(course) }
            active = course
            if let result = course.result {
                finalize(course,result: result)
            } else {
                try waypoints.setPracticeNavigationTarget(course.targetID,locked: true)
                if course.paused && (navigation.running || navigation.preparing) { navigation.pause(reason: course.pauseReason) }
            }
        } catch { blockedByStorage = true; self.error = error.localizedDescription; if navigation.running || navigation.preparing { navigation.pause(reason: "Course progress needs attention.") } }
    }
    private func finalize(_ course: PracticeCourse,result: Backup.CourseResult) {
        finalizing = true; error = nil
        finalization = Task {
            let grace = FinalizationGrace()
            defer { grace.end(); finalization = nil; finalizing = false }
            do {
                var document = Backup.Document(); document.hasSettings = false; document.courseHistory = [result]
                _ = try await LibraryRestoreCommit.field(document,into: field)
                // Completion is a confirmed operation owned by this session,
                // including after its sheet disappears. It never clears a new run.
                guard saved.active == course else { throw PracticeCourseError.invalid("The active course changed. Reopen it before finishing.") }
                while true {
                    let snapshot = saved.saveSnapshot()
                    let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepare(nil) }.value
                    guard saved.active == course else { throw PracticeCourseError.invalid("The active course changed. Reopen it before finishing.") }
                    if try saved.publish(prepared) { break }
                }
                active = nil; summary = result; blockedByStorage = false; failedFinalizationRunID = nil
                try waypoints.setPracticeNavigationTarget(waypoints.selectedId,locked: false)
            } catch {
                failedFinalizationRunID = course.runID; blockedByStorage = true
                self.error = saved.active == course ? "The completed run is kept. Retry saving its result. \(error.localizedDescription)" : "Result saved; target settings need attention. \(error.localizedDescription)"
                if navigation.running || navigation.preparing { navigation.pause(reason: "Course progress needs attention.") }
            }
        }
    }
    func retryResult() {
        guard !finalizing else { return }
        failedFinalizationRunID = nil; reconcile()
    }
    @MainActor private final class FinalizationGrace {
        private var identifier: UIBackgroundTaskIdentifier = .invalid
        init() {
            identifier = UIApplication.shared.beginBackgroundTask(withName: "Save practice result") { [weak self] in
                Task { @MainActor in self?.end() }
            }
        }
        func end() {
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid }
        }
    }
    func receive(_ fix: Fix?) {
        guard foreground else { return }
        reconcile()
        guard !blockedByStorage, var course = active, let id = course.targetID, let target = waypoints.waypoints.first(where: { $0.id == id }), let fix,
              NavigationFixPolicy.isUsable(lat: fix.lat,lon: fix.lon,accuracyMeters: fix.accuracyMeters,timestampUptime: fix.timestampUptime,nowUptime: uptime()) else { return }
        let nav = Geodesy.navInfo(fromLat: fix.lat,fromLon: fix.lon,toLat: target.lat,toLon: target.lon)
        guard PracticeCourse.canScore(distance: nav.distanceMeters,accuracy: fix.accuracyMeters) else { return }
        do {
            guard try course.markFound(runID: course.runID,checkpointID: id,now: millis) else { return }
            try saved.save(course); active = course; error = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            reconcile()
        } catch { self.error = error.localizedDescription }
    }
    func end(expectedRunID: String?) {
        guard saved.active?.runID == expectedRunID, saved.active?.done != true, !damaged else { return }
        do { try saved.save(nil); active = nil; error = nil; reconcile() }
        catch { self.error = error.localizedDescription }
    }
    func resetDamaged() {
        do { try saved.preserveDamagedAndReset(); error = nil; reconcile() }
        catch { self.error = error.localizedDescription }
    }
    func dismissSummary() { summary = nil }
    private var millis: Int64 { Int64(now().timeIntervalSince1970*1000) }
}
