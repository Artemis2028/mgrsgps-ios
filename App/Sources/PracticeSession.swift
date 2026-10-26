import Combine
import GridFixCore
import SwiftUI

@MainActor
final class PracticeSession: ObservableObject {
    @Published private(set) var active: PracticeCourse?
    @Published private(set) var summary: Backup.CourseResult?
    @Published private(set) var blockedByStorage = false
    @Published private(set) var finalizing = false
    @Published private(set) var working = false
    private enum Write {
        case start(PracticeCourse)
        case random(WaypointStore.PracticePointsEdit,String)
        case reconcile(PracticeCourse)
        case score(previous: PracticeCourse,next: PracticeCourse,target: Waypoint)
        case end(String)
    }
    private var operation: Task<Void,Never>?
    private var generation = UUID()
    private var pendingWrite: Write?
    private var queuedFix: Fix?
    private var targetWriteFailed = false
    private let scoreFeedback: @MainActor () -> Void
    private let prepareCourse: @Sendable (PracticeCourseStore.SaveSnapshot,PracticeCourse?) throws -> PracticeCourseStore.PreparedSave
    private let preparePoints: @Sendable (WaypointStore.RestoreSnapshot,WaypointStore.PracticePointsEdit) throws -> WaypointStore.PreparedPracticePoints
    private let prepareTarget: @Sendable (WaypointStore.RestoreSnapshot,WaypointStore.PracticeSelection) throws -> WaypointStore.PreparedPracticeSelection
    var hasPendingWrite: Bool { pendingWrite != nil || targetWriteFailed }
    var canCancelStart: Bool {
        switch pendingWrite { case .start, .random: return saved.active == nil; default: return false }
    }
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
    var locked: Bool { active != nil || damaged || working || finalizing }

    init(directory: URL?,waypoints: WaypointStore,field: FieldDataStore,navigation: NavigationSession,
         now: @escaping () -> Date = Date.init,uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         prepareCourse: @escaping @Sendable (PracticeCourseStore.SaveSnapshot,PracticeCourse?) throws -> PracticeCourseStore.PreparedSave = { try $0.prepare($1) },
         preparePoints: @escaping @Sendable (WaypointStore.RestoreSnapshot,WaypointStore.PracticePointsEdit) throws -> WaypointStore.PreparedPracticePoints = { try $0.preparePracticePoints($1) },
         prepareTarget: @escaping @Sendable (WaypointStore.RestoreSnapshot,WaypointStore.PracticeSelection) throws -> WaypointStore.PreparedPracticeSelection = { try $0.preparePracticeSelection($1) },
         scoreFeedback: @escaping @MainActor () -> Void = { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }) {
        saved = PracticeCourseStore(directory: directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!)
        self.waypoints = waypoints; self.field = field; self.navigation = navigation; self.now = now; self.uptime = uptime; self.prepareCourse = prepareCourse; self.preparePoints = preparePoints; self.prepareTarget = prepareTarget; self.scoreFeedback = scoreFeedback
        active = saved.active; error = saved.loadError
        waypoints.$waypoints.sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &subscriptions)
        reconcile()
    }
    func setForeground(_ value: Bool) { foreground = value; if value { reconcile() } }
    func startFolder(_ folder: String) {
        guard !locked, !hasPendingWrite else { return }
        do {
            let points = waypoints.waypoints.filter { $0.folder == folder }
            try begin(name: folder,ids: points.map(\.id))
        } catch { self.error = error.localizedDescription }
    }
    func startRandom(count: Int,radius: Int,fix: Fix?) {
        guard !locked, !hasPendingWrite else { return }
        guard let fix, NavigationFixPolicy.isUsable(lat: fix.lat,lon: fix.lon,accuracyMeters: fix.accuracyMeters,timestampUptime: fix.timestampUptime,nowUptime: uptime()) else {
            error = "A recent, precise GPS fix is required to scatter checkpoints."; return
        }
        let origin = GeoPoint(lat: fix.lat,lon: fix.lon), date = now()
        let createdAt = Int64(date.timeIntervalSince1970*1000)
        let folder = "Course "+String(Format.dtg(date).prefix(7))
        generation = UUID(); let token = generation
        working = true; error = nil; blockedByStorage = false
        operation = Task {
            let grace = FinalizationGrace(); defer { grace.end() }
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let points = try PracticeCourseGenerator.scatter(origin: origin,count: count,radius: radius)
                let edit = WaypointStore.PracticePointsEdit(folder: folder,points: points,now: createdAt)
                return edit
            }
            do {
                let edit = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard generation == token else { return }
                operation = nil; perform(.random(edit,folder))
            } catch {
                guard generation == token else { return }
                working = false; operation = nil; self.error = error.localizedDescription
            }
        }
    }
    private func begin(name: String,ids: [String]) throws {
        let course = try PracticeCourse(name: name,waypointIDs: ids,startedAt: millis)
        perform(.start(course))
    }
    func reconcile() {
        guard !reconciling, !finalizing, !working, pendingWrite == nil, !targetWriteFailed else { return }
        if let failedFinalizationRunID, saved.active?.runID == failedFinalizationRunID, saved.active?.done == true { return }
        reconciling = true; defer { reconciling = false }
        if damaged {
            if navigation.running || navigation.preparing { navigation.pause() }
            synchronizeTarget(nil,locked: true); return
        }
        guard var course = saved.active else {
            active = nil
            if waypoints.practiceNavigationLocked || waypoints.practiceNavigationSavePending { synchronizeTarget(waypoints.selectedId,locked: false) }
            return
        }
        if navigation.progress != nil { navigation.stop() }
        course.reconcile(availableIDs: Set(waypoints.waypoints.map(\.id)))
        if course != saved.active {
            if course.paused && (navigation.running || navigation.preparing) { navigation.pause(reason: course.pauseReason) }
            perform(.reconcile(saved.active!)); return
        }
        active = course
        if let result = course.result { finalize(course,result: result) }
        else {
            if course.paused && (navigation.running || navigation.preparing) { navigation.pause(reason: course.pauseReason) }
            synchronizeTarget(course.targetID,locked: true)
        }
    }
    private struct ChangedTargetOwner: Error {}
    private func validateTargetOwner(_ course: PracticeCourse?,loadError: String?) throws {
        guard saved.active == course, saved.loadError == loadError else { throw ChangedTargetOwner() }
        var checked = course; checked?.reconcile(availableIDs: Set(waypoints.waypoints.map(\.id)))
        guard checked == course else { throw ChangedTargetOwner() }
    }
    private func commitTarget(_ request: WaypointStore.PracticeSelection,validate: @MainActor () throws -> Void) async throws {
        while true {
            try Task.checkCancellation(); try validate()
            let snapshot = waypoints.restoreSnapshot(), factory = prepareTarget
            let worker = Task.detached(priority: .userInitiated) { try Task.checkCancellation(); return try factory(snapshot,request) }
            let prepared = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
            try Task.checkCancellation(); try validate()
            if try waypoints.publishPracticeSelection(prepared) { navigation.practiceTargetDidSave(); return }
        }
    }
    private func synchronizeTarget(_ id: String?,locked: Bool) {
        guard let request = waypoints.beginPracticeSelection(id,locked: locked) else { return }
        operation?.cancel(); generation = UUID(); let token = generation
        let owner = saved.active, loadError = saved.loadError
        working = true; blockedByStorage = false; error = nil
        navigation.waitForPracticeTarget()
        operation = Task {
            let grace = FinalizationGrace(); defer { grace.end() }
            do {
                try await commitTarget(request) {
                    guard self.generation == token else { throw CancellationError() }
                    try self.validateTargetOwner(owner,loadError: loadError)
                }
                guard generation == token else { return }
                working = false; operation = nil; blockedByStorage = false; error = saved.loadError
                reconcile()
                let latest = queuedFix; queuedFix = nil
                if foreground, let latest { receive(latest) }
            } catch {
                guard generation == token else { return }
                working = false; operation = nil; queuedFix = nil
                if error is ChangedTargetOwner { reconcile(); return }
                targetWriteFailed = true; blockedByStorage = true
                self.error = "Course target could not be saved. Retry saving the course. \(error.localizedDescription)"
                if navigation.running || navigation.preparing { navigation.pause(reason: "Course progress needs attention.") }
            }
        }
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
                    let prepared = try await prepare(snapshot,nil)
                    guard saved.active == course else { throw PracticeCourseError.invalid("The active course changed. Reopen it before finishing.") }
                    if try saved.publish(prepared) { break }
                }
                active = nil; summary = result; blockedByStorage = false; failedFinalizationRunID = nil
                if let request = waypoints.beginPracticeSelection(waypoints.selectedId,locked: false) {
                    navigation.waitForPracticeTarget()
                    try await commitTarget(request) {
                        guard self.saved.active == nil, !self.damaged else { throw ChangedTargetOwner() }
                    }
                }
            } catch {
                failedFinalizationRunID = course.runID; blockedByStorage = true
                if saved.active == nil { targetWriteFailed = true }
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
    private struct ChangedCheckpoint: LocalizedError {
        var errorDescription: String? { "Checkpoint changed before its score could be saved. Waiting for its current position." }
    }
    private func prepare(_ snapshot: PracticeCourseStore.SaveSnapshot,_ value: PracticeCourse?) async throws -> PracticeCourseStore.PreparedSave {
        let factory = prepareCourse
        let worker = Task.detached(priority: .userInitiated) { try Task.checkCancellation(); return try factory(snapshot,value) }
        return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
    }
    private func perform(_ request: Write) {
        operation?.cancel(); generation = UUID(); let token = generation
        working = true; pendingWrite = nil; targetWriteFailed = false; blockedByStorage = false; error = nil
        operation = Task {
            let grace = FinalizationGrace(); defer { grace.end() }
            var retained = request
            do {
                if case let .random(edit,name) = retained {
                    while true {
                        try Task.checkCancellation()
                        guard generation == token, saved.active == nil else { throw CancellationError() }
                        let snapshot = waypoints.restoreSnapshot(), factory = preparePoints
                        let worker = Task.detached(priority: .userInitiated) { try Task.checkCancellation(); return try factory(snapshot,edit) }
                        let prepared = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                        try Task.checkCancellation()
                        guard generation == token, saved.active == nil else { throw CancellationError() }
                        if try waypoints.publishPracticePoints(prepared) != nil { break }
                    }
                    // No suspension between acknowledgement and phase advance:
                    // a failed course save must never append the points again.
                    retained = .start(try PracticeCourse(name: name,waypointIDs: edit.ids,startedAt: millis))
                }
                while true {
                    try Task.checkCancellation()
                    guard generation == token else { throw CancellationError() }
                    let previous = saved.active
                    var next: PracticeCourse?
                    switch retained {
                    case .random: throw PracticeCourseError.invalid("Checkpoints must be saved before starting the course.")
                    case .start(let course):
                        guard previous == nil else { throw PracticeCourseError.invalid("Another course is already active.") }
                        next = course
                    case .reconcile(let expected):
                        guard previous == expected else { throw PracticeCourseError.invalid("The course changed. Reopen it before saving.") }
                        next = expected
                    case let .score(expected,scored,target):
                        guard previous == expected else { throw PracticeCourseError.invalid("The course changed before scoring.") }
                        guard waypoints.waypoints.contains(where: { $0.id == target.id && $0.lat == target.lat && $0.lon == target.lon }) else { throw ChangedCheckpoint() }
                        next = scored
                    case .end(let run):
                        guard previous?.runID == run, previous?.done == false else { throw PracticeCourseError.invalid("The course changed. Its completed result was kept.") }
                        next = nil
                    }
                    next?.reconcile(availableIDs: Set(waypoints.waypoints.map(\.id)))
                    let candidate = next
                    let prepared = try await prepare(saved.saveSnapshot(),candidate)
                    try Task.checkCancellation()
                    guard generation == token, saved.active == previous else { throw CancellationError() }
                    if case let .score(_,_,target) = retained {
                        guard waypoints.waypoints.contains(where: { $0.id == target.id && $0.lat == target.lat && $0.lon == target.lon }) else { throw ChangedCheckpoint() }
                    }
                    var current = candidate; current?.reconcile(availableIDs: Set(waypoints.waypoints.map(\.id)))
                    if current != candidate { continue }
                    guard try saved.publish(prepared) else { continue }
                    active = candidate
                    if case .start = retained { summary = nil; if navigation.progress != nil { navigation.stop() } }
                    if case .score = retained, foreground { scoreFeedback() }
                    working = false; operation = nil; reconcile()
                    let latest = queuedFix; queuedFix = nil
                    if foreground, let latest { receive(latest) }
                    return
                }
            } catch {
                guard generation == token else { return }
                working = false; operation = nil; queuedFix = nil
                if error is ChangedCheckpoint {
                    self.error = error.localizedDescription; reconcile()
                } else if !(error is CancellationError) {
                    pendingWrite = retained; blockedByStorage = true
                    if case .random = retained {
                        self.error = "Checkpoints could not be saved. Retry to keep the same proposed course, or cancel start. \(error.localizedDescription)"
                    } else if case .start(let course) = retained {
                        self.error = "Course start could not be saved. Checkpoints in \(course.name) are kept. Retry or cancel start. \(error.localizedDescription)"
                    } else { self.error = "Course save failed; progress is kept. Retry saving. \(error.localizedDescription)" }
                    if saved.active != nil && (navigation.running || navigation.preparing) { navigation.pause(reason: "Course progress needs attention.") }
                }
            }
        }
    }
    func retryWrite() {
        guard !working, !finalizing else { return }
        if let request = pendingWrite { perform(request) }
        else { targetWriteFailed = false; blockedByStorage = false; error = nil; reconcile() }
    }
    func cancelPendingStart() {
        guard !working, canCancelStart else { return }
        pendingWrite = nil; blockedByStorage = false; error = nil; reconcile()
    }
    func receive(_ fix: Fix?) {
        guard foreground else { return }
        if working {
            if let fix, NavigationFixPolicy.isUsable(lat: fix.lat,lon: fix.lon,accuracyMeters: fix.accuracyMeters,timestampUptime: fix.timestampUptime,nowUptime: uptime()),
               queuedFix.map({ fix.timestampUptime >= $0.timestampUptime }) ?? true { queuedFix = fix }
            return
        }
        guard !finalizing, !hasPendingWrite else { return }
        reconcile()
        guard !working, !blockedByStorage, let course = active, let id = course.targetID, let target = waypoints.waypoints.first(where: { $0.id == id }), let fix,
              NavigationFixPolicy.isUsable(lat: fix.lat,lon: fix.lon,accuracyMeters: fix.accuracyMeters,timestampUptime: fix.timestampUptime,nowUptime: uptime()) else { return }
        let nav = Geodesy.navInfo(fromLat: fix.lat,fromLon: fix.lon,toLat: target.lat,toLon: target.lon)
        guard PracticeCourse.canScore(distance: nav.distanceMeters,accuracy: fix.accuracyMeters) else { return }
        do {
            var next = course
            guard try next.markFound(runID: course.runID,checkpointID: id,now: millis) else { return }
            perform(.score(previous: course,next: next,target: target))
        } catch { self.error = error.localizedDescription }
    }
    func end(expectedRunID: String?) {
        guard let expectedRunID, saved.active?.runID == expectedRunID, saved.active?.done == false, !damaged, !finalizing else { return }
        queuedFix = nil; perform(.end(expectedRunID))
    }
    func resetDamaged() {
        guard !working, !finalizing else { return }
        do { try saved.preserveDamagedAndReset(); targetWriteFailed = false; pendingWrite = nil; blockedByStorage = false; error = nil; reconcile() }
        catch { self.error = error.localizedDescription }
    }
    func dismissSummary() { summary = nil }
    private var millis: Int64 { Int64(now().timeIntervalSince1970*1000) }
}
