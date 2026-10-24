import Combine
import Foundation

/// Local persistence for waypoints and folders.
///
/// File-backed JSON (not Core Data) so the on-disk shape stays close to the
/// backup document and a restore can merge by id without a schema migration.
/// Thread-safe enough for the main-actor UI: every mutation rewrites the file
/// atomically.
public final class WaypointStore: ObservableObject, @unchecked Sendable {

    @Published public private(set) var waypoints: [Waypoint] = []
    @Published public private(set) var folders: [FolderInfo] = []
    @Published public private(set) var selectedId: String?

    private let fileURL: URL
    private let lock = NSLock()

    private struct Snapshot: Codable {
        var waypoints: [Waypoint]
        var folders: [FolderInfo]
        var selectedId: String?
    }

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("waypoints-v1.json")
        load()
    }

    /// In-memory store for tests — never touches the filesystem.
    public static func inMemory(waypoints: [Waypoint] = [],
                                folders: [FolderInfo] = []) -> WaypointStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gf-wp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = WaypointStore(directory: tmp)
        store.lock.lock()
        store.waypoints = waypoints
        store.folders = Self.mergeFolderList(stored: folders, referenced: waypoints.map(\.folder))
        store.lock.unlock()
        store.persist()
        return store
    }

    // MARK: - Mutations

    @discardableResult
    public func add(_ draft: WaypointDraft) -> Waypoint {
        lock.lock(); defer { lock.unlock() }
        let folder = Folders.match(known: knownNamesLocked(), raw: draft.folder)
        ensureFolderLocked(folder, visible: nil)
        let wp = Waypoint(
            name: draft.name, lat: draft.lat, lon: draft.lon,
            folder: folder, symbol: draft.symbol, affiliation: draft.affiliation,
            echelon: draft.echelon, designation: draft.designation,
            kind: draft.kind, rotation: draft.rotation,
            metadata: draft.metadata ?? WaypointMetadata()
        )
        waypoints.append(wp)
        refreshFoldersLocked()
        persistLocked()
        return wp
    }

    public func update(id: String, draft: WaypointDraft) {
        lock.lock(); defer { lock.unlock() }
        guard let idx = waypoints.firstIndex(where: { $0.id == id }) else { return }
        let folder = Folders.match(known: knownNamesLocked(), raw: draft.folder)
        ensureFolderLocked(folder, visible: nil)
        var wp = waypoints[idx]
        wp.name = draft.name
        wp.lat = draft.lat
        wp.lon = draft.lon
        wp.folder = folder
        wp.symbol = draft.symbol
        wp.affiliation = draft.affiliation
        wp.echelon = draft.echelon
        wp.designation = draft.designation
        wp.kind = draft.kind
        wp.rotation = draft.rotation
        if let meta = draft.metadata { wp.metadata = meta }
        waypoints[idx] = wp
        refreshFoldersLocked()
        persistLocked()
    }

    public func delete(ids: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        waypoints.removeAll { ids.contains($0.id) }
        if let sel = selectedId, ids.contains(sel) { selectedId = nil }
        refreshFoldersLocked()
        persistLocked()
    }

    public func setFavorite(id: String,favorite: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        var next = waypoints; next[index].favorite = favorite
        try publishLibraryLocked(next,folders: folders,selection: selectedId)
    }

    public func setVisible(id: String, visible: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard let idx = waypoints.firstIndex(where: { $0.id == id }) else { return }
        waypoints[idx].visible = visible
        persistLocked()
    }

    /// Library batches publish only after their complete snapshot is durable.
    public func applyLibraryBatch(ids: Set<String>,action: LibraryBatchAction) throws {
        guard !ids.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var next = waypoints
        switch action {
        case .swapVisibility: for i in next.indices where ids.contains(next[i].id) { next[i].visible.toggle() }
        case .delete: next.removeAll { ids.contains($0.id) }
        }
        let selection = next.contains { $0.id == selectedId } ? selectedId : nil
        try publishLibraryLocked(next,folders: folders,selection: selection)
    }

    @discardableResult
    public func createLibraryFolder(_ raw: String) throws -> String {
        lock.lock(); defer { lock.unlock() }
        let name = Folders.match(known: knownNamesLocked(),raw: raw)
        var nextFolders = folders
        if !nextFolders.contains(where: { $0.name == name }) { nextFolders.append(.init(name: name)) }
        try publishLibraryLocked(waypoints,folders: nextFolders,selection: selectedId)
        return name
    }

    public func setLibraryFolderVisible(_ raw: String,visible: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        let name = Folders.match(known: knownNamesLocked(),raw: raw)
        var next = folders
        if let i = next.firstIndex(where: { $0.name == name }) { next[i].visible = visible }
        else { next.append(.init(name: name,visible: visible)) }
        try publishLibraryLocked(waypoints,folders: next,selection: selectedId)
    }

    /// Renaming onto an existing folder merges records; either visible source
    /// makes the merged folder visible, as in Android's mergeFolder.
    @discardableResult
    public func renameLibraryFolder(from: String,to raw: String) throws -> String {
        guard from.caseInsensitiveCompare(Folders.defaultFolder) != .orderedSame,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return from }
        lock.lock(); defer { lock.unlock() }
        let target = Folders.match(known: knownNamesLocked().filter { $0.caseInsensitiveCompare(from) != .orderedSame },raw: raw)
        let visible = folders.first { $0.name.caseInsensitiveCompare(from) == .orderedSame }?.visible ?? true
        var nextFolders = folders.filter { $0.name.caseInsensitiveCompare(from) != .orderedSame }
        if let i = nextFolders.firstIndex(where: { $0.name == target }) { nextFolders[i].visible = nextFolders[i].visible || visible }
        else { nextFolders.append(.init(name: target,visible: visible)) }
        let next = waypoints.map { point -> Waypoint in
            var point = point
            if point.folder.caseInsensitiveCompare(from) == .orderedSame { point.folder = target }
            return point
        }
        try publishLibraryLocked(next,folders: nextFolders,selection: selectedId)
        return target
    }

    public func removeLibraryFolder(_ name: String,deleteContents: Bool) throws {
        guard name.caseInsensitiveCompare(Folders.defaultFolder) != .orderedSame else { return }
        lock.lock(); defer { lock.unlock() }
        let next = waypoints.compactMap { point -> Waypoint? in
            guard point.folder.caseInsensitiveCompare(name) == .orderedSame else { return point }
            if deleteContents { return nil }
            var moved = point; moved.folder = Folders.defaultFolder; return moved
        }
        let selection = next.contains { $0.id == selectedId } ? selectedId : nil
        try publishLibraryLocked(next,folders: folders.filter { $0.name.caseInsensitiveCompare(name) != .orderedSame },selection: selection)
    }

    private func publishLibraryLocked(_ next: [Waypoint],folders: [FolderInfo],selection: String?) throws {
        let nextFolders = Self.mergeFolderList(stored: folders,referenced: next.map(\.folder))
        let data = try JSONEncoder().encode(Snapshot(waypoints: next,folders: nextFolders,selectedId: selection))
        try data.write(to: fileURL,options: .atomic)
        waypoints = next; self.folders = nextFolders; selectedId = selection
    }

    @Published public private(set) var practiceNavigationLocked = false
    private var practiceSelectionNeedsSave = false
    private var practiceTargetID: String?

    /// Applies to every selection entry point, including map, imports and library.
    public func setPracticeNavigationTarget(_ id: String?,locked: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        let target = id.flatMap { candidate in waypoints.contains { $0.id == candidate } ? candidate : nil }
        guard practiceSelectionNeedsSave || practiceNavigationLocked != locked || practiceTargetID != target || selectedId != target else { return }
        // The durable course, not this preference file, owns the lock. Keep it
        // fail-closed even if selection persistence is temporarily unavailable.
        practiceTargetID = target; practiceNavigationLocked = locked
        practiceSelectionNeedsSave = true
        do { try publishLibraryLocked(waypoints,folders: folders,selection: target); practiceSelectionNeedsSave = false }
        catch { selectedId = target; throw error }
    }

    public func addPracticePoints(folder raw: String,points: [GeoPoint]) throws -> [Waypoint] {
        lock.lock(); defer { lock.unlock() }
        guard points.count >= 2, waypoints.count + points.count <= 10_000,
              points.allSatisfy({ TrackCodec.validCoordinates($0.lat,$0.lon) }) else { throw PracticeCourseError.invalid("Invalid checkpoints or waypoint library limit reached.") }
        let folder = Folders.match(known: knownNamesLocked(),raw: raw)
        let added = points.enumerated().map { Waypoint(name: "CP \($0.offset+1)",lat: $0.element.lat,lon: $0.element.lon,folder: folder,symbol: "target") }
        try publishLibraryLocked(waypoints+added,folders: folders,selection: selectedId)
        return added
    }

    public func select(_ id: String?) {
        lock.lock(); defer { lock.unlock() }
        selectedId = practiceNavigationLocked ? practiceTargetID.flatMap { target in waypoints.contains { $0.id == target } ? target : nil } : id
        persistLocked()
    }

    @discardableResult
    public func addFolder(_ name: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let stored = Folders.match(known: knownNamesLocked(), raw: name)
        ensureFolderLocked(stored, visible: nil)
        refreshFoldersLocked()
        persistLocked()
        return stored
    }

    public func setFolderVisible(_ name: String, visible: Bool) {
        lock.lock(); defer { lock.unlock() }
        ensureFolderLocked(name, visible: visible)
        refreshFoldersLocked()
        persistLocked()
    }

    /// Additive, id-keyed merge used by backup restore. Returns count added.
    @discardableResult
    public func merge(waypoints incoming: [Waypoint], folders incomingFolders: [FolderInfo]) -> Int {
        (try? restore(waypoints: incoming, folders: incomingFolders)) ?? 0
    }

    /// Existing records and route vertices win. Publish only after the complete
    /// merged snapshot has been written, so a failed restore remains retryable.
    @discardableResult
    public func restore(waypoints incoming: [Waypoint], folders incomingFolders: [FolderInfo]) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        var ids = Set(waypoints.map(\.id))
        var vertices = Set(waypoints.compactMap(\.routeVertexKey))
        var next = waypoints
        for var waypoint in incoming {
            guard ids.insert(waypoint.id).inserted else { continue }
            if let vertex = waypoint.routeVertexKey, !vertices.insert(vertex).inserted { continue }
            waypoint.folder = Folders.match(known: folders.map(\.name) + incomingFolders.map(\.name), raw: waypoint.folder)
            next.append(waypoint)
        }
        var mergedFolders = folders
        for var folder in incomingFolders {
            folder.name = Folders.canonical(folder.name)
            if !mergedFolders.contains(where: { $0.name.caseInsensitiveCompare(folder.name) == .orderedSame }) { mergedFolders.append(folder) }
        }
        let nextFolders = Self.mergeFolderList(stored: mergedFolders, referenced: next.map(\.folder))
        let snapshot = Snapshot(waypoints: next, folders: nextFolders, selectedId: selectedId)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        let added = next.count - waypoints.count
        waypoints = next; folders = nextFolders
        return added
    }

    /// Port of Android replaceRouteWaypoints: owner ID/index establish identity;
    /// names never do. Duplicate legacy owners are retained as standalone points.
    public func replaceRouteWaypoints(routeID: String, name: String, points: [GeoPoint], folder: String,
                                      now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws {
        guard !routeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              points.allSatisfy({ TrackCodec.validCoordinates($0.lat, $0.lon) }) else { throw BackupError.notABackup("Invalid route") }
        lock.lock(); defer { lock.unlock() }
        let storedFolder = Folders.match(known: knownNamesLocked(), raw: folder)
        var owners: [Int: Waypoint] = [:]
        for waypoint in waypoints where waypoint.sourceRouteId == routeID {
            if let index = waypoint.sourceRoutePointIndex, index >= 0,
               owners[index] == nil || waypoint.id == selectedId { owners[index] = waypoint }
        }
        let generated = points.enumerated().map { index, point -> Waypoint in
            var waypoint = owners[index] ?? Waypoint(name: "", lat: point.lat, lon: point.lon, createdAt: now)
            waypoint.name = "\(name) WP \(index + 1)"
            waypoint.lat = point.lat; waypoint.lon = point.lon; waypoint.folder = storedFolder
            waypoint.sourceRouteId = routeID; waypoint.sourceRoutePointIndex = index
            return waypoint
        }
        let retained = waypoints.compactMap { waypoint -> Waypoint? in
            guard waypoint.sourceRouteId == routeID else { return waypoint }
            if let index = waypoint.sourceRoutePointIndex, owners[index]?.id == waypoint.id { return nil }
            var standalone = waypoint
            standalone.sourceRouteId = nil; standalone.sourceRoutePointIndex = nil
            return standalone
        }
        let next = retained + generated
        let selection = next.contains { $0.id == selectedId } ? selectedId : nil
        let nextFolders = Self.mergeFolderList(stored: folders, referenced: next.map(\.folder))
        try JSONEncoder().encode(Snapshot(waypoints: next, folders: nextFolders, selectedId: selection)).write(to: fileURL, options: .atomic)
        waypoints = next; folders = nextFolders; selectedId = selection
    }

    public func replaceAll(waypoints: [Waypoint], folders: [FolderInfo]) {
        lock.lock(); defer { lock.unlock() }
        self.waypoints = waypoints.map {
            var w = $0
            w.folder = Folders.canonical(w.folder)
            return w
        }
        self.folders = Self.mergeFolderList(stored: folders, referenced: self.waypoints.map(\.folder))
        persistLocked()
    }

    // MARK: - Persistence

    private func load() {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            folders = [FolderInfo(name: Folders.defaultFolder)]
            return
        }
        waypoints = snap.waypoints.map {
            var w = $0
            w.folder = Folders.canonical(w.folder)
            return w
        }
        folders = Self.mergeFolderList(stored: snap.folders, referenced: waypoints.map(\.folder))
        selectedId = snap.selectedId
    }

    private func persist() {
        lock.lock(); defer { lock.unlock() }
        persistLocked()
    }

    private func persistLocked() {
        let snap = Snapshot(waypoints: waypoints, folders: folders, selectedId: selectedId)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func knownNamesLocked() -> [String] {
        (folders.map(\.name) + waypoints.map(\.folder) + [Folders.defaultFolder]).uniqued()
    }

    private func ensureFolderLocked(_ name: String, visible: Bool?) {
        let clean = Folders.canonical(name)
        if let idx = folders.firstIndex(where: {
            $0.name.caseInsensitiveCompare(clean) == .orderedSame
        }) {
            if let visible { folders[idx].visible = visible }
        } else {
            folders.append(FolderInfo(name: clean, visible: visible ?? true))
        }
    }

    private func refreshFoldersLocked() {
        folders = Self.mergeFolderList(stored: folders, referenced: waypoints.map(\.folder))
    }

    private static func mergeFolderList(stored: [FolderInfo], referenced: [String]) -> [FolderInfo] {
        let names = (stored.map(\.name) + referenced + [Folders.defaultFolder]).uniqued()
        return names.map { n in
            stored.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                ?? FolderInfo(name: n)
        }
        .sorted {
            if $0.name == Folders.defaultFolder { return true }
            if $1.name == Folders.defaultFolder { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in self {
            let key = s.lowercased()
            if seen.insert(key).inserted { out.append(s) }
        }
        return out
    }
}

private struct RouteVertexKey: Hashable {
    let routeID: String
    let index: Int
}

private extension Waypoint {
    var routeVertexKey: RouteVertexKey? {
        guard let routeID = sourceRouteId, !routeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = sourceRoutePointIndex, index >= 0 else { return nil }
        return RouteVertexKey(routeID: routeID, index: index)
    }
}
