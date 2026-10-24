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
    public static func validID(_ id: String) -> Bool {
        UUID(uuidString: id)?.uuidString.lowercased() == id
    }

    public static func decode(_ data: Data) throws -> [TrackPoint] {
        guard data.count <= ZipArchive.entryLimit, let text = String(data: data, encoding: .utf8) else {
            throw BackupError.notABackup("Invalid track point file")
        }
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard lines.count <= 250_000 else { throw BackupError.notABackup("Too many track points") }
        return try lines.map { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard (3...4).contains(parts.count), let lat = Double(parts[0]), let lon = Double(parts[1]),
                  let time = Int64(parts[2]), time >= 0,
                  let altitude = parts.count == 4 ? Double(parts[3]) : -32768,
                  altitude.isFinite, validCoordinates(lat, lon) else { throw BackupError.notABackup("Malformed track point") }
            return TrackPoint(lat: lat, lon: lon, time: time, altitudeMeters: altitude > -32767 ? altitude : nil)
        }
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
