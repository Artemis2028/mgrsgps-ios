import CryptoKit
import Foundation

public enum TAKSharing {
    public static let refreshSeconds: TimeInterval = 300
    public struct Item: Equatable, Sendable, Codable {
        public let uid: String
        public let name: String
        public let affiliation: String
        public let points: [GeoPoint]
        public let closed: Bool
        public let creatorUID: String
        public let creatorCallsign: String
        public var signature: String {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return (try? encoder.encode(self)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "invalid"
        }
        public func xml(now: Date) throws -> String {
            if points.count == 1 {
                return try TAKCoT.marker(uid: uid, name: name, affiliation: affiliation, position: points[0], creatorUID: creatorUID, creatorCallsign: creatorCallsign, now: now)
            }
            return try TAKCoT.drawing(uid: uid, name: name, points: points, closed: closed, creatorUID: creatorUID, creatorCallsign: creatorCallsign, now: now)
        }
    }
    public struct Plan: Sendable {
        public let send: [Item]
        public let delete: [String]
    }
    /// The exact Android folder/eye/visibility contract. Unsupported or oversized
    /// drawings are omitted whole, so previously shared geometry gets deleted.
    public static func current(sharedFolders: Set<String>, waypoints: [Waypoint], graphics: [Backup.Graphic], folders: [FolderInfo], uid: String, callsign: String) -> [Item] {
        let hidden = Set(folders.filter { !$0.visible }.map { Folders.canonical($0.name).lowercased() })
        let allowed = Set(sharedFolders.map { Folders.canonical($0).lowercased() }).subtracting(hidden)
        var items: [Item] = []
        for point in waypoints where point.visible && allowed.contains(Folders.canonical(point.folder).lowercased()) {
            let position = GeoPoint(lat: point.lat, lon: point.lon)
            guard TAKCoT.validPosition(position) else { continue }
            items.append(.init(uid: uid + "-wp-" + point.id, name: point.name, affiliation: point.affiliation, points: [position], closed: false, creatorUID: uid, creatorCallsign: callsign))
        }
        for graphic in graphics where graphic.visible && allowed.contains(Folders.canonical(graphic.folder).lowercased()) {
            guard !["ring", "sector", "text"].contains(graphic.type) else { continue }
            let points = graphic.points.map { GeoPoint(lat: $0.lat, lon: $0.lon) }
            let closed = points.count > 1 && GraphicTypes.isArea(graphic.type)
            guard !points.isEmpty, points.count + (closed ? 1 : 0) <= TAKCoT.maximumVertices,
                  points.allSatisfy(TAKCoT.validPosition), !closed || points.count >= 3 else { continue }
            let name = graphic.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? GraphicTypes.label(graphic.type) : graphic.name
            items.append(.init(uid: uid + "-g-" + graphic.id, name: name, affiliation: graphic.affiliation, points: points, closed: closed, creatorUID: uid, creatorCallsign: callsign))
        }
        return items
    }
    public static func plan(current: [Item], sent: [String: String], refreshAll: Bool) -> Plan {
        let ids = Set(current.map(\.uid))
        return .init(send: current.filter { refreshAll || sent[$0.uid] != $0.signature }, delete: sent.keys.filter { !ids.contains($0) }.sorted())
    }
}
