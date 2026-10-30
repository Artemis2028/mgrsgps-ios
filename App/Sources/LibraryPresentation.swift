import Combine
import Foundation
import GridFixCore

@MainActor
final class LibraryPresentation: ObservableObject {
    struct Request: Sendable {
        let points: [Waypoint]
        let folders: [FolderInfo]
        let graphics: [Backup.Graphic]
        let tracks: [Backup.TrackMeta]
        let query: String
        let folder: String?
        let sort: WaypointSort
        let origin: GeoPoint?
        let locale: Locale
        let cachedIndex: LibraryListing.Index?
        let indexIsCurrent: Bool
        let cachedCatalog: LibraryListing.Catalog?
    }
    struct Work: Sendable {
        let catalog: LibraryListing.Catalog
        let snapshot: LibraryListing.Snapshot
    }
    typealias Compute = @Sendable (Request) throws -> Work
    @Published private(set) var snapshot: LibraryListing.Snapshot?
    @Published private(set) var updating = false
    @Published private(set) var error: String?
    @Published private(set) var query = ""
    @Published private(set) var folder: String?
    @Published private(set) var sort: WaypointSort = .distance
    private(set) var acceptedSourceRevision: UInt64 = 0
    private var points: [Waypoint] = [], folders: [FolderInfo] = []
    private var graphics: [Backup.Graphic] = [], tracks: [Backup.TrackMeta] = []
    private var origin: GeoPoint?, locale = Locale.current
    private var active = false, pending = false
    private var generation: UInt64 = 0, sourceRevision: UInt64 = 0, pointRevision: UInt64 = 0
    private var acceptedGeneration: UInt64?
    private var cachedIndex: LibraryListing.Index?, cachedPointRevision: UInt64?
    private var cachedCatalog: LibraryListing.Catalog?, cachedSourceRevision: UInt64?
    private var runID = UUID()
    private var task: Task<Void,Never>?
    private var worker: Task<Work,Error>?
    private let compute: Compute

    init(compute: @escaping Compute = { try LibraryPresentation.compute($0) }) { self.compute = compute }
    var isReady: Bool { active && !updating && error == nil && snapshot != nil && acceptedGeneration == generation }

    func setWaypoints(_ value: [Waypoint]) {
        points = value; pointRevision &+= 1; sourceRevision &+= 1
        worker?.cancel(); request(structural: true)
    }
    func setFolders(_ value: [FolderInfo]) { folders = value; sourceRevision &+= 1; request(structural: true) }
    func setField(graphics: [Backup.Graphic],tracks: [Backup.TrackMeta]) {
        self.graphics = graphics; self.tracks = tracks; sourceRevision &+= 1; request(structural: true)
    }
    func setQuery(_ value: String) {
        let value = String(value.prefix(60)); guard query != value else { return }
        query = value; request(structural: true)
    }
    func setFolder(_ value: String?) { guard folder != value else { return }; folder = value; request(structural: true) }
    func setSort(_ value: WaypointSort) { guard sort != value else { return }; sort = value; request(structural: true) }
    func setOrigin(_ value: GeoPoint?) {
        guard origin?.lat != value?.lat || origin?.lon != value?.lon else { return }
        let eligibilityChanged = (origin == nil) != (value == nil)
        origin = value
        if sort == .distance { request(structural: eligibilityChanged) }
    }
    func refreshLocale(_ value: Locale) { locale = value; sourceRevision &+= 1; request(structural: true) }
    func retry() { request(structural: true) }
    func activate() { guard !active else { return }; active = true; request(structural: true) }
    func deactivate() {
        active = false; generation &+= 1; runID = UUID()
        worker?.cancel(); task?.cancel(); worker = nil; task = nil; updating = false; pending = true
    }

    private func request(structural: Bool) {
        if structural { generation &+= 1; if active { updating = true } }
        pending = true; error = nil
        guard active,task == nil else { return }
        let token = UUID(); runID = token
        task = Task {
            defer { if runID == token { task = nil; worker = nil } }
            while active && pending && runID == token && !Task.isCancelled {
                pending = false
                let gen = generation, source = sourceRevision, pointVersion = pointRevision
                let request = Request(points: points,folders: folders,graphics: graphics,tracks: tracks,query: query,folder: folder,sort: sort,origin: origin,locale: locale,cachedIndex: cachedIndex,indexIsCurrent: cachedPointRevision == pointVersion,cachedCatalog: cachedSourceRevision == source ? cachedCatalog : nil)
                let compute = compute
                let job = Task.detached(priority: .userInitiated) { try compute(request) }
                worker = job
                do {
                    let result = try await job.value
                    guard active,runID == token,!Task.isCancelled else { return }
                    if pointVersion == pointRevision { cachedIndex = result.catalog.index; cachedPointRevision = pointVersion }
                    if source == sourceRevision { cachedCatalog = result.catalog; cachedSourceRevision = source }
                    if gen == generation {
                        acceptedGeneration = gen; acceptedSourceRevision = source
                        snapshot = result.snapshot
                        // A subscriber may reconcile a removed folder and
                        // synchronously request another generation here.
                        if gen == generation { updating = false; error = nil }
                    }
                } catch {
                    guard active,runID == token,!Task.isCancelled else { return }
                    if error is CancellationError && (pending || gen != generation) { continue }
                    if gen == generation { self.error = "Could not update library: \(error.localizedDescription)"; updating = false }
                }
                if runID == token { worker = nil }
            }
        }
    }

    nonisolated static func compute(_ request: Request) throws -> Work {
        try Task.checkCancellation()
        let catalog: LibraryListing.Catalog
        if let cached = request.cachedCatalog { catalog = cached }
        else {
            let index: LibraryListing.Index
            if request.indexIsCurrent,let cached = request.cachedIndex { index = cached }
            else { index = try LibraryListing.Index(request.points,reusing: request.cachedIndex) }
            catalog = try LibraryListing.Catalog(index: index,folders: request.folders,graphics: request.graphics,tracks: request.tracks,locale: request.locale)
        }
        return try Work(catalog: catalog,snapshot: catalog.snapshot(folder: request.folder,origin: request.origin,query: request.query,sort: request.sort))
    }
}
