import Combine
import Foundation

/// Imported/saved graphics, track logs, and practice history are committed as a
/// single atomic archive. An interrupted import never publishes half a batch.
/// Live recording is deliberately separate from this finished-data store.
public final class FieldDataStore: ObservableObject, @unchecked Sendable {
    @Published public private(set) var document = Backup.Document() { didSet { revision &+= 1 } }
    @Published public private(set) var loadError: String?
    private let fileURL: URL
    private let lock = NSRecursiveLock()
    private var revision: UInt64 = 0
    private let identity = UUID()

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("field-data-v1.zip")
        document.hasSettings = false
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { document = try Backup.importZip(Data(contentsOf: fileURL)) }
            catch { loadError = error.localizedDescription }
        }
    }

    public func points(for trackID: String) throws -> [TrackPoint] {
        lock.lock()
        let bytes = document.trackFiles[trackID] ?? Data()
        lock.unlock()
        return try TrackCodec.decode(bytes)
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
        if let next = try Self.applying(edit,to: document) { try commit(next) }
    }

    private static func applying(_ edit: Edit,to document: Backup.Document) throws -> Backup.Document? {
        var next = document
        switch edit {
        case .saveGraphic(let graphic):
            if let index = next.graphics.firstIndex(where: { $0.id == graphic.id }) { next.graphics[index] = graphic }
            else { next.graphics.append(graphic) }
        case .createGraphic(let graphic):
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
            if changed(original.name,updated.name) { next.graphics[i].name = updated.name }
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
            next.tracks.removeAll { $0.id == id }; next.trackFiles.removeValue(forKey: id)
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
                for id in trackIDs { next.trackFiles.removeValue(forKey: id) }
            }
        case let .changeLibraryFolder(from,to,deleteContents):
            guard from.caseInsensitiveCompare(Folders.defaultFolder) != .orderedSame else { return nil }
            if deleteContents {
                let removed = Set(next.tracks.filter { $0.folder.caseInsensitiveCompare(from) == .orderedSame }.map(\.id))
                next.graphics.removeAll { $0.folder.caseInsensitiveCompare(from) == .orderedSame }
                next.tracks.removeAll { removed.contains($0.id) }
                for id in removed { next.trackFiles.removeValue(forKey: id) }
            } else {
                let target = Folders.canonical(to)
                for i in next.graphics.indices where next.graphics[i].folder.caseInsensitiveCompare(from) == .orderedSame { next.graphics[i].folder = target }
                for i in next.tracks.indices where next.tracks[i].folder.caseInsensitiveCompare(from) == .orderedSame { next.tracks[i].folder = target }
            }
        case let .moveTrack(id,folder):
            guard let i = next.tracks.firstIndex(where: { $0.id == id }) else { return nil }
            next.tracks[i].folder = Folders.canonical(folder)
        case .saveRecordedTrack(let recording):
            try Backup.validate(recording)
            guard recording.tracks.count == 1, let track = recording.tracks.first,
                  let bytes = recording.trackFiles[track.id] else { throw BackupError.notABackup("Invalid finished recording") }
            if next.tracks.contains(where: { $0.id == track.id }) {
                guard next.trackFiles[track.id] == bytes else { throw BackupError.notABackup("A different track already has this recording ID; journal kept") }
                return nil
            }
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
        let (next,result) = Self.merged(document,incoming)
        if result.graphics == 0 && result.tracks == 0 && next.courseHistory == document.courseHistory { return result }
        try commit(next)
        return result
    }

    private static func merged(_ current: Backup.Document,_ incoming: Backup.Document) -> (Backup.Document,Backup.RestoreResult) {
        var next = current
        let graphicIDs = Set(next.graphics.map(\.id)), trackIDs = Set(next.tracks.map(\.id))
        let graphics = incoming.graphics.filter { !graphicIDs.contains($0.id) }
        let tracks = incoming.tracks.filter { !trackIDs.contains($0.id) }
        next.graphics += graphics; next.tracks += tracks
        for track in tracks { next.trackFiles[track.id] = incoming.trackFiles[track.id] ?? Data() }
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

        /// Prepare an ordinary edit without borrowing the live repository lock.
        public func prepare(edit: Edit) throws -> PreparedEdit {
            try Task.checkCancellation()
            let next = try FieldDataStore.applying(edit,to: document)
            let file = try next.map { try PreparedAtomicFile(data: Backup.exportZip($0),destination: destination,lockCompatible: true) }
            return PreparedEdit(document: next,revision: revision,identity: identity,file: file)
        }

        /// May run on a worker. Does not read or mutate the live store.
        public func prepare(_ incoming: Backup.Document) throws -> PreparedRestore {
            try Backup.validate(incoming)
            let (next,result) = FieldDataStore.merged(document,incoming)
            let changed = result.graphics != 0 || result.tracks != 0 || next.courseHistory != document.courseHistory
            let file: PreparedAtomicFile?
            if changed { file = try PreparedAtomicFile(data: Backup.exportZip(next),destination: destination,lockCompatible: true) }
            else { file = nil }
            return PreparedRestore(document: next,result: result,revision: revision,identity: identity,file: file)
        }
    }

    public struct PreparedEdit: Sendable {
        fileprivate let document: Backup.Document?
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedAtomicFile?
    }

    /// False means the source changed; reapply the intent to a fresh snapshot.
    public func publishEdit(_ prepared: PreparedEdit) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepared.identity == identity else { throw BackupError.notABackup("Prepared field edit belongs to a different store") }
        guard prepared.revision == revision else { prepared.file?.discard(); return false }
        if let file = prepared.file, let next = prepared.document {
            try file.publish(); document = next
        }
        return true
    }

    public struct PreparedRestore: Sendable {
        fileprivate let document: Backup.Document
        fileprivate let result: Backup.RestoreResult
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedAtomicFile?
    }

    public func restoreSnapshot() throws -> RestoreSnapshot {
        lock.lock(); defer { lock.unlock() }
        if let loadError { throw BackupError.notABackup("Stored field data could not be read and was kept: \(loadError)") }
        return RestoreSnapshot(document: document,revision: revision,identity: identity,destination: fileURL)
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
            try file.publish()
            document = prepared.document
        }
        return prepared.result
    }

    public func backup(waypoints: [Waypoint], folders: [FolderInfo], settings: Backup.AppSettings) -> Backup.Document {
        lock.lock(); defer { lock.unlock() }
        var snapshot = document
        snapshot.waypoints = waypoints; snapshot.folders = folders; snapshot.settings = settings
        snapshot.hasSettings = true
        snapshot.exportedAt = Int64(Date().timeIntervalSince1970 * 1000)
        return snapshot
    }

    private func commit(_ next: Backup.Document) throws {
        if let loadError { throw BackupError.notABackup("Stored field data could not be read and was kept: \(loadError)") }
        let data = try Backup.exportZip(next)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: fileURL, options: options)
        document = next
    }
}
