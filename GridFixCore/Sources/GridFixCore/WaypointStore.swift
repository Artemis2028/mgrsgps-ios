import Combine
import CryptoKit
import Foundation

/// Local persistence for waypoints and folders.
///
/// File-backed JSON (not Core Data) so the on-disk shape stays close to the
/// backup document and a restore can merge by id without a schema migration.
/// Editor and restore workflows prepare immutable snapshots on workers, then
/// atomically publish on the UI executor. Legacy mutation helpers remain for
/// setup and the remaining non-editor workflows.
public final class WaypointStore: ObservableObject, @unchecked Sendable {

    @Published public private(set) var waypoints: [Waypoint] = [] { didSet { revision &+= 1 } }
    @Published public private(set) var folders: [FolderInfo] = [] { didSet { revision &+= 1 } }
    @Published public private(set) var loadError: String?
    @Published public private(set) var selectedId: String? { didSet { revision &+= 1 } }

    private let fileURL: URL
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private let identity = UUID()

    fileprivate struct Snapshot: Codable, Sendable {
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
        case .hide: for i in next.indices where ids.contains(next[i].id) { next[i].visible = false }
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
        if let loadError { throw BackupError.notABackup(loadError) }
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
        if let loadError { throw BackupError.notABackup(loadError) }
        let base = Snapshot(waypoints: waypoints,folders: folders,selectedId: selectedId)
        let (next,added) = Self.merged(base,waypoints: incoming,folders: incomingFolders)
        try JSONEncoder().encode(next).write(to: fileURL,options: .atomic)
        waypoints = next.waypoints; folders = next.folders
        return added
    }

    private static func merged(_ base: Snapshot,waypoints incoming: [Waypoint],folders incomingFolders: [FolderInfo]) -> (Snapshot,Int) {
        var ids = Set(base.waypoints.map(\.id))
        var vertices = Set(base.waypoints.compactMap(\.routeVertexKey))
        var next = base.waypoints
        let knownFolders = base.folders.map(\.name) + incomingFolders.map(\.name)
        for var waypoint in incoming {
            guard ids.insert(waypoint.id).inserted else { continue }
            if let vertex = waypoint.routeVertexKey, !vertices.insert(vertex).inserted { continue }
            waypoint.folder = Folders.match(known: knownFolders,raw: waypoint.folder)
            next.append(waypoint)
        }
        var mergedFolders = base.folders
        for var folder in incomingFolders {
            folder.name = Folders.canonical(folder.name)
            if !mergedFolders.contains(where: { $0.name.caseInsensitiveCompare(folder.name) == .orderedSame }) { mergedFolders.append(folder) }
        }
        let nextFolders = Self.mergeFolderList(stored: mergedFolders, referenced: next.map(\.folder))
        return (Snapshot(waypoints: next,folders: nextFolders,selectedId: base.selectedId),next.count-base.waypoints.count)
    }

    public enum LibraryEdit: Sendable {
        case favorite(String,Bool)
        case folderVisibility(String,Bool)
        case createFolder(String)
        case renameFolder(String,String)
        case removeFolder(String,Bool)
    }

    public struct PreparedLibraryEdit: Sendable {
        fileprivate let batch: PreparedBatch
        public let folder: String?
    }

    public func publishLibraryEdit(_ prepared: PreparedLibraryEdit) throws -> Bool {
        try publishBatch(prepared.batch)
    }

    public struct RestoreSnapshot: Sendable {
        fileprivate let base: Snapshot
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let destination: URL
        fileprivate let loadError: String?
        fileprivate let allowsDefaultSelection: Bool

        public func prepareLibrary(_ edit: LibraryEdit) throws -> PreparedLibraryEdit {
            if let loadError { throw BackupError.notABackup(loadError) }
            var next = base
            var folder: String?
            let names = base.folders.map(\.name) + base.waypoints.map(\.folder)
            switch edit {
            case let .favorite(id,value):
                guard let index = next.waypoints.firstIndex(where: { $0.id == id }) else { throw EditFailure.removed }
                next.waypoints[index].favorite = value
            case let .folderVisibility(raw,visible):
                let name = Folders.match(known: names,raw: raw); folder = name
                if let index = next.folders.firstIndex(where: { $0.name == name }) { next.folders[index].visible = visible }
                else { next.folders.append(.init(name: name,visible: visible)) }
            case .createFolder(let raw):
                let name = Folders.match(known: names,raw: raw); folder = name
                if !next.folders.contains(where: { $0.name == name }) { next.folders.append(.init(name: name)) }
            case let .renameFolder(from,raw):
                guard from.caseInsensitiveCompare(Folders.defaultFolder) != .orderedSame,
                      !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EditFailure.invalid }
                let target = Folders.match(known: names.filter { $0.caseInsensitiveCompare(from) != .orderedSame },raw: raw)
                folder = target
                let visible = next.folders.first { $0.name.caseInsensitiveCompare(from) == .orderedSame }?.visible ?? true
                next.folders.removeAll { $0.name.caseInsensitiveCompare(from) == .orderedSame }
                if let index = next.folders.firstIndex(where: { $0.name == target }) { next.folders[index].visible = next.folders[index].visible || visible }
                else { next.folders.append(.init(name: target,visible: visible)) }
                for index in next.waypoints.indices where next.waypoints[index].folder.caseInsensitiveCompare(from) == .orderedSame { next.waypoints[index].folder = target }
            case let .removeFolder(name,deleteContents):
                guard name.caseInsensitiveCompare(Folders.defaultFolder) != .orderedSame else { throw EditFailure.invalid }
                if deleteContents { next.waypoints.removeAll { $0.folder.caseInsensitiveCompare(name) == .orderedSame } }
                else { for index in next.waypoints.indices where next.waypoints[index].folder.caseInsensitiveCompare(name) == .orderedSame { next.waypoints[index].folder = Folders.defaultFolder } }
                next.folders.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                if !next.waypoints.contains(where: { $0.id == next.selectedId }) { next.selectedId = nil }
            }
            next.folders = WaypointStore.mergeFolderList(stored: next.folders,referenced: next.waypoints.map(\.folder))
            let file = try PreparedAtomicFile(data: JSONEncoder().encode(next),destination: destination)
            return .init(batch: .init(snapshot: next,revision: revision,identity: identity,file: file),folder: folder)
        }

        public func prepareBatch(ids: Set<String>,action: LibraryBatchAction) throws -> PreparedBatch {
            if let loadError { throw BackupError.notABackup(loadError) }
            var next = base
            switch action {
            case .hide: for i in next.waypoints.indices where ids.contains(next.waypoints[i].id) { next.waypoints[i].visible = false }
            case .swapVisibility: for i in next.waypoints.indices where ids.contains(next.waypoints[i].id) { next.waypoints[i].visible.toggle() }
            case .delete: next.waypoints.removeAll { ids.contains($0.id) }
            }
            if !next.waypoints.contains(where: { $0.id == next.selectedId }) { next.selectedId = nil }
            let file = try PreparedAtomicFile(data: JSONEncoder().encode(next),destination: destination)
            return .init(snapshot: next,revision: revision,identity: identity,file: file)
        }

        public func prepare(edit: Edit) throws -> PreparedEdit {
            if let loadError { throw BackupError.notABackup(loadError) }
            var next = base
            let draft: WaypointDraft
            switch edit { case .create(_,_,let value), .update(_,let value): draft = value }
            guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  TrackCodec.validCoordinates(draft.lat,draft.lon), draft.rotation.isFinite else { throw EditFailure.invalid }
            let names = base.folders.map(\.name) + base.waypoints.map(\.folder)
            let folder = Folders.match(known: names,raw: draft.folder)
            let saved: Waypoint
            switch edit {
            case let .create(id,createdAt,draft):
                guard !id.isEmpty else { throw EditFailure.invalid }
                if let existing = base.waypoints.first(where: { $0.id == id }) {
                    return .init(snapshot: base,waypoint: existing,revision: revision,identity: identity,file: nil)
                }
                saved = Waypoint(id: id,name: draft.name,lat: draft.lat,lon: draft.lon,createdAt: createdAt,folder: folder,
                                 symbol: draft.symbol,affiliation: draft.affiliation,echelon: draft.echelon,designation: draft.designation,
                                 kind: draft.kind,rotation: draft.rotation,metadata: draft.metadata ?? .init())
                next.waypoints.append(saved)
                // Android add selects its new point only if no target exists.
                // A running practice course retains its explicit target lock.
                if next.selectedId == nil, allowsDefaultSelection { next.selectedId = saved.id }
            case let .update(original,draft):
                guard let index = next.waypoints.firstIndex(where: { $0.id == original.id }) else { throw EditFailure.removed }
                var value = next.waypoints[index]
                func changed(_ a: String,_ b: String) -> Bool { !a.utf8.elementsEqual(b.utf8) }
                if changed(original.name,draft.name) { value.name = draft.name }
                if original.lat != draft.lat || original.lon != draft.lon { value.lat = draft.lat; value.lon = draft.lon }
                if changed(original.folder,draft.folder) { value.folder = folder }
                if changed(original.symbol,draft.symbol) { value.symbol = draft.symbol }
                if changed(original.affiliation,draft.affiliation) { value.affiliation = draft.affiliation }
                if changed(original.echelon,draft.echelon) { value.echelon = draft.echelon }
                if changed(original.designation,draft.designation) { value.designation = draft.designation }
                if changed(original.kind,draft.kind) { value.kind = draft.kind }
                if original.rotation != draft.rotation { value.rotation = draft.rotation }
                if let metadata = draft.metadata {
                    if metadata.color != original.metadata.color { value.metadata.color = metadata.color }
                    if metadata.milgpsSymbolCode != original.metadata.milgpsSymbolCode { value.metadata.milgpsSymbolCode = metadata.milgpsSymbolCode }
                    if metadata.elevationMeters != original.metadata.elevationMeters { value.metadata.elevationMeters = metadata.elevationMeters }
                    if metadata.timestampMillis != original.metadata.timestampMillis { value.metadata.timestampMillis = metadata.timestampMillis }
                }
                next.waypoints[index] = value; saved = value
            }
            next.folders = WaypointStore.mergeFolderList(stored: base.folders,referenced: next.waypoints.map(\.folder))
            let file = try PreparedAtomicFile(data: JSONEncoder().encode(next),destination: destination)
            return .init(snapshot: next,waypoint: saved,revision: revision,identity: identity,file: file)
        }

        public func prepare(waypoints: [Waypoint],folders: [FolderInfo]) throws -> PreparedRestore {
            if let loadError { throw BackupError.notABackup(loadError) }
            let (next,count) = WaypointStore.merged(base,waypoints: waypoints,folders: folders)
            let file = try PreparedAtomicFile(data: JSONEncoder().encode(next),destination: destination)
            return PreparedRestore(snapshot: next,count: count,revision: revision,identity: identity,file: file)
        }
    }

    public struct PreparedRestore: Sendable {
        fileprivate let snapshot: Snapshot
        fileprivate let count: Int
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedAtomicFile
    }

    public struct PreparedBatch: Sendable {
        fileprivate let snapshot: Snapshot
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedAtomicFile
    }
    public func publishBatch(_ prepared: PreparedBatch) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else { throw EditFailure.wrongStore }
        guard prepared.revision == revision else { prepared.file.discard(); return false }
        try prepared.file.publish()
        waypoints = prepared.snapshot.waypoints; folders = prepared.snapshot.folders; selectedId = prepared.snapshot.selectedId
        return true
    }

    public func restoreSnapshot() -> RestoreSnapshot {
        lock.lock(); defer { lock.unlock() }
        return RestoreSnapshot(base: Snapshot(waypoints: waypoints,folders: folders,selectedId: selectedId),revision: revision,identity: identity,destination: fileURL,loadError: loadError,allowsDefaultSelection: !practiceNavigationLocked)
    }

    /// Publish on the UI executor. Nil requests a fresh merge after an edit.
    public func publishRestore(_ prepared: PreparedRestore) throws -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else {
            throw BackupError.notABackup("Prepared waypoint restore belongs to a different store")
        }
        guard prepared.revision == revision else { prepared.file.discard(); return nil }
        try prepared.file.publish()
        waypoints = prepared.snapshot.waypoints; folders = prepared.snapshot.folders
        return prepared.count
    }

    /// Immutable editor intent. A create ID/time belongs to the presentation,
    /// so rebasing or retrying a failed write cannot create duplicate points.
    public enum Edit: Sendable {
        case create(id: String,createdAt: Int64,draft: WaypointDraft)
        case update(original: Waypoint,draft: WaypointDraft)
    }
    public struct PreparedEdit: Sendable {
        fileprivate let snapshot: Snapshot
        fileprivate let waypoint: Waypoint
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedAtomicFile?
    }
    public enum EditFailure: LocalizedError {
        case invalid,removed,wrongStore
        public var errorDescription: String? {
            switch self {
            case .invalid: return "Enter a name and valid coordinates before saving."
            case .removed: return "This waypoint is no longer saved."
            case .wrongStore: return "This waypoint save belongs to a different library."
            }
        }
    }
    public func publishEdit(_ prepared: PreparedEdit) throws -> Waypoint? {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else { throw EditFailure.wrongStore }
        guard prepared.revision == revision else { prepared.file?.discard(); return nil }
        if let file = prepared.file {
            try file.publish()
            waypoints = prepared.snapshot.waypoints; folders = prepared.snapshot.folders; selectedId = prepared.snapshot.selectedId
        }
        return prepared.waypoint
    }

    /// Port of Android replaceRouteWaypoints: owner ID/index establish identity;
    /// names never do. Duplicate legacy owners are retained as standalone points.
    public func replaceRouteWaypoints(routeID: String, name: String, points: [GeoPoint], folder: String,
                                      now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws {
        if let loadError { throw BackupError.notABackup(loadError) }
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

    /// Recovery preparation runs on a worker. Publication checks both the
    /// store revision and the original file before replacing anything.
    public struct RecoverySnapshot: Sendable {
        fileprivate let destination: URL
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        public func prepareReload() throws -> PreparedReload {
            let stamp = try RecoveryStamp.read(destination)
            let value = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: destination, options: .mappedIfSafe))
            guard try RecoveryStamp.read(destination) == stamp else { throw RecoveryFailure.changed }
            let points = value.waypoints.map { point -> Waypoint in var point = point; point.folder = Folders.canonical(point.folder); return point }
            let next = Snapshot(waypoints: points, folders: WaypointStore.mergeFolderList(stored: value.folders, referenced: points.map(\.folder)), selectedId: value.selectedId)
            return .init(snapshot: next, stamp: stamp, revision: revision, identity: identity)
        }
        public func prepareFreshLibrary() throws -> PreparedRecovery {
            let archive = try makeArchive()
            let next = Snapshot(waypoints: [], folders: [.init(name: Folders.defaultFolder)], selectedId: nil)
            let file = try PreparedAtomicFile(data: JSONEncoder().encode(next), destination: destination)
            return .init(snapshot: next, original: archive.original, stamp: archive.stamp, archiveStamp: archive.archiveStamp, revision: revision, identity: identity, file: file)
        }
        public func preserveOriginal() throws -> URL { try makeArchive().original }
        private func makeArchive() throws -> (original: URL, stamp: RecoveryStamp, archiveStamp: RecoveryStamp) {
            try Task.checkCancellation()
            let stamp = try RecoveryStamp.read(destination)
            let directory = destination.deletingLastPathComponent().appendingPathComponent("WaypointRecovery", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let original = directory.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
            guard FileManager.default.createFile(atPath: original.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw RecoveryFailure.archive }
            var complete = false
            defer { if !complete { try? FileManager.default.removeItem(at: original) } }
            let input = try FileHandle(forReadingFrom: destination), output = try FileHandle(forWritingTo: original)
            defer { try? input.close(); try? output.close() }
            var digest = SHA256()
            while let bytes = try input.read(upToCount: 64 * 1024), !bytes.isEmpty {
                try Task.checkCancellation(); digest.update(data: bytes); try output.write(contentsOf: bytes)
            }
            try output.synchronize(); try output.close()
            // The source may have been edited/replaced while it was copied.
            let check = try FileHandle(forReadingFrom: destination); defer { try? check.close() }
            var current = SHA256()
            while let bytes = try check.read(upToCount: 64 * 1024), !bytes.isEmpty { try Task.checkCancellation(); current.update(data: bytes) }
            guard try RecoveryStamp.read(destination) == stamp, Data(current.finalize()) == Data(digest.finalize()) else { throw RecoveryFailure.changed }
            let archiveStamp = try RecoveryStamp.read(original)
            complete = true
            return (original, stamp, archiveStamp)
        }
    }
    public struct PreparedReload: Sendable {
        fileprivate let snapshot: Snapshot
        fileprivate let stamp: RecoveryStamp
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
    }
    public struct PreparedRecovery: Sendable {
        fileprivate let snapshot: Snapshot
        public let original: URL
        fileprivate let stamp: RecoveryStamp
        fileprivate let archiveStamp: RecoveryStamp
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedAtomicFile
    }
    public enum RecoveryFailure: LocalizedError {
        case unavailable, changed, archive
        public var errorDescription: String? {
            switch self {
            case .unavailable: return "The saved waypoint path is missing or is not a regular file. It has not been changed."
            case .changed: return "The saved file or library changed during recovery. Retry before continuing."
            case .archive: return "Unable to preserve the original waypoint file. The library has not been replaced."
            }
        }
    }
    fileprivate struct RecoveryStamp: Equatable, Sendable {
        let size: Int64, inode: UInt64, volume: UInt64
        let modified: Date
        static func read(_ url: URL) throws -> Self {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, let modified = attributes[.modificationDate] as? Date else { throw RecoveryFailure.unavailable }
            return .init(size: size.int64Value, inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                         volume: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0, modified: modified)
        }
    }
    public func recoverySnapshot() throws -> RecoverySnapshot {
        lock.lock(); defer { lock.unlock() }
        guard loadError != nil else { throw RecoveryFailure.changed }
        return .init(destination: fileURL, revision: revision, identity: identity)
    }
    public func publishReload(_ prepared: PreparedReload) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else { throw EditFailure.wrongStore }
        guard prepared.revision == revision, loadError != nil, try RecoveryStamp.read(fileURL) == prepared.stamp else { throw RecoveryFailure.changed }
        waypoints = prepared.snapshot.waypoints; folders = prepared.snapshot.folders; selectedId = prepared.snapshot.selectedId; loadError = nil
        return true
    }
    public func publishRecovery(_ prepared: PreparedRecovery) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else { throw EditFailure.wrongStore }
        guard prepared.revision == revision, loadError != nil, try RecoveryStamp.read(fileURL) == prepared.stamp,
              try RecoveryStamp.read(prepared.original) == prepared.archiveStamp else { throw RecoveryFailure.changed }
        try prepared.file.publish()
        waypoints = prepared.snapshot.waypoints; folders = prepared.snapshot.folders; selectedId = nil; loadError = nil
        return prepared.original
    }
    public func recoveryFiles() throws -> [URL] {
        let directory = fileURL.deletingLastPathComponent().appendingPathComponent("WaypointRecovery", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil && $0.pathExtension == "json" && (try? RecoveryStamp.read($0)) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func load() {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            folders = [FolderInfo(name: Folders.defaultFolder)]; return
        }
        let snap: Snapshot
        do { snap = try JSONDecoder().decode(Snapshot.self,from: Data(contentsOf: fileURL)) }
        catch {
            loadError = "Cannot read saved waypoints. The original file has been kept."
            folders = [FolderInfo(name: Folders.defaultFolder)]; return
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
        guard loadError == nil else { return }
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
