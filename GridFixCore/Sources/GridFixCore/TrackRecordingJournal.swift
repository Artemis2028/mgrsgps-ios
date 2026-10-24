import Foundation

/// A location timestamp translated to uptime at delivery. Core Location has no
/// Android elapsedRealtimeNanos equivalent; the iOS adapter translates a batch
/// with one wall-clock/uptime pair and rejects cached, future, and invalid fixes.
public struct RecordingSample: Sendable {
    public let point: TrackPoint
    public let accuracyMeters: Double
    public let uptime: TimeInterval
    public init(point: TrackPoint, accuracyMeters: Double, uptime: TimeInterval) {
        self.point = point; self.accuracyMeters = accuracyMeters; self.uptime = uptime
    }
}

public struct RecordingSummary: Equatable, Sendable {
    public let id: String
    public let name: String
    public let startedAt: Int64
    public let pointCount: Int
    public let distanceM: Double
    public let livePoints: [GeoPoint]
}

/// Confined to one serial executor by its owner. Each accepted point is synced
/// to an append-only Android-compatible log before statistics are published.
/// The journal survives process death until the finished archive is committed.
public final class TrackRecordingJournal {
    private struct Session: Codable {
        let id: String
        var name: String
        let folder: String
        let startedAt: Int64
        var endedAt: Int64?
    }
    private let directory: URL
    private var metadataURL: URL { directory.appendingPathComponent("session.json") }
    private var logURL: URL { directory.appendingPathComponent("points.txt") }
    private var session: Session?
    private var startedUptime: TimeInterval = 0
    private var lastSample: RecordingSample?
    private var pointCount = 0, byteCount = 0
    private var distance = 0.0
    private var preview: [GeoPoint] = []
    public private(set) var isRecording = false
    public var hasPendingSession: Bool { session != nil }
    public var summary: RecordingSummary? {
        session.map { RecordingSummary(id: $0.id, name: $0.name, startedAt: $0.startedAt,
                                      pointCount: pointCount, distanceM: distance, livePoints: preview) }
    }

    public init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("LiveRecording", isDirectory: true)
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            guard data.count <= 64 * 1024 else { throw BackupError.notABackup("Invalid recording metadata; journal kept") }
            let stored = try JSONDecoder().decode(Session.self, from: data)
            guard TrackCodec.validID(stored.id), stored.startedAt >= 0 else { throw BackupError.notABackup("Invalid recording session; journal kept") }
            session = stored
        }
    }

    @discardableResult
    public func start(now: Int64, uptime: TimeInterval, name: String? = nil, folder: String = Folders.defaultFolder) throws -> RecordingSummary {
        guard session == nil, now >= 0, uptime.isFinite, uptime >= 0 else { throw BackupError.notABackup("Finish or recover the previous recording first") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "ddHHmm'Z'"
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let next = Session(id: UUID().uuidString.lowercased(), name: trimmed.isEmpty ? "Track " + formatter.string(from: Date(timeIntervalSince1970: Double(now) / 1000)) : trimmed,
                           folder: Folders.canonical(folder), startedAt: now)
        try Self.writeProtected(Data(), to: logURL)
        try Self.writeProtected(JSONEncoder().encode(next), to: metadataURL)
        session = next; startedUptime = uptime; isRecording = true
        lastSample = nil; pointCount = 0; byteCount = 0; distance = 0; preview = []
        return summary!
    }

    /// Android: <=30 m accuracy; >=5 m movement, or >15 s and >1 m.
    /// Filtering uses the last *saved* fix. Duplicate/reversed times never append.
    @discardableResult
    public func append(_ sample: RecordingSample) throws -> RecordingSummary? {
        guard isRecording, session != nil else { return nil }
        let p = sample.point
        guard TrackCodec.validCoordinates(p.lat, p.lon), p.time >= 0,
              sample.accuracyMeters.isFinite, (0...30).contains(sample.accuracyMeters),
              sample.uptime.isFinite, sample.uptime >= startedUptime,
              p.altitudeMeters?.isFinite ?? true else { return nil }
        var step = 0.0
        if let last = lastSample {
            let gap = sample.uptime - last.uptime
            guard gap > 0 else { return nil }
            step = Geodesy.navInfo(fromLat: last.point.lat, fromLon: last.point.lon, toLat: p.lat, toLon: p.lon).distanceMeters
            guard step >= 5 || (gap > 15 && step > 1) else { return nil }
        }
        do {
            let bytes = try TrackCodec.encode([p])
            guard pointCount < 250_000, byteCount + bytes.count <= 16 * 1024 * 1024 else {
                throw BackupError.notABackup("Recording reached the supported track size; saved points were kept")
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            let offset = try handle.seekToEnd()
            do {
                try handle.write(contentsOf: bytes)
                try handle.synchronize()
            } catch {
                // Best-effort rollback; recovery also drops an incomplete last row.
                try? handle.truncate(atOffset: offset); try? handle.synchronize()
                throw error
            }
            byteCount += bytes.count; pointCount += 1; distance += step; lastSample = sample
            preview.append(GeoPoint(lat: p.lat, lon: p.lon))
            if preview.count > 4000 { preview = Array(preview.suffix(2000)) }
            return summary
        } catch {
            isRecording = false // queued callbacks cannot append after failure
            throw error
        }
    }

    /// Stops appends, seals metadata, and reconstructs final stats from disk.
    /// On relaunch this closes an interrupted track instead of resuming silently.
    public func finish(now: Int64, name: String? = nil, discardEmpty: Bool = false) throws -> Backup.Document? {
        isRecording = false
        guard var stored = session else { return nil }
        let size = try FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber
        guard let size, size.intValue <= 16 * 1024 * 1024 else { throw BackupError.notABackup("Invalid recording log; journal kept") }
        var data = try Data(contentsOf: logURL)
        if !data.isEmpty, data.last != 10 {
            data = data.lastIndex(of: 10).map { Data(data[...$0]) } ?? Data()
            try Self.writeProtected(data, to: logURL)
        }
        let points = try TrackCodec.decode(data)
        if points.isEmpty && discardEmpty { return nil }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { stored.name = trimmed }
        if stored.endedAt == nil { stored.endedAt = max(now, stored.startedAt, points.last?.time ?? 0) }
        try Self.writeProtected(JSONEncoder().encode(stored), to: metadataURL)
        session = stored
        let meta = Backup.TrackMeta(id: stored.id, name: stored.name, startedAt: stored.startedAt,
                                   endedAt: stored.endedAt!, distanceM: TrackCodec.distance(points), pointCount: points.count, folder: stored.folder)
        var document = Backup.Document(tracks: [meta], trackFiles: [stored.id: data])
        document.hasSettings = false
        try Backup.validate(document)
        return document
    }

    /// Only call after publishing the finished track, or an explicit discard.
    public func clear() throws {
        isRecording = false
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        session = nil; lastSample = nil; preview = []; pointCount = 0; byteCount = 0; distance = 0
    }

    private static func writeProtected(_ data: Data, to url: URL) throws {
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: url, options: options)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}
