import CryptoKit
import Foundation

/// A value capture of one immutable local log, not an open handle or cached
/// point array. Read on a worker; every use checks provenance and exact bytes.
public struct SavedTrackSource: Equatable, Sendable {
    let fileURL: URL
    let sha256: String
    private let stamp: FieldDataReadSource.Stamp
    private let verification = Verification()
    public var byteCount: UInt64 { stamp.size }
    var hasVerifiedBytes: Bool { verification.valid }
    public static func == (lhs: Self,rhs: Self) -> Bool {
        lhs.fileURL == rhs.fileURL && lhs.sha256 == rhs.sha256 && lhs.stamp == rhs.stamp
    }
    private final class Verification: @unchecked Sendable {
        private let lock = NSLock()
        private var readers = 0,verified = false
        var valid: Bool { lock.lock(); defer { lock.unlock() }; return readers == 0 && verified }
        func begin() { lock.lock(); readers += 1; verified = false; lock.unlock() }
        func end(success: Bool) { lock.lock(); readers -= 1; verified = success && readers == 0; lock.unlock() }
    }

    init(fileURL: URL,sha256: String) throws {
        guard let stamp = try FieldDataReadSource.Stamp.read(fileURL) else {
            throw BackupError.notABackup("Saved track file is missing; the saved library was kept")
        }
        self.fileURL = fileURL; self.sha256 = sha256; self.stamp = stamp
    }
    func validate() throws {
        guard (try? FieldDataReadSource.Stamp.read(fileURL)) == stamp else {
            throw BackupError.notABackup("Saved track file changed or is missing; original files were kept. Reopen the app and try again.")
        }
    }
    public func read(maximumBytes: Int? = nil) throws -> Data {
        try Task.checkCancellation()
        if let maximumBytes,maximumBytes < 0 || byteCount > UInt64(maximumBytes) {
            throw BackupError.notABackup("Saved track exceeds this format's supported size limit")
        }
        verification.begin()
        do {
            try validate()
            // Own requested bytes; later file writes cannot mutate the snapshot.
            let bytes = try Data(contentsOf:fileURL)
            try validate()
            guard FieldDataDisk.digest(bytes) == sha256 else {
                throw BackupError.notABackup("Saved track checksum failed; original data was kept")
            }
            try Task.checkCancellation()
            verification.end(success:true)
            return bytes
        } catch {
            verification.end(success:false)
            throw error
        }
    }

    /// Results must remain worker-local until this returns successfully: the
    /// final checksum/stamp validates every byte, including unsampled rows.
    public func visitPoints(_ point: (TrackPoint) throws -> Void) throws {
        try visitPoints(chunkSize: 64 * 1024,point: point)
    }
    func visitPoints(chunkSize: Int,point: (TrackPoint) throws -> Void) throws {
        precondition(chunkSize > 0)
        try Task.checkCancellation()
        verification.begin()
        do {
            try validate()
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            var reader = TrackCodec.PointReader(),hash = SHA256(),total: UInt64 = 0
            while let chunk = try handle.read(upToCount: chunkSize),!chunk.isEmpty {
                try Task.checkCancellation()
                guard total <= byteCount,UInt64(chunk.count) <= byteCount-total else {
                    throw BackupError.notABackup("Saved track file changed; original data was kept")
                }
                total += UInt64(chunk.count); hash.update(data: chunk)
                try reader.append(chunk,point: point)
            }
            try reader.append(Data(),final: true,point: point)
            try validate()
            guard total == byteCount,hash.finalize().map({ String(format:"%02x",$0) }).joined() == sha256 else {
                throw BackupError.notABackup("Saved track checksum failed; original data was kept")
            }
            try Task.checkCancellation()
            verification.end(success: true)
        } catch {
            verification.end(success: false)
            throw error
        }
    }
}

extension Backup.Document {
    /// Streaming local source or eager imported bytes, with identical strict
    /// row validation. Callers publish their derived result only after success.
    public func visitTrackPoints(_ id: String,point: (TrackPoint) throws -> Void) throws {
        if let bytes = trackFiles[id] { try TrackCodec.visitLocal(bytes,point: point) }
        else if let source = localTrackFiles[id] { try source.visitPoints(point) }
        else { try TrackCodec.visitLocal(trackData(id),point: point) }
    }
    /// A missing nonempty log is an error, never a fabricated empty export,
    /// backtrack, map preview or restored track. Local sources stay off the wire.
    public func trackData(_ id: String,maximumBytes: Int? = nil) throws -> Data {
        if let bytes = trackFiles[id] {
            if let maximumBytes,bytes.count > maximumBytes {
                throw BackupError.notABackup("Track exceeds this format's supported size limit")
            }
            return bytes
        }
        if let source = localTrackFiles[id] { return try source.read(maximumBytes:maximumBytes) }
        guard tracks.first(where:{ $0.id == id })?.pointCount == 0 else {
            throw BackupError.notABackup("Saved track points are missing; original files were kept")
        }
        return Data()
    }
    /// External backup limits can reject an oversized source before reading it.
    func materializedForBackup() throws -> Self {
        let ids = Set(tracks.map(\.id))
        guard Set(trackFiles.keys).union(localTrackFiles.keys).isSubset(of:ids) else {
            throw BackupError.notABackup("Track file is missing from manifest")
        }
        var result = self
        var total = 0
        for track in tracks {
            try Task.checkCancellation()
            let bytes = try trackData(track.id,maximumBytes:ZipArchive.entryLimit)
            guard total <= ZipArchive.totalLimit-bytes.count else {
                throw BackupError.notABackup("Backup exceeds supported size limits")
            }
            total += bytes.count; result.trackFiles[track.id] = bytes
        }
        result.localTrackFiles = [:]
        return result
    }
}
