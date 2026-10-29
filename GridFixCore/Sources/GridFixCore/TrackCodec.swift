import Foundation

public struct TrackPoint: Equatable, Sendable, Codable {
    public let lat: Double
    public let lon: Double
    /// Milliseconds since epoch; zero means unknown.
    public let time: Int64
    /// MSL height, never ellipsoid height. Nil encodes Android's -32768 sentinel.
    public let altitudeMeters: Double?
    public init(lat: Double, lon: Double, time: Int64 = 0, altitudeMeters: Double? = nil) {
        self.lat = lat; self.lon = lon; self.time = time; self.altitudeMeters = altitudeMeters
    }
}

public enum TrackCodec {
    public static let interchangeByteLimit = ZipArchive.entryLimit
    public struct LocalSummary: Equatable, Sendable {
        public let count: Int
        public let distanceM: Double
        public let last: TrackPoint?
    }

    /// Local logs are independent of the bounded external backup contract.
    /// Statistics validate every row without retaining a second point array.
    public static func summarizeLocal(_ data: Data) throws -> LocalSummary {
        try summarizeLocal(visit: { try visitLocal(data,point: $0) })
    }
    static func summarizeLocal(visit: (_ point: (TrackPoint) throws -> Void) throws -> Void) throws -> LocalSummary {
        var count = 0,distance = 0.0,last: TrackPoint?
        try visit { point in
            if let previous = last {
                distance += Geodesy.navInfo(fromLat: previous.lat,fromLon: previous.lon,toLat: point.lat,toLon: point.lon).distanceMeters
            }
            count += 1; last = point
        }
        return .init(count: count,distanceM: distance,last: last)
    }

    public static func decodeLocal(_ data: Data) throws -> [TrackPoint] {
        var points: [TrackPoint] = []
        try visitLocal(data) { points.append($0) }
        return points
    }

    /// Count actual nonempty rows, never trust stored metadata for preview stride.
    /// The subsequent point visit still validates every coordinate/time/altitude.
    static func countLocalRows(_ data: Data) throws -> Int {
        var count = 0
        try visitLocalRows(data) { _ in count += 1 }
        return count
    }

    static func visitLocal(_ data: Data,point: (TrackPoint) throws -> Void) throws {
        try visitLocalRows(data) { try point(parseLine($0)) }
    }

    private static func visitLocalRows(_ data: Data,row: (Substring) throws -> Void) throws {
        try Task.checkCancellation()
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var start = 0,i = 0
            func consume(_ end: Int) throws {
                guard end > start else { return }
                guard let line = String(bytes: bytes[start..<end],encoding: .utf8) else { throw BackupError.notABackup("Invalid track point file") }
                if line.allSatisfy(\.isWhitespace) { return }
                try row(line[...])
            }
            while i < bytes.count {
                // Preserve the old String.isNewline reader, including legacy
                // Unicode separators; canonical appends still use ASCII LF.
                let length: Int
                if (10...13).contains(bytes[i]) { length = 1 }
                else if bytes[i] == 0xc2,i+1 < bytes.count,bytes[i+1] == 0x85 { length = 2 }
                else if bytes[i] == 0xe2,i+2 < bytes.count,bytes[i+1] == 0x80,(0xa8...0xa9).contains(bytes[i+2]) { length = 3 }
                else { length = 0 }
                if length > 0 { try consume(i); i += length; start = i }
                else { i += 1 }
                if i % 65536 == 0 { try Task.checkCancellation() }
            }
            try consume(bytes.count)
        }
        try Task.checkCancellation()
    }

    /// Incremental local-log reader. Retains only the current row and a chunk;
    /// Unicode newline prefixes and UTF-8 characters may span chunk boundaries.
    struct PointReader {
        private var pending = Data()
        private var offset = 0
        mutating func append(_ chunk: Data,final: Bool = false,point: (TrackPoint) throws -> Void) throws {
            try Task.checkCancellation()
            pending.append(chunk)
            var start = 0,i = offset
            try pending.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                func consume(_ end: Int) throws {
                    guard end > start else { return }
                    guard let line = String(bytes: bytes[start..<end],encoding: .utf8) else {
                        throw BackupError.notABackup("Invalid track point file")
                    }
                    if !line.allSatisfy(\.isWhitespace) { try point(parseLine(line[...])) }
                }
                while i < bytes.count {
                    let length: Int
                    if (10...13).contains(bytes[i]) { length = 1 }
                    else if bytes[i] == 0xc2 {
                        if i+1 == bytes.count && !final { break }
                        length = i+1 < bytes.count && bytes[i+1] == 0x85 ? 2 : 0
                    } else if bytes[i] == 0xe2 {
                        if i+2 >= bytes.count && !final { break }
                        length = i+2 < bytes.count && bytes[i+1] == 0x80 && (0xa8...0xa9).contains(bytes[i+2]) ? 3 : 0
                    } else { length = 0 }
                    if length > 0 { try consume(i); i += length; start = i }
                    else { i += 1 }
                    if i % 65536 == 0 { try Task.checkCancellation() }
                }
                if final { try consume(bytes.count); start = bytes.count; i = bytes.count }
            }
            if start > 0 { pending.removeFirst(start) }
            offset = i-start
            try Task.checkCancellation()
        }
    }

    private static func parseLine(_ line: Substring) throws -> TrackPoint {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard (3...4).contains(parts.count), let lat = Double(parts[0]), let lon = Double(parts[1]),
              let time = Int64(parts[2]), time >= 0,
              let altitude = parts.count == 4 ? Double(parts[3]) : -32768,
              altitude.isFinite, validCoordinates(lat,lon) else { throw BackupError.notABackup("Malformed track point") }
        return TrackPoint(lat: lat,lon: lon,time: time,altitudeMeters: altitude > -32767 ? altitude : nil)
    }
    public static func validID(_ id: String) -> Bool {
        UUID(uuidString: id)?.uuidString.lowercased() == id
    }

    public static func decode(_ data: Data) throws -> [TrackPoint] {
        guard data.count <= interchangeByteLimit, let text = String(data: data, encoding: .utf8) else {
            throw BackupError.notABackup("Invalid track point file")
        }
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard lines.count <= 250_000 else { throw BackupError.notABackup("Too many track points") }
        return try lines.map(parseLine)
    }

    public static func encode(_ points: [TrackPoint]) throws -> Data {
        guard points.count <= 250_000 else { throw BackupError.notABackup("Too many track points") }
        var text = ""
        for point in points {
            guard validCoordinates(point.lat, point.lon), point.time >= 0,
                  point.altitudeMeters?.isFinite ?? true else { throw BackupError.notABackup("Invalid track point") }
            text += String(format: "%.7f %.7f %lld %.1f\n", locale: Locale(identifier: "en_US_POSIX"),
                           point.lat, point.lon, point.time, point.altitudeMeters ?? -32768)
        }
        let result = Data(text.utf8)
        guard result.count <= ZipArchive.entryLimit else { throw BackupError.notABackup("Track file exceeds 16 MB") }
        return result
    }

    public static func distance(_ points: [TrackPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { result, pair in
            result + Geodesy.navInfo(fromLat: pair.0.lat, fromLon: pair.0.lon, toLat: pair.1.lat, toLon: pair.1.lon).distanceMeters
        }
    }

    public static func imported(name: String, points: [TrackPoint], now: Int64,
                                folder: String = "Imported") throws -> (Backup.TrackMeta, Data) {
        let normalized = points.map { TrackPoint(lat: $0.lat, lon: $0.lon, time: max(0, $0.time), altitudeMeters: $0.altitudeMeters) }
        let bytes = try encode(normalized)
        let stored = try decode(bytes)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (Backup.TrackMeta(id: UUID().uuidString.lowercased(), name: trimmed.isEmpty ? "Imported track" : trimmed,
                                 startedAt: stored.first.flatMap { $0.time > 0 ? $0.time : nil } ?? now,
                                 endedAt: stored.last.flatMap { $0.time > 0 ? $0.time : nil } ?? now,
                                 distanceM: distance(stored), pointCount: stored.count, folder: Folders.canonical(folder)), bytes)
    }

    static func validCoordinates(_ lat: Double, _ lon: Double) -> Bool {
        lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
    }
}
