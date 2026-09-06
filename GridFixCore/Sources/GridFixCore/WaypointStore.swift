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

    public func setVisible(id: String, visible: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard let idx = waypoints.firstIndex(where: { $0.id == id }) else { return }
        waypoints[idx].visible = visible
        persistLocked()
    }

    public func select(_ id: String?) {
        lock.lock(); defer { lock.unlock() }
        selectedId = id
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
        lock.lock(); defer { lock.unlock() }
        let existing = Set(waypoints.map(\.id))
        var added = 0
        for var f in incomingFolders {
            f.name = Folders.canonical(f.name)
            if let idx = folders.firstIndex(where: {
                $0.name.caseInsensitiveCompare(f.name) == .orderedSame
            }) {
                // Keep the device's own visibility.
                _ = idx
            } else {
                folders.append(f)
            }
        }
        for var w in incoming {
            w.folder = Folders.match(known: knownNamesLocked(), raw: w.folder)
            if existing.contains(w.id) { continue }
            waypoints.append(w)
            ensureFolderLocked(w.folder, visible: nil)
            added += 1
        }
        refreshFoldersLocked()
        persistLocked()
        return added
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
