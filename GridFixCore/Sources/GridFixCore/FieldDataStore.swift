import Combine
import Foundation

/// Imported/saved graphics, track logs, and practice history are committed as a
/// single atomic archive. An interrupted import never publishes half a batch.
/// Live recording is deliberately separate from this finished-data store.
public final class FieldDataStore: ObservableObject, @unchecked Sendable {
    @Published public private(set) var document = Backup.Document()
    @Published public private(set) var loadError: String?
    private let fileURL: URL
    private let lock = NSRecursiveLock()

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
        lock.lock(); defer { lock.unlock() }
        return try TrackCodec.decode(document.trackFiles[trackID] ?? Data())
    }

    public func saveGraphic(_ graphic: Backup.Graphic) throws {
        lock.lock(); defer { lock.unlock() }
        var next = document
        if let index = next.graphics.firstIndex(where: { $0.id == graphic.id }) { next.graphics[index] = graphic }
        else { next.graphics.append(graphic) }
        try commit(next)
    }

    public func deleteGraphic(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var next = document; next.graphics.removeAll { $0.id == id }; try commit(next)
    }

    public func setTrackVisible(_ id: String, visible: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        var next = document
        guard let index = next.tracks.firstIndex(where: { $0.id == id }) else { return }
        next.tracks[index].visible = visible
        try commit(next)
    }

    public func deleteTrack(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var next = document
        next.tracks.removeAll { $0.id == id }; next.trackFiles.removeValue(forKey: id)
        try commit(next)
    }

    /// Existing IDs win, course results are deduplicated by start/name and the
    /// newest 30 survive, matching Android's mergeCourseHistory policy.
    @discardableResult
    public func restore(_ incoming: Backup.Document) throws -> Backup.RestoreResult {
        try Backup.validate(incoming)
        lock.lock(); defer { lock.unlock() }
        var next = document
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
        }.sorted { $0.started == $1.started ? $0.name < $1.name : $0.started < $1.started }.suffix(30))
        let courseAdded = next.courseHistory.filter { !oldKeys.contains(HistoryKey(started: $0.started, name: $0.name)) }.count
        try commit(next)
        return Backup.RestoreResult(waypoints: 0, graphics: graphics.count, tracks: tracks.count, course: courseAdded, settingsApplied: false)
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
        try data.write(to: fileURL, options: .atomic)
        document = next
    }
}
