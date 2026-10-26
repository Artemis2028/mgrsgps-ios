import Foundation
import GridFixCore

@MainActor
enum InterchangeCoordinator {
    struct Result: Sendable {
        var completed: Bool
        var message: String
    }

    /// Android imports commit tracks, then waypoints/folders, then graphics.
    /// Each phase is atomic; stable content IDs make a retry additive. Workers
    /// finish a started phase; cancellation is honored between phases, matching
    /// Android ImportCoordinator.persist and never translated into a write error.
    static func apply(_ document: Backup.Document, waypoints: WaypointStore, field: FieldDataStore) async throws -> Result {
        var saved: [String] = []
        var phase = "validation"
        do {
            try Task.checkCancellation()
            let validation = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                try Backup.validate(document)
                try Task.checkCancellation()
            }
            try await withTaskCancellationHandler(operation: { try await validation.value },onCancel: { validation.cancel() })
            try Task.checkCancellation()
            if !document.tracks.isEmpty {
                phase = "tracks"
                var tracks = Backup.Document(); tracks.hasSettings = false
                tracks.tracks = document.tracks; tracks.trackFiles = document.trackFiles
                let count = try await LibraryRestoreCommit.field(tracks,into: field).tracks
                if count > 0 { saved.append("\(count) tracks") }
            }
            try Task.checkCancellation()
            if !document.waypoints.isEmpty || !document.folders.isEmpty {
                phase = "waypoints and folders"
                let count = try await LibraryRestoreCommit.waypoints(document.waypoints,folders: document.folders,into: waypoints)
                if count > 0 { saved.append("\(count) waypoints") }
            }
            try Task.checkCancellation()
            if !document.graphics.isEmpty {
                phase = "graphics/routes"
                var graphics = Backup.Document(); graphics.hasSettings = false; graphics.graphics = document.graphics
                let count = try await LibraryRestoreCommit.field(graphics,into: field).graphics
                if count > 0 { saved.append("\(count) graphics/routes") }
            }
            try Task.checkCancellation()
            return .init(completed: true,message: saved.isEmpty ? "Nothing new to import. Existing records kept." : "Imported " + saved.joined(separator: ", "))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let progress = saved.isEmpty ? "No records added." : "Already imported: " + saved.joined(separator: ", ") + "."
            let failure = phase == "validation" ? "Could not validate import" : "Could not save " + phase
            return .init(completed: false,message: "Import stopped: \(failure): \(error.localizedDescription). \(progress) Retry this unchanged file to finish without duplicates.")
        }
    }
}

/// Bounds the read itself, including files whose provider reports no byte size.
/// Coordination and parsing run off the UI thread. No persistence happens here.
enum InterchangeFileReview: Sendable {
    case interchange(InterchangePreview)
    case backup(Backup.Document)
}
enum InterchangeFileReader {
    /// Keep provider coordination/security access alive while reading mapped ZIP
    /// pages, rather than returning a mapping after provider access is released.
    static func backup(_ url: URL,password: String? = nil) throws -> Backup.Document {
        try coordinated(url) { source in
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            let head = try handle.read(upToCount: 12) ?? Data()
            let limit = BackupCrypto.isSealed(head) ? BackupCrypto.maximumSealedBytes : KMZ.inputByteLimit
            guard try handle.seekToEnd() <= UInt64(limit) else { throw BackupError.notABackup("Backup container exceeds \(limit/(1024*1024)) MB") }
            try Task.checkCancellation()
            let bytes = try Data(contentsOf: source,options: .mappedIfSafe)
            guard bytes.count <= limit else { throw BackupError.notABackup("Backup container exceeds \(limit/(1024*1024)) MB") }
            if BackupCrypto.isSealed(bytes) {
                guard let password else { throw BackupCrypto.Failure.passwordRequired }
                switch try ProtectedFiles.open(bytes,password: password) {
                case .backup(let plain): return try Backup.importZip(plain)
                case .file: throw BackupError.notABackup("This is a protected export. Choose Import file to review it.")
                }
            }
            return try Backup.importZip(bytes)
        }
    }
    /// Parse while coordinated access is still held. Mapping avoids duplicating
    /// a large archive container; decoded members are visited one at a time.
    static func preview(_ url: URL,format: TextInterchangeFormat?,knownFolders: [String],password: String? = nil) throws -> InterchangePreview {
        switch try review(url,format: format,knownFolders: knownFolders,password: password) {
        case .interchange(let preview): return preview
        case .backup: throw BackupError.notABackup("This file is an MGRS GPS backup. Use Import backup to restore it.")
        }
    }
    static func review(_ url: URL,format: TextInterchangeFormat?,knownFolders: [String],password: String? = nil) throws -> InterchangeFileReview {
        try coordinated(url) { source in
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            let head = try handle.read(upToCount: 12) ?? Data()
            let sealed = BackupCrypto.isSealed(head)
            let limit = sealed ? BackupCrypto.maximumSealedBytes : (format?.byteLimit ?? TextInterchange.fileLimit(filename: url.lastPathComponent))
            guard try handle.seekToEnd() <= UInt64(limit) else { throw BackupError.notABackup("File exceeds \(limit/(1024*1024)) MB") }
            try Task.checkCancellation()
            let bytes = try Data(contentsOf: source,options: .mappedIfSafe)
            guard bytes.count <= limit else { throw BackupError.notABackup("File exceeds \(limit/(1024*1024)) MB") }
            if sealed {
                guard let password else { throw BackupCrypto.Failure.passwordRequired }
                switch try ProtectedFiles.open(bytes,password: password) {
                case .backup(let archive): return .backup(try Backup.importZip(archive))
                case let .file(name,data):
                    return .interchange(try TextInterchange.preview(data,filename: name,knownFolders: knownFolders))
                }
            }
            return .interchange(try TextInterchange.preview(bytes,format: format,filename: url.lastPathComponent,knownFolders: knownFolders))
        }
    }
    static func read(_ url: URL,limit: Int) throws -> Data {
        try coordinated(url) { source in
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            var data = Data()
            while data.count <= limit {
                try Task.checkCancellation()
                let part = try handle.read(upToCount: min(64*1024,limit+1-data.count)) ?? Data()
                if part.isEmpty { return data }
                data.append(part)
            }
            throw BackupError.notABackup("File exceeds \(limit/(1024*1024)) MB")
        }
    }
    private static func coordinated<T>(_ url: URL,read: (URL) throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Swift.Result<T,Error>?
        NSFileCoordinator().coordinate(readingItemAt: url,options: .withoutChanges,error: &coordinationError) { source in result = Swift.Result { try read(source) } }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BackupError.notABackup("File provider did not return a readable file") }
        return try result.get()
    }
}
