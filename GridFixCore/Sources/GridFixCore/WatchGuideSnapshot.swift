import Foundation

/// Read-only phone guidance. Never drives watch GPS, crossing detection or haptics.
public struct WatchGuideSnapshot: Codable, Equatable, Sendable {
    public static let contextKey = "gridfix.guide.v1"
    public static let lifetime: Double = 20
    public var version = 1
    public var sourceID: String
    public var revision: Int64
    public var at: Int64
    public var active: Bool
    public var available: Bool
    public var targetName: String?
    public var status: String
    public var laneName: String?
    public var laneState: String?
    public var crossedLine: String?

    public init(sourceID: String, revision: Int64, at: Int64, active: Bool, available: Bool = false,
                targetName: String? = nil, status: String = "Phone guide off", laneName: String? = nil,
                laneState: String? = nil, crossedLine: String? = nil) {
        self.sourceID = sourceID; self.revision = revision; self.at = at; self.active = active
        self.available = available; self.targetName = targetName; self.status = status
        self.laneName = laneName; self.laneState = laneState; self.crossedLine = crossedLine
    }
    public var isValid: Bool {
        version == 1 && !sourceID.isEmpty && sourceID.utf8.count <= 64 && revision >= 0 && at > 0
        && status.utf8.count <= 640
        && [targetName,laneName,crossedLine].allSatisfy { ($0?.utf8.count ?? 0) <= 480 }
        && (laneState.map { ["NOT_YET","INSIDE","OUT_LEFT","OUT_RIGHT","OVERSHOT"].contains($0) } ?? true)
        && ((laneName == nil) == (laneState == nil))
        && (!available || active) && (!active || targetName?.isEmpty == false)
        && (active || (targetName == nil && laneName == nil && crossedLine == nil))
    }
    public static func decode(_ data: Data) -> Self? {
        guard data.count <= 4096, let value = try? JSONDecoder().decode(Self.self,from: data), value.isValid else { return nil }
        return value
    }
    public func shouldApply(over cached: Self?) -> Bool {
        guard let cached else { return true }
        if sourceID != cached.sourceID { return at >= cached.at }
        return revision > cached.revision || (revision == cached.revision && self == cached)
    }
    public func isFresh(at date: Date) -> Bool {
        let age = date.timeIntervalSince1970 - Double(at)/1000
        return age.isFinite && age >= -2 && age <= Self.lifetime
    }
    public func displayStatus(at date: Date) -> String {
        guard isFresh(at: date) else { return "Phone guidance expired · open phone" }
        guard active else { return "Phone guide off" }
        guard available else { return "Phone guidance unavailable" }
        return status
    }
}

/// Receipt-bound lifetime for read-only phone decisions. Replaying an unchanged
/// timestamp cannot renew guidance; wall-clock changes cannot extend its budget.
public struct WatchGuideScene: Sendable {
    public private(set) var snapshot: WatchGuideSnapshot?
    private var receiptWall: Date?
    private var receiptUptime: TimeInterval?
    private var deadline: TimeInterval?
    public init() {}
    public static func legacy(_ snapshot: WatchGuideSnapshot) -> Self {
        var value = Self(); if snapshot.isValid { value.snapshot = snapshot }; return value
    }
    public mutating func clear() { self = Self() }
    @discardableResult public mutating func apply(_ incoming: WatchGuideSnapshot,now: Date,uptime: TimeInterval) -> Bool {
        let age = now.timeIntervalSince1970-Double(incoming.at)/1000
        guard incoming.isValid,incoming.shouldApply(over: snapshot),age.isFinite,age >= -2,
              uptime.isFinite,uptime >= 0,uptime <= Double.greatestFiniteMagnitude-22 else { return false }
        // Legacy caches have no trustworthy receipt. Keep their ordering but
        // wait for a newer packet instead of re-anchoring an identical replay.
        if incoming == snapshot,receiptUptime == nil { return false }
        var nextDeadline = uptime+max(0,min(WatchGuideSnapshot.lifetime,WatchGuideSnapshot.lifetime-age))
        if let prior = snapshot, incoming.at <= prior.at,let deadline { nextDeadline = min(nextDeadline,deadline) }
        snapshot = incoming; receiptWall = now; receiptUptime = uptime; deadline = nextDeadline
        return true
    }
    public func isFresh(now: Date,uptime: TimeInterval) -> Bool {
        guard let snapshot,let receiptWall,let receiptUptime,let deadline,
              now.timeIntervalSince1970.isFinite,uptime.isFinite,uptime >= receiptUptime,
              abs(now.timeIntervalSince(receiptWall)-(uptime-receiptUptime)) <= 2,
              uptime < deadline else { return false }
        return snapshot.isFresh(at: now)
    }
    public func displayStatus(now: Date,uptime: TimeInterval) -> String {
        guard isFresh(now: now,uptime: uptime),let snapshot else { return "Phone guidance expired · open phone" }
        return snapshot.displayStatus(at: now)
    }
    private struct Cache: Codable {
        let snapshot: WatchGuideSnapshot
        let wall: Date
        let uptime: TimeInterval
        let deadline: TimeInterval
    }
    public func encodedCache() -> Data? {
        guard let snapshot,let receiptWall,let receiptUptime,let deadline,
              let bytes = try? JSONEncoder().encode(Cache(snapshot: snapshot,wall: receiptWall,uptime: receiptUptime,deadline: deadline)),bytes.count <= 8192 else { return nil }
        return bytes
    }
    public static func decodeCache(_ data: Data) -> Self? {
        guard data.count <= 8192,let cache = try? JSONDecoder().decode(Cache.self,from: data),cache.snapshot.isValid,
              cache.wall.timeIntervalSince1970.isFinite,cache.uptime.isFinite,cache.uptime >= 0,
              cache.deadline.isFinite,cache.deadline >= 0,cache.deadline <= cache.uptime+WatchGuideSnapshot.lifetime else { return nil }
        var value = Self(); value.snapshot = cache.snapshot; value.receiptWall = cache.wall
        value.receiptUptime = cache.uptime; value.deadline = cache.deadline
        return value
    }
}
