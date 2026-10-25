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
