import CryptoKit
import Foundation

/// Parsed geographic content before destination-folder matching or persistence.
/// Identity follows Android ImportCoordinator's gridfix-import-v1 byte contract.
public struct InterchangeContents: Sendable {
    public struct Shape: Sendable {
        public var name: String
        public var folder: String
        public var points: [GeoPoint]
        public init(name: String,folder: String = "Imported",points: [GeoPoint]) { self.name = name; self.folder = folder; self.points = points }
    }
    public var waypoints: [WaypointDraft] = []
    public var lines: [Shape] = []
    public var areas: [Shape] = []
    public var tracks: [GPX.Track] = []
    public var skipped = 0
    public init() {}
    public var isEmpty: Bool { waypoints.isEmpty && lines.isEmpty && areas.isEmpty && tracks.isEmpty }

    public func document(now: Int64 = Int64(Date().timeIntervalSince1970*1000),knownFolders: [String] = []) throws -> Backup.Document {
        guard now >= 0, waypoints.count <= 10_000, lines.count+areas.count <= 10_000, tracks.count <= 10_000,
              lines.reduce(0,{ $0+$1.points.count })+areas.reduce(0,{ $0+$1.points.count }) <= 250_000,
              tracks.reduce(0,{ $0+$1.points.count }) <= 250_000 else { throw BackupError.notABackup("Interchange record/point limit exceeded") }
        let namespace = fingerprint()
        var result = Backup.Document(); result.hasSettings = false
        var names = knownFolders, importedFolders: [String] = []
        func folder(_ raw: String) -> String {
            let name = Folders.match(known: names,raw: raw)
            if !names.contains(name) { names.append(name) }
            if !importedFolders.contains(name) { importedFolders.append(name) }
            return name
        }
        for (index,draft) in waypoints.enumerated() {
            guard TrackCodec.validCoordinates(draft.lat,draft.lon), draft.rotation.isFinite, Float(draft.rotation).isFinite,
                  draft.metadata?.elevationMeters?.isFinite != false else { throw BackupError.notABackup("Invalid imported waypoint") }
            result.waypoints.append(.init(id: Self.id(namespace,"waypoint",index),name: draft.name,lat: draft.lat,lon: draft.lon,
                                         createdAt: now,folder: folder(draft.folder),symbol: draft.symbol.isEmpty ? "flag" : draft.symbol,
                                         affiliation: draft.affiliation,echelon: draft.echelon,designation: draft.designation,kind: draft.kind,
                                         rotation: draft.rotation,metadata: draft.metadata ?? .init()))
        }
        for (kind,shapes,type) in [("line",lines,"route"),("area",areas,"aa")] {
            for (index,shape) in shapes.enumerated() {
                guard shape.points.count >= GraphicTypes.minPoints(type), shape.points.allSatisfy({ TrackCodec.validCoordinates($0.lat,$0.lon) }) else { throw BackupError.notABackup("Invalid imported \(kind)") }
                result.graphics.append(.init(id: Self.id(namespace,kind,index),name: shape.name.trimmingCharacters(in: .whitespacesAndNewlines),type: type,
                                             points: shape.points.map { .init(lat: $0.lat,lon: $0.lon) },folder: folder(shape.folder),createdAt: now))
            }
        }
        for (index,track) in tracks.enumerated() {
            let (original,bytes) = try TrackCodec.imported(name: track.name,points: track.points,now: now,folder: folder(Folders.defaultFolder))
            var info = original; info.id = Self.id(namespace,"track",index)
            result.tracks.append(info); result.trackFiles[info.id] = bytes
        }
        result.folders = importedFolders.map { FolderInfo(name: $0) }
        try Backup.validate(result)
        return result
    }
    private static func id(_ namespace: String,_ kind: String,_ ordinal: Int) -> String {
        var bytes = Array(Insecure.MD5.hash(data: Data("gridfix-import-v1:\(namespace):\(kind):\(ordinal)".utf8)))
        bytes[6] = (bytes[6]&0x0f)|0x30; bytes[8] = (bytes[8]&0x3f)|0x80
        let uuid = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        return uuid.uuidString.lowercased()
    }
    func fingerprint() -> String {
        var out = ImportIdentityWriter()
        out.string("gridfix-import-v1"); out.int(waypoints.count)
        for w in waypoints {
            out.string(w.name); out.double(w.lat); out.double(w.lon); out.string(w.folder); out.string(w.symbol)
            out.string(w.affiliation); out.string(w.echelon); out.string(w.designation); out.string(w.kind)
            out.integer(Float(w.rotation).bitPattern)
            out.bool(w.metadata != nil)
            if let m = w.metadata {
                out.bool(m.color != nil); if let v = m.color { out.string(v) }
                out.bool(m.milgpsSymbolCode != nil); if let v = m.milgpsSymbolCode { out.int(v) }
                out.bool(m.elevationMeters != nil); if let v = m.elevationMeters { out.double(v) }
                out.bool(m.timestampMillis != nil); if let v = m.timestampMillis { out.integer(UInt64(bitPattern: v)) }
            }
        }
        for shapes in [lines,areas] {
            out.int(shapes.count)
            for shape in shapes {
                out.string(shape.name); out.string(shape.folder); out.int(shape.points.count)
                for p in shape.points { out.double(p.lat); out.double(p.lon) }
            }
        }
        out.int(tracks.count)
        for track in tracks {
            out.string(track.name); out.int(track.points.count)
            for p in track.points { out.double(p.lat); out.double(p.lon); out.integer(UInt64(bitPattern: p.time)); out.double(p.altitudeMeters ?? -32768) }
        }
        return out.finish()
    }
}

private struct ImportIdentityWriter {
    var digest = SHA256()
    mutating func bool(_ value: Bool) { digest.update(data: Data([value ? 1 : 0])) }
    mutating func integer<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        withUnsafeBytes(of: &big) { digest.update(data: Data($0)) }
    }
    mutating func int(_ value: Int) { integer(Int32(clamping: value)) }
    mutating func double(_ value: Double) { integer(value.isNaN ? 0x7ff8000000000000 as UInt64 : value.bitPattern) }
    mutating func string(_ value: String) { let bytes = Data(value.utf8); int(bytes.count); digest.update(data: bytes) }
    mutating func finish() -> String { digest.finalize().map { String(format: "%02x",$0) }.joined() }
}
