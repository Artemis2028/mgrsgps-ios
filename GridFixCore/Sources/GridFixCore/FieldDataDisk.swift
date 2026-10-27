import CryptoKit
import Foundation

/// Local storage is independent of the bounded backup/interchange ZIP contract.
/// Immutable, uniquely named logs are installed before one atomic metadata index.
enum FieldDataDisk {
    static let indexName = "field-data-v2.json"
    static let logsName = "field-track-logs-v2"
    private static let indexLimit = 64 * 1024 * 1024
    struct Log: Codable, Sendable { let name: String; let sha256: String }
    private struct Index: Codable {
        var format = "GridFixFieldStore"
        var version = 2
        let manifest: Data
        let logs: [String: Log]
    }
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x",$0) }.joined() }
    private static func validName(_ name: String) -> Bool {
        name.hasSuffix(".txt") && TrackCodec.validID(String(name.dropLast(4)))
    }
    static func read(_ index: URL) throws -> (Backup.Document,[String: Log]) {
        let size = try index.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= indexLimit else { throw BackupError.notABackup("Saved field index exceeds its metadata limit") }
        let envelope = try JSONDecoder().decode(Index.self,from: Data(contentsOf: index,options: .mappedIfSafe))
        guard envelope.format == "GridFixFieldStore", envelope.version == 2 else { throw BackupError.notABackup("Unsupported saved field index") }
        var document = try Backup.decodeManifest(envelope.manifest)
        try Backup.validate(document,includingTrackFiles: false)
        guard Set(envelope.logs.keys) == Set(document.tracks.map(\.id)) else { throw BackupError.notABackup("Saved track index is incomplete") }
        let directory = index.deletingLastPathComponent().appendingPathComponent(logsName,isDirectory: true)
        for i in document.tracks.indices {
            try Task.checkCancellation()
            let id = document.tracks[i].id
            guard let ref = envelope.logs[id], validName(ref.name) else { throw BackupError.notABackup("Invalid saved track filename") }
            let path = directory.appendingPathComponent(ref.name)
            let attributes = try path.resourceValues(forKeys: [.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw BackupError.notABackup("Invalid saved track file") }
            let bytes = try Data(contentsOf: path,options: .mappedIfSafe)
            guard digest(bytes) == ref.sha256 else { throw BackupError.notABackup("Saved track checksum failed; original data was kept") }
            let summary = try TrackCodec.summarizeLocal(bytes)
            document.trackFiles[id] = bytes
            // Retain the old ZIP reader's authoritative recomputation policy.
            document.tracks[i].pointCount = summary.count
            document.tracks[i].distanceM = summary.distanceM
        }
        return (document,envelope.logs)
    }
    static func prepare(_ document: Backup.Document,previous: Backup.Document,logs: [String: Log],index: URL,source: FieldDataReadSource,sourceDigest: String?) throws -> PreparedFieldData {
        try Task.checkCancellation()
        let expectedSource = try source.refreshedIfIdentical(digest:sourceDigest)
        try Backup.validate(document,includingTrackFiles: false)
        guard Set(document.trackFiles.keys).isSubset(of: Set(document.tracks.map(\.id))) else { throw BackupError.notABackup("Track file is missing from manifest") }
        let directory = index.deletingLastPathComponent().appendingPathComponent(logsName,isDirectory: true)
        if !document.tracks.isEmpty { try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true) }
        var next: [String: Log] = [:], installed: [URL] = []
        do {
            for track in document.tracks {
                try Task.checkCancellation()
                guard let bytes = document.trackFiles[track.id] ?? (track.pointCount == 0 ? Data() : nil) else { throw BackupError.notABackup("Missing saved track points") }
                if let ref = logs[track.id], previous.trackFiles[track.id] == bytes {
                    let attributes = try directory.appendingPathComponent(ref.name).resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                    guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, attributes.fileSize == bytes.count else { throw BackupError.notABackup("Saved track changed or is missing; original index was kept") }
                    // Retained logs are immutable and already validated; metadata
                    // edits must not parse/hash/rewrite the whole finished library.
                    next[track.id] = ref
                } else {
                    _ = try TrackCodec.summarizeLocal(bytes)
                    let hash = digest(bytes)
                    // Never reuse an obsolete filename: post-commit deletion cannot
                    // remove a later restore, even when IDs/point bytes are identical.
                    let name = UUID().uuidString.lowercased()+".txt"
                    let file = try PreparedAtomicFile(data: bytes,destination: directory.appendingPathComponent(name),lockCompatible: true,synchronize: true)
                    try Task.checkCancellation(); try PreparedFieldData.install(file)
                    installed.append(file.destination); next[track.id] = .init(name: name,sha256: hash)
                }
            }
            let envelope = Index(manifest: try Backup.encodeManifest(document),logs: next)
            let data = try JSONEncoder().encode(envelope)
            guard data.count <= indexLimit else { throw BackupError.notABackup("Saved field index exceeds its metadata limit") }
            let marker = try PreparedAtomicFile(data: data,destination: index,lockCompatible: true,synchronize: true)
            let retained = Set(next.values.map(\.name))
            let obsolete = logs.values.filter { !retained.contains($0.name) }.map { directory.appendingPathComponent($0.name) }
            try Task.checkCancellation()
            return .init(index: marker,installed: installed,logs: next,obsolete: obsolete,expectedSource:expectedSource,digest:digest(data))
        } catch { PreparedFieldData.discardInstalled(installed); throw error }
    }

    /// Bounded worker maintenance. Missing/corrupt indexes never grant deletion
    /// authority; the caller must hold a successful read's exact source receipt.
    static func pruneOrphans(source: FieldDataReadSource,retained: Set<String>,now: Date) throws -> Int {
        guard source.index != nil else { return 0 }
        let directory = source.indexURL.deletingLastPathComponent().appendingPathComponent(logsName,isDirectory:true)
        let attributes = try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard attributes.isDirectory == true,attributes.isSymbolicLink != true else { return 0 }
        guard let files = FileManager.default.enumerator(at:directory,includingPropertiesForKeys:nil,options:[.skipsSubdirectoryDescendants]) else { return 0 }
        let cutoff = now.addingTimeInterval(-24*60*60)
        var candidates: [(URL,FieldDataReadSource.Stamp)] = []
        while let file = files.nextObject() as? URL {
            try Task.checkCancellation()
            guard validName(file.lastPathComponent),!retained.contains(file.lastPathComponent),
                  let stamp = try? FieldDataReadSource.Stamp.read(file),stamp.modified <= cutoff else { continue }
            candidates.append((file,stamp))
            if candidates.count == 64 { break }
        }
        var removed = 0
        for (file,stamp) in candidates {
            try Task.checkCancellation()
            if try PreparedFieldData.removeOrphan(file,stamp:stamp,source:source) { removed += 1 }
        }
        return removed
    }
}

/// A preparation owns only fresh, unreferenced filenames. The immutable logs
/// are ready before the main executor performs its one index rename.
final class PreparedFieldData: @unchecked Sendable {
    // Source check and rename are one short in-process publication gate, even
    // when separate store instances prepared against the same saved index.
    private static let publicationLock = NSRecursiveLock()
    // Filenames are fresh UUIDs. Counts also protect the unlikely case of the
    // same generated name in two roots; an extra retained file is harmless.
    private static var activeLogNames: [String:Int] = [:]
    let index: PreparedAtomicFile
    let installed: [URL]
    let logs: [String: FieldDataDisk.Log]
    let obsolete: [URL]
    let expectedSource: FieldDataReadSource
    let digest: String
    private let lock = NSLock()
    private var consumed = false
    init(index: PreparedAtomicFile,installed: [URL],logs: [String: FieldDataDisk.Log],obsolete: [URL],expectedSource: FieldDataReadSource,digest: String) {
        self.index = index; self.installed = installed; self.logs = logs; self.obsolete = obsolete
        self.expectedSource = expectedSource; self.digest = digest
    }
    func discard() {
        lock.lock(); guard !consumed else { lock.unlock(); return }
        consumed = true; lock.unlock()
        index.discard(); Self.discardInstalled(installed)
    }
    func publish() throws -> FieldDataReadSource {
        Self.publicationLock.lock(); defer { Self.publicationLock.unlock() }
        lock.lock()
        guard !consumed else { lock.unlock(); throw BackupError.notABackup("Field preparation was already consumed. Prepare again.") }
        do {
            guard try FieldDataReadSource.read(index.destination) == expectedSource else { throw FieldDataStore.WriteFailure.changed }
            try index.publish(); consumed = true; lock.unlock()
        } catch {
            consumed = true; lock.unlock(); index.discard(); Self.discardInstalled(installed)
            throw error
        }
        Self.removeLater(obsolete)
        Self.releaseInstalled(installed)
        // Publication succeeded: never remove its installed logs if a later
        // source stat fails. Reopening can recover the complete committed index.
        guard let updated = try? FieldDataReadSource.read(index.destination),updated.index != nil else { throw FieldDataStore.WriteFailure.changed }
        return updated
    }
    static func removeLater(_ paths: [URL]) {
        guard !paths.isEmpty else { return }
        Task.detached(priority: .utility) { for path in paths { try? FileManager.default.removeItem(at: path) } }
    }
    static func install(_ file: PreparedAtomicFile) throws {
        publicationLock.lock(); defer { publicationLock.unlock() }
        try file.publish(replacing:false)
        activeLogNames[file.destination.lastPathComponent,default:0] += 1
    }
    private static func releaseInstalled(_ paths: [URL]) {
        publicationLock.lock(); defer { publicationLock.unlock() }
        for file in paths {
            let name = file.lastPathComponent
            if let count = activeLogNames[name],count > 1 { activeLogNames[name] = count-1 }
            else { activeLogNames.removeValue(forKey:name) }
        }
    }
    static func discardInstalled(_ paths: [URL]) {
        releaseInstalled(paths); removeLater(paths)
    }
    static func removeOrphan(_ file: URL,stamp: FieldDataReadSource.Stamp,source: FieldDataReadSource) throws -> Bool {
        publicationLock.lock(); defer { publicationLock.unlock() }
        try source.validate()
        guard activeLogNames[file.lastPathComponent] == nil,
              (try? FieldDataReadSource.Stamp.read(file)) == stamp else { return false }
        try FileManager.default.removeItem(at:file)
        return true
    }
    deinit { discard() }
}
