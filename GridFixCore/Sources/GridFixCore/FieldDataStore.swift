import Combine
import Foundation

/// Imported/saved graphics, track logs, and practice history are committed as a
/// single atomic index with immutable point-log files. A legacy archive is read
/// without modification; the next successful commit migrates its complete data.
/// Live recording is deliberately separate from this finished-data store.
public final class FieldDataStore: ObservableObject, @unchecked Sendable {
    @Published public private(set) var document = Backup.Document() { didSet { revision &+= 1 } }
    @Published public private(set) var loadError: String?
    @Published public private(set) var ready: Bool
    private let fileURL: URL
    private var logs: [String: FieldDataDisk.Log] = [:]
    private var source: FieldDataReadSource?
    private var sourceDigest: String?
    private let lock = NSRecursiveLock()
    private var revision: UInt64 = 0
    private let identity = UUID()
    @MainActor private var loadTask: Task<PreparedLoad,Error>?
    @MainActor private var loadGeneration = UUID()

    public enum LoadFailure: LocalizedError {
        case changed
        public var errorDescription: String? { "Saved routes and tracks changed while opening. The original files were kept. Try again." }
    }
    public enum WriteFailure: LocalizedError {
        case changed
        public var errorDescription: String? { "Saved routes and tracks changed elsewhere. Reopen the app before editing them. The current files were kept." }
    }

    public init(directory: URL? = nil,loadImmediately: Bool = true) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent(FieldDataDisk.indexName)
        ready = loadImmediately
        document.hasSettings = false
        if loadImmediately {
            for attempt in 0..<3 {
                do {
                    let result = try LoadSnapshot(destination:fileURL,identity:identity).prepare()
                    try result.source?.validate()
                    document = result.document; logs = result.logs; loadError = result.error; source = result.source; sourceDigest = result.sourceDigest
                    break
                } catch LoadFailure.changed {
                    if attempt == 2 { loadError = LoadFailure.changed.localizedDescription }
                } catch { loadError = error.localizedDescription; break }
            }
        }
    }

    public struct LoadSnapshot: Sendable {
        fileprivate let destination: URL
        fileprivate let identity: UUID
        /// Only reads saved files. A partial/corrupt library never becomes a
        /// writable empty library, and no legacy recovery bytes are rewritten.
        /// Deferred mode checks index/file metadata now; requested point bytes
        /// are checked by the consumer worker through their immutable source.
        public func prepare(deferTrackContents: Bool = false) throws -> PreparedLoad {
            try Task.checkCancellation()
            var document = Backup.Document(); document.hasSettings = false
            var logs: [String: FieldDataDisk.Log] = [:], failure: String?
            let source: FieldDataReadSource
            do { source = try FieldDataReadSource.read(destination) }
            catch { return PreparedLoad(document:document,logs:[:],error:error.localizedDescription,identity:identity,source:nil) }
            do {
                if source.index != nil {
                    (document,logs) = try FieldDataDisk.read(destination,deferTrackContents:deferTrackContents)
                } else {
                    let legacy = destination.deletingLastPathComponent().appendingPathComponent("field-data-v1.zip")
                    if source.legacy != nil {
                        document = try Backup.importZip(Data(contentsOf: legacy,options: .mappedIfSafe))
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { failure = error.localizedDescription }
            try Task.checkCancellation()
            let sourceDigest = failure == nil ? try source.contentDigest() : nil
            try source.validate()
            return PreparedLoad(document: document,logs: logs,error: failure,identity: identity,source:source,sourceDigest:sourceDigest)
        }
    }
    public struct PreparedLoad: Sendable {
        fileprivate let document: Backup.Document
        fileprivate let logs: [String: FieldDataDisk.Log]
        fileprivate let error: String?
        fileprivate let identity: UUID
        fileprivate let source: FieldDataReadSource?
        fileprivate var sourceDigest: String? = nil
    }
    public func loadSnapshot() -> LoadSnapshot {
        LoadSnapshot(destination: fileURL,identity: identity)
    }
    @discardableResult public func publishLoad(_ prepared: PreparedLoad) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else { throw BackupError.notABackup("Prepared library belongs to a different store") }
        guard !ready else { return false }
        try prepared.source?.validate()
        document = prepared.document; logs = prepared.logs; loadError = prepared.error; source = prepared.source; sourceDigest = prepared.sourceDigest
        ready = true
        return true
    }
    /// Concurrent clients share a single worker. Cancelling one awaiting view
    /// cannot discard another client's load or publish on the worker executor.
    @MainActor public func load(prepare: @escaping @Sendable (LoadSnapshot) throws -> PreparedLoad = { try $0.prepare() }) async {
        guard !ready else { return }
        for _ in 0..<3 {
            let task: Task<PreparedLoad,Error>
            let token: UUID
            if let existing = loadTask { task = existing; token = loadGeneration }
            else {
                let snapshot = loadSnapshot()
                loadGeneration = UUID(); token = loadGeneration
                task = Task.detached(priority: .userInitiated) { try prepare(snapshot) }
                loadTask = task
            }
            do {
                let prepared = try await task.value
                guard loadGeneration == token, !Task.isCancelled else { return }
                _ = try publishLoad(prepared)
                loadTask = nil
                return
            } catch LoadFailure.changed {
                guard loadGeneration == token,!Task.isCancelled else { return }
                loadTask = nil
            } catch is CancellationError {
                // Cancellation is not damage. The next live client can retry.
                if loadGeneration == token { loadTask = nil }
                return
            } catch {
                guard loadGeneration == token, !Task.isCancelled else { return }
                var empty = Backup.Document(); empty.hasSettings = false
                _ = try? publishLoad(PreparedLoad(document: empty,logs: [:],error: error.localizedDescription,identity: identity,source:nil))
                loadTask = nil
                return
            }
        }
        guard !Task.isCancelled,!ready else { return }
        var empty = Backup.Document(); empty.hasSettings = false
        _ = try? publishLoad(PreparedLoad(document:empty,logs:[:],error:LoadFailure.changed.localizedDescription,identity:identity,source:nil))
    }

    /// Retry is explicit after a failed read. Healthy stores and an existing
    /// read are never reset; ordinary load clients still share one worker.
    @MainActor public func retryLoad(prepare: @escaping @Sendable (LoadSnapshot) throws -> PreparedLoad = { try $0.prepare() }) async {
        guard beginLoadRetry() else { return }
        await load(prepare:prepare)
    }
    private func beginLoadRetry() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard ready,loadError != nil else { return false }
        ready = false; loadError = nil
        return true
    }
    private func requireReady() throws {
        guard ready else { throw BackupError.notABackup("The field library is still loading. Try again when loading finishes.") }
        if let loadError { throw BackupError.notABackup("Stored field data could not be read and was kept: \(loadError)") }
    }

    public struct TrackMaintenanceSnapshot: Sendable {
        fileprivate let source: FieldDataReadSource
        fileprivate let retained: Set<String>
        fileprivate let deferred: [SavedTrackSource]
        /// Run on a worker. Retain indexed/recent/in-flight logs and all unknown
        /// files; remove at most64 old, unreferenced canonical log names.
        public func prune(now: Date = Date()) throws -> Int {
            // Metadata-only startup grants no deletion authority. Never force
            // unread logs to be scanned just to clean an unreferenced file.
            for file in deferred {
                try Task.checkCancellation()
                guard file.hasVerifiedBytes else { return 0 }
                try file.validate()
            }
            return try FieldDataDisk.pruneOrphans(source:source,retained:retained,now:now)
        }
    }
    public func trackMaintenanceSnapshot() throws -> TrackMaintenanceSnapshot? {
        lock.lock(); defer { lock.unlock() }
        try requireReady()
        guard let source,source.index != nil else { return nil }
        return .init(source:source,retained:Set(logs.values.map(\.name)),deferred:Array(document.localTrackFiles.values))
    }
    @MainActor public func maintainTrackStorage() async {
        guard !Task.isCancelled,let snapshot = try? trackMaintenanceSnapshot() else { return }
        let worker = Task.detached(priority:.utility) { try snapshot.prune() }
        await withTaskCancellationHandler(operation:{ _ = try? await worker.value },onCancel:{ worker.cancel() })
    }

    public func points(for trackID: String) throws -> [TrackPoint] {
        let snapshot = try trackReadSnapshot(trackID)
        return try TrackCodec.decodeLocal(snapshot.readBytes())
    }

    public struct TrackReadSnapshot: Sendable {
        public let track: Backup.TrackMeta
        fileprivate let bytes: Data?
        fileprivate let file: SavedTrackSource?
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        public func readBytes() throws -> Data {
            if let bytes { return bytes }
            if let file { return try file.read() }
            guard track.pointCount == 0 else { throw BackupError.notABackup("Saved track points are missing; original files were kept") }
            return Data()
        }
    }
    /// Capture the immutable source and library revision without file I/O.
    /// Its worker reads and verifies bytes only when the track is requested.
    public func trackReadSnapshot(_ id: String) throws -> TrackReadSnapshot {
        lock.lock(); defer { lock.unlock() }
        try requireReady()
        if let loadError { throw BackupError.notABackup("Stored field data could not be read and was kept: \(loadError)") }
        guard let track = document.tracks.first(where: { $0.id == id }) else { throw BackupError.notABackup("This track is no longer saved.") }
        return .init(track: track,bytes: document.trackFiles[id],file:document.localTrackFiles[id],revision: revision,identity: identity)
    }
    public func isCurrent(_ snapshot: TrackReadSnapshot) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ready && loadError == nil && snapshot.identity == identity && snapshot.revision == revision
    }

    public enum Edit: Sendable {
        case saveGraphic(Backup.Graphic)
        case createGraphic(Backup.Graphic)
        case editGraphic(original: Backup.Graphic,updated: Backup.Graphic)
        case deleteGraphic(String)
        case setGraphicVisible(String,Bool)
        case setTrackVisible(String,Bool)
        case deleteTrack(String)
        case libraryBatch(graphicIDs: Set<String>,trackIDs: Set<String>,action: LibraryBatchAction)
        case changeLibraryFolder(from: String,to: String?,deleteContents: Bool)
        case moveTrack(String,String)
        case saveRecordedTrack(Backup.Document)
    }

    public func saveGraphic(_ graphic: Backup.Graphic) throws { try edit(.saveGraphic(graphic)) }
    public func deleteGraphic(_ id: String) throws { try edit(.deleteGraphic(id)) }
    public func setTrackVisible(_ id: String,visible: Bool) throws { try edit(.setTrackVisible(id,visible)) }
    public func deleteTrack(_ id: String) throws { try edit(.deleteTrack(id)) }
    public func applyLibraryBatch(graphicIDs: Set<String>,trackIDs: Set<String>,action: LibraryBatchAction) throws {
        try edit(.libraryBatch(graphicIDs: graphicIDs,trackIDs: trackIDs,action: action))
    }
    public func changeLibraryFolder(from: String,to: String?,deleteContents: Bool = false) throws {
        try edit(.changeLibraryFolder(from: from,to: to,deleteContents: deleteContents))
    }
    public func moveTrack(_ id: String,to folder: String) throws { try edit(.moveTrack(id,folder)) }

    private func edit(_ edit: Edit) throws {
        lock.lock(); defer { lock.unlock() }
        try requireReady()
        if let next = try Self.applying(edit,to: document) { try commit(next) }
    }

    private static func applying(_ edit: Edit,to document: Backup.Document) throws -> Backup.Document? {
        var next = document
        switch edit {
        case .saveGraphic(var graphic):
            graphic.name = AutomaticNames.graphic(graphic, among: next.graphics)
            if let index = next.graphics.firstIndex(where: { $0.id == graphic.id }) { next.graphics[index] = graphic }
            else { next.graphics.append(graphic) }
        case .createGraphic(var graphic):
            graphic.name = AutomaticNames.graphic(graphic, among: next.graphics)
            guard !next.graphics.contains(where: { $0.id == graphic.id }) else { return nil }
            next.graphics.append(graphic)
        case let .editGraphic(original,updated):
            guard original.id == updated.id, let i = next.graphics.firstIndex(where: { $0.id == original.id }) else {
                throw BackupError.notABackup("This graphic is no longer saved. Your draft is kept.")
            }
            // Like Android's scoped rename/updatePoints/setVisible operations,
            // preserve current fields the editor did not change. Use exact bytes
            // for strings: Swift equality folds canonical Unicode equivalents.
            func changed(_ a: String,_ b: String) -> Bool { !a.utf8.elementsEqual(b.utf8) }
            if changed(original.name,updated.name) { next.graphics[i].name = AutomaticNames.graphic(updated, among: next.graphics) }
            if changed(original.folder,updated.folder) { next.graphics[i].folder = updated.folder }
            if changed(original.type,updated.type) { next.graphics[i].type = updated.type }
            if changed(original.affiliation,updated.affiliation) { next.graphics[i].affiliation = updated.affiliation }
            if changed(original.echelon,updated.echelon) { next.graphics[i].echelon = updated.echelon }
            if original.points != updated.points { next.graphics[i].points = updated.points }
            if original.visible != updated.visible { next.graphics[i].visible = updated.visible }
        case .deleteGraphic(let id): next.graphics.removeAll { $0.id == id }
        case let .setGraphicVisible(id,visible):
            guard let i = next.graphics.firstIndex(where: { $0.id == id }) else { return nil }
            next.graphics[i].visible = visible
        case let .setTrackVisible(id,visible):
            guard let i = next.tracks.firstIndex(where: { $0.id == id }) else { return nil }
            next.tracks[i].visible = visible
        case .deleteTrack(let id):
            next.tracks.removeAll { $0.id == id }; next.trackFiles.removeValue(forKey: id); next.localTrackFiles.removeValue(forKey:id)
        case let .libraryBatch(graphicIDs,trackIDs,action):
            guard !graphicIDs.isEmpty || !trackIDs.isEmpty else { return nil }
            switch action {
            case .hide:
                for i in next.graphics.indices where graphicIDs.contains(next.graphics[i].id) { next.graphics[i].visible = false }
                for i in next.tracks.indices where trackIDs.contains(next.tracks[i].id) { next.tracks[i].visible = false }
            case .swapVisibility:
                for i in next.graphics.indices where graphicIDs.contains(next.graphics[i].id) { next.graphics[i].visible.toggle() }
                for i in next.tracks.indices where trackIDs.contains(next.tracks[i].id) { next.tracks[i].visible.toggle() }
            case .delete:
                next.graphics.removeAll { graphicIDs.contains($0.id) }; next.tracks.removeAll { trackIDs.contains($0.id) }
                for id in trackIDs { next.trackFiles.removeValue(forKey: id); next.localTrackFiles.removeValue(forKey:id) }
            }
        case let .changeLibraryFolder(from,to,deleteContents):
            guard from.caseInsensitiveCompare(Folders.defaultFolder) != .orderedSame else { return nil }
            if deleteContents {
                let removed = Set(next.tracks.filter { $0.folder.caseInsensitiveCompare(from) == .orderedSame }.map(\.id))
                next.graphics.removeAll { $0.folder.caseInsensitiveCompare(from) == .orderedSame }
                next.tracks.removeAll { removed.contains($0.id) }
                for id in removed { next.trackFiles.removeValue(forKey: id); next.localTrackFiles.removeValue(forKey:id) }
            } else {
                let target = Folders.canonical(to)
                for i in next.graphics.indices where next.graphics[i].folder.caseInsensitiveCompare(from) == .orderedSame { next.graphics[i].folder = target }
                for i in next.tracks.indices where next.tracks[i].folder.caseInsensitiveCompare(from) == .orderedSame { next.tracks[i].folder = target }
            }
        case let .moveTrack(id,folder):
            guard let i = next.tracks.firstIndex(where: { $0.id == id }) else { return nil }
            next.tracks[i].folder = Folders.canonical(folder)
        case .saveRecordedTrack(let recording):
            try Backup.validate(recording,includingTrackFiles: false)
            guard recording.tracks.count == 1, let track = recording.tracks.first,
                  let bytes = recording.trackFiles[track.id] else { throw BackupError.notABackup("Invalid finished recording") }
            guard Set(recording.trackFiles.keys) == [track.id] else { throw BackupError.notABackup("Invalid finished recording files") }
            if next.tracks.contains(where: { $0.id == track.id }) {
                guard try next.trackData(track.id) == bytes else { throw BackupError.notABackup("A different track already has this recording ID; journal kept") }
                return nil
            }
            // Every new log is fully validated by FieldDataDisk.prepare before
            // publication. Do not calculate its distance a second time here.
            // An idempotent retry above reuses already-validated stored bytes.
            next.tracks.append(track); next.trackFiles[track.id] = bytes
        }
        return next
    }

    /// Final publication is idempotent after a crash between archive commit and
    /// journal cleanup. Never silently replace a different log with the same ID.
    public func saveRecordedTrack(_ recording: Backup.Document) throws {
        try edit(.saveRecordedTrack(recording))
    }

    /// Existing IDs win, course results are deduplicated by start/name and the
    /// newest 30 survive, matching Android's mergeCourseHistory policy.
    @discardableResult
    public func restore(_ incoming: Backup.Document) throws -> Backup.RestoreResult {
        try Backup.validate(incoming)
        lock.lock(); defer { lock.unlock() }
        try requireReady()
        let (next,result) = try Self.merged(document,incoming)
        if result.graphics == 0 && result.tracks == 0 && next.courseHistory == document.courseHistory { return result }
        try commit(next)
        return result
    }

    private static func merged(_ current: Backup.Document,_ incoming: Backup.Document) throws -> (Backup.Document,Backup.RestoreResult) {
        var next = current
        let graphicIDs = Set(next.graphics.map(\.id)), trackIDs = Set(next.tracks.map(\.id))
        let graphics = incoming.graphics.filter { !graphicIDs.contains($0.id) }
        let tracks = incoming.tracks.filter { !trackIDs.contains($0.id) }
        next.graphics += graphics; next.tracks += tracks
        for track in tracks { next.trackFiles[track.id] = try incoming.trackData(track.id) }
        struct HistoryKey: Hashable { let started: Int64; let name: String }
        var keys = Set<HistoryKey>()
        let oldKeys = Set(next.courseHistory.map { HistoryKey(started: $0.started, name: $0.name) })
        next.courseHistory = Array((next.courseHistory + incoming.courseHistory).filter {
            keys.insert(HistoryKey(started: $0.started, name: $0.name)).inserted
        }.sorted { $0.started == $1.started ? $0.name.utf16.lexicographicallyPrecedes($1.name.utf16) : $0.started < $1.started }.suffix(30))
        let courseAdded = next.courseHistory.filter { !oldKeys.contains(HistoryKey(started: $0.started, name: $0.name)) }.count
        return (next,Backup.RestoreResult(waypoints: 0,graphics: graphics.count,tracks: tracks.count,course: courseAdded,settingsApplied: false))
    }

    public struct RestoreSnapshot: Sendable {
        fileprivate let document: Backup.Document
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let destination: URL
        fileprivate let logs: [String: FieldDataDisk.Log]
        fileprivate let source: FieldDataReadSource
        fileprivate let sourceDigest: String?

        /// Prepare an ordinary edit without borrowing the live repository lock.
        public func prepare(edit: Edit) throws -> PreparedEdit {
            try Task.checkCancellation()
            let next = try FieldDataStore.applying(edit,to: document)
            let file = try next.map { try FieldDataDisk.prepare($0,previous: document,logs: logs,index: destination,source:source,sourceDigest:sourceDigest) }
            return PreparedEdit(document: next,revision: revision,identity: identity,file: file)
        }

        /// May run on a worker. Does not read or mutate the live store.
        public func prepare(_ incoming: Backup.Document) throws -> PreparedRestore {
            try Backup.validate(incoming)
            let (next,result) = try FieldDataStore.merged(document,incoming)
            let changed = result.graphics != 0 || result.tracks != 0 || next.courseHistory != document.courseHistory
            let file: PreparedFieldData?
            if changed { file = try FieldDataDisk.prepare(next,previous: document,logs: logs,index: destination,source:source,sourceDigest:sourceDigest) }
            else { file = nil }
            return PreparedRestore(document: next,result: result,revision: revision,identity: identity,file: file)
        }
    }

    public struct PreparedEdit: Sendable {
        fileprivate let document: Backup.Document?
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedFieldData?
    }

    /// False means the source changed; reapply the intent to a fresh snapshot.
    public func publishEdit(_ prepared: PreparedEdit) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else { throw BackupError.notABackup("Prepared field edit belongs to a different store") }
        guard prepared.revision == revision else { prepared.file?.discard(); return false }
        if let file = prepared.file, let next = prepared.document {
            source = try file.publish(); sourceDigest = file.digest; logs = file.logs; document = next
        }
        return true
    }

    public struct PreparedRestore: Sendable {
        fileprivate let document: Backup.Document
        fileprivate let result: Backup.RestoreResult
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedFieldData?
    }

    public func restoreSnapshot() throws -> RestoreSnapshot {
        lock.lock(); defer { lock.unlock() }
        try requireReady()
        if let loadError { throw BackupError.notABackup("Stored field data could not be read and was kept: \(loadError)") }
        guard let source else { throw WriteFailure.changed }
        return RestoreSnapshot(document: document,revision: revision,identity: identity,destination: fileURL,logs: logs,source:source,sourceDigest:sourceDigest)
    }

    /// Nil means a concurrent mutation won; discard this preparation and merge
    /// again. Invoke on the publication executor (the main actor in the app).
    public func publishRestore(_ prepared: PreparedRestore) throws -> Backup.RestoreResult? {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else {
            throw BackupError.notABackup("Prepared field restore belongs to a different store")
        }
        guard prepared.revision == revision else { prepared.file?.discard(); return nil }
        if let file = prepared.file {
            source = try file.publish(); sourceDigest = file.digest
            logs = file.logs; document = prepared.document
        }
        return prepared.result
    }

    public func backup(waypoints: [Waypoint], folders: [FolderInfo], settings: Backup.AppSettings) throws -> Backup.Document {
        lock.lock(); defer { lock.unlock() }
        try requireReady()
        if let loadError { throw BackupError.notABackup("Stored field data could not be read and was kept: \(loadError)") }
        var snapshot = document
        snapshot.waypoints = waypoints; snapshot.folders = folders; snapshot.settings = settings
        snapshot.hasSettings = true
        snapshot.exportedAt = Int64(Date().timeIntervalSince1970 * 1000)
        return snapshot
    }

    private func commit(_ next: Backup.Document) throws {
        try requireReady()
        if let loadError { throw BackupError.notABackup("Stored field data could not be read and was kept: \(loadError)") }
        guard let source else { throw WriteFailure.changed }
        let prepared = try FieldDataDisk.prepare(next,previous: document,logs: logs,index: fileURL,source:source,sourceDigest:sourceDigest)
        self.source = try prepared.publish(); sourceDigest = prepared.digest; logs = prepared.logs; document = next
    }
}
