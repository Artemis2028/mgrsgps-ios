import Foundation
import GridFixCore

@MainActor
enum InterchangeCoordinator {
    struct Result {
        var completed: Bool
        var message: String
    }

    /// Android imports commit tracks, then waypoints/folders, then graphics.
    /// Each phase is atomic; stable content IDs make a retry additive.
    static func apply(_ document: Backup.Document, waypoints: WaypointStore, field: FieldDataStore) -> Result {
        var saved: [String] = []
        do {
            try Backup.validate(document)
            if !document.tracks.isEmpty {
                var tracks = Backup.Document(); tracks.hasSettings = false
                tracks.tracks = document.tracks; tracks.trackFiles = document.trackFiles
                let count = try field.restore(tracks).tracks
                if count > 0 { saved.append("\(count) tracks") }
            }
            if !document.waypoints.isEmpty || !document.folders.isEmpty {
                let count = try waypoints.restore(waypoints: document.waypoints,folders: document.folders)
                if count > 0 { saved.append("\(count) waypoints") }
            }
            if !document.graphics.isEmpty {
                var graphics = Backup.Document(); graphics.hasSettings = false; graphics.graphics = document.graphics
                let count = try field.restore(graphics).graphics
                if count > 0 { saved.append("\(count) graphics/routes") }
            }
            return .init(completed: true,message: saved.isEmpty ? "Nothing new to import. Existing records kept." : "Imported " + saved.joined(separator: ", "))
        } catch {
            let progress = saved.isEmpty ? "No records added." : "Already imported: " + saved.joined(separator: ", ") + "."
            return .init(completed: false,message: "Import stopped: \(error.localizedDescription). \(progress) Retry this unchanged file to finish without duplicates.")
        }
    }
}

/// Bounds the read itself, including files whose provider reports no byte size.
/// Coordination and parsing run off the UI thread. No persistence happens here.
enum InterchangeFileReader {
    /// Parse while coordinated access is still held. Mapping avoids duplicating
    /// a large archive container; decoded members are visited one at a time.
    static func preview(_ url: URL,format: TextInterchangeFormat?,knownFolders: [String]) throws -> InterchangePreview {
        try coordinated(url) { source in
            let limit = format?.byteLimit ?? TextInterchange.fileLimit(filename: url.lastPathComponent)
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            guard try handle.seekToEnd() <= UInt64(limit) else { throw BackupError.notABackup("File exceeds \(limit/(1024*1024)) MB") }
            try Task.checkCancellation()
            let bytes = try Data(contentsOf: source,options: .mappedIfSafe)
            guard bytes.count <= limit else { throw BackupError.notABackup("File exceeds \(limit/(1024*1024)) MB") }
            return try TextInterchange.preview(bytes,format: format,filename: url.lastPathComponent,knownFolders: knownFolders)
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
