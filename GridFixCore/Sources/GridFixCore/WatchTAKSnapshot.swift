import CryptoKit
import Foundation

/// Separate read-only remote scene. Contains no server configuration, credentials or own location.
public struct WatchTAKSnapshot: Codable, Equatable, Sendable {
    public static let contextKey = "gridfix.tak.v1"
    public static let maximumBytes = 8 * 1024
    public static let maximumItems = 64
    public static let maximumVertices = 384
    public static let maximumItemVertices = 128
    public var version = 1
    public var sourceID: String
    public var revision: Int64
    public var at: Int64
    public var enabled: Bool
    public var connected: Bool
    public var omitted = 0
    public var items: [Item] = []

    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var affiliation: String
        public var points: [GeoPoint]
        public var closed: Bool
        public var contact: Bool
        public var expiresAt: Int64
        public init(id: String,name: String,affiliation: String,points: [GeoPoint],closed: Bool = false,contact: Bool = false,expiresAt: Int64) {
            self.id = id; self.name = name; self.affiliation = affiliation; self.points = points
            self.closed = closed; self.contact = contact; self.expiresAt = expiresAt
        }
        public var isValid: Bool {
            id.utf8.count == 64 && id.allSatisfy { "0123456789abcdef".contains($0) }
            && name.utf8.count <= 480 && ["friendly","hostile","neutral","unknown"].contains(affiliation)
            && (1...WatchTAKSnapshot.maximumItemVertices).contains(points.count)
            && points.allSatisfy { WatchMapSnapshot.validCoordinate($0) && ($0.lat != 0 || $0.lon != 0) }
            && (!closed || points.count >= 3) && (!contact || (points.count == 1 && !closed))
            && !WatchMapGeometry.crossesDateline(points,closed:closed)
        }
    }
    public init(sourceID: String,revision: Int64,at: Int64,enabled: Bool,connected: Bool) {
        self.sourceID = sourceID; self.revision = revision; self.at = at
        self.enabled = enabled; self.connected = connected
    }
    public var isValid: Bool {
        version == 1 && !sourceID.isEmpty && sourceID.utf8.count <= 64 && revision >= 0
        && at > 0 && at <= 253_402_300_799_000 && omitted >= 0
        && items.count <= Self.maximumItems && Set(items.map(\.id)).count == items.count
        && items.reduce(0) { $0+$1.points.count } <= Self.maximumVertices
        && (enabled || items.isEmpty)
        && items.allSatisfy { $0.isValid && $0.expiresAt > at && $0.expiresAt-at <= 3_600_000 }
    }
    public func encoded() -> Data? {
        guard isValid,let data = try? JSONEncoder().encode(self),data.count <= Self.maximumBytes else { return nil }
        return data
    }
    public static func decode(_ data: Data) -> Self? {
        guard data.count <= maximumBytes,let value = try? JSONDecoder().decode(Self.self,from:data),value.isValid else { return nil }
        return value
    }
    public func shouldApply(over previous: Self?) -> Bool {
        guard let previous else { return true }
        return previous.sourceID == sourceID ? revision > previous.revision : at >= previous.at
    }
    /// A smaller context budget drops whole items, never a partial drawing.
    public func fitting(bytes: Int) -> Self? {
        guard isValid,bytes >= 256 else { return nil }
        var value = self
        while let encoded = try? JSONEncoder().encode(value),encoded.count > min(bytes,Self.maximumBytes) {
            guard !value.items.isEmpty else { return nil }
            value.items.removeLast(); value.omitted += 1
        }
        return value
    }
    public static func build(_ source: [TAKRemoteItem],enabled: Bool,connected: Bool,date: Date = Date(),sourceID: String,revision: Int64) -> Self {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite,seconds > 0,seconds <= 253_402_300_799 else { return .init(sourceID:sourceID,revision:revision,at:1,enabled:false,connected:false) }
        let at = Int64(seconds*1000)
        var value = Self(sourceID:sourceID,revision:revision,at:at,enabled:enabled,connected:connected)
        guard enabled else { return value }
        var used = 0, ids = Set<String>()
        for remote in source where remote.staleAt > date {
            let expiry = remote.staleAt.timeIntervalSince1970
            guard expiry.isFinite else { value.omitted += 1; continue }
            let id = SHA256.hash(data:Data(remote.id.utf8)).map { String(format:"%02x",$0) }.joined()
            let item = Item(id:id,name:String(remote.callsign.prefix(120)),affiliation:remote.affiliation,points:remote.points,closed:remote.closed,contact:remote.isContact,expiresAt:Int64(min(seconds+3600,expiry)*1000))
            guard value.items.count < maximumItems,item.isValid,item.expiresAt > at,used+item.points.count <= maximumVertices,ids.insert(id).inserted else { value.omitted += 1; continue }
            value.items.append(item)
            if value.encoded() == nil { value.items.removeLast(); value.omitted += 1 }
            else { used += item.points.count }
        }
        return value.fitting(bytes:maximumBytes) ?? Self(sourceID:sourceID,revision:revision,at:at,enabled:enabled,connected:connected)
    }
}

/// In-memory cache with monotonic expiry. Complete replacement and retained expiry
/// deadlines keep reconnect/clock changes from extending unchanged remote items.
public struct WatchTAKScene: Sendable {
    public private(set) var snapshot: WatchTAKSnapshot?
    private struct Entry: Sendable { var item: WatchTAKSnapshot.Item; var deadline: TimeInterval }
    private var values: [String:Entry] = [:]
    private var receipt: (Date,TimeInterval)?
    public init() {}
    public mutating func clear() { snapshot = nil; values = [:]; receipt = nil }
    @discardableResult public mutating func apply(_ incoming: WatchTAKSnapshot,now: Date,uptime: TimeInterval) -> Bool {
        let age = now.timeIntervalSince1970-Double(incoming.at)/1000
        guard incoming.encoded() != nil,incoming.shouldApply(over:snapshot),age.isFinite,age >= -2,uptime.isFinite,uptime >= 0 else { return false }
        var next: [String:Entry] = [:]
        for item in incoming.items {
            let remaining = min(3600,Double(item.expiresAt)/1000-now.timeIntervalSince1970)
            guard remaining > 0 else { continue }
            var deadline = uptime+remaining
            if let prior = values[item.id],item.expiresAt <= prior.item.expiresAt { deadline = min(deadline,prior.deadline) }
            next[item.id] = Entry(item:item,deadline:deadline)
        }
        snapshot = incoming; values = next; receipt = (now,uptime)
        return true
    }
    private struct Cache: Codable {
        var snapshot: WatchTAKSnapshot
        var wall: Date
        var uptime: TimeInterval
        var deadlines: [String:TimeInterval]
    }
    public func encodedCache() -> Data? {
        guard let snapshot,let receipt else { return nil }
        let cache = Cache(snapshot:snapshot,wall:receipt.0,uptime:receipt.1,deadlines:values.mapValues(\.deadline))
        guard let data = try? JSONEncoder().encode(cache),data.count <= 24*1024 else { return nil }
        return data
    }
    public static func decodeCache(_ data: Data) -> Self? {
        guard data.count <= 24*1024,let cache = try? JSONDecoder().decode(Cache.self,from:data),cache.snapshot.encoded() != nil,
              cache.wall.timeIntervalSince1970.isFinite,cache.uptime.isFinite,cache.uptime >= 0,
              cache.deadlines.count <= WatchTAKSnapshot.maximumItems,
              Set(cache.deadlines.keys).isSubset(of:Set(cache.snapshot.items.map(\.id))),
              cache.deadlines.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= cache.uptime+3602 }) else { return nil }
        var scene = Self(); scene.snapshot = cache.snapshot; scene.receipt = (cache.wall,cache.uptime)
        for item in cache.snapshot.items {
            if let deadline = cache.deadlines[item.id] { scene.values[item.id] = Entry(item:item,deadline:deadline) }
        }
        return scene
    }
    public func visible(now: Date,uptime: TimeInterval) -> [WatchTAKSnapshot.Item] {
        guard let snapshot,snapshot.enabled,let receipt,uptime >= receipt.1,
              abs(now.timeIntervalSince(receipt.0)-(uptime-receipt.1)) <= 2 else { return [] }
        return snapshot.items.filter { item in values[item.id].map { uptime < $0.deadline && now.timeIntervalSince1970 < Double(item.expiresAt)/1000 } == true }
    }
}
