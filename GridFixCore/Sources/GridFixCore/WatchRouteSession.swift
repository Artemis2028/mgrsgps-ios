import Foundation

/// Locally selected complete route; never restores execution consent from cache.
public struct WatchRouteSession: Sendable {
    public private(set) var feature: WatchMapSnapshot.Feature?
    public private(set) var sourceID: String?
    public private(set) var runID: UUID?
    public private(set) var progress: RouteFollowingProgress?
    public private(set) var status = "Route off"
    private var after: TimeInterval = 0
    private var lastFix: TimeInterval = 0
    private var lastNow: TimeInterval = 0
    private var lastSampleID: TimeInterval?
    public init() {}
    public var hasRoute: Bool { feature != nil }
    public var active: Bool { progress.map { !$0.paused && !$0.complete } ?? false }
    public static func canFollow(_ feature: WatchMapSnapshot.Feature) -> Bool {
        var packet = WatchMapSnapshot(); packet.features = [feature]
        return packet.isValid && feature.kind == "graphic" && feature.type == "route"
            && !feature.simplified && feature.originalPointCount == feature.points.count
            && (2...WatchMapSnapshot.maxLinePoints).contains(feature.points.count)
    }
    public var target: WatchSnapshot.Target? {
        guard let feature,let runID,let progress,!progress.complete else { return nil }
        let point = progress.points[progress.index]
        let suffix = "WP\(progress.index+1)", name = feature.name.trimmingCharacters(in:.whitespacesAndNewlines)
        let automatic = name.hasPrefix("RT") && Int(name.dropFirst(2)).map({$0 > 0}) == true
        let label = name.isEmpty ? suffix : automatic ? name+suffix : name+" · "+suffix
        return .init(id:"watch-route:\(runID.uuidString):\(progress.index)",name:label,lat:point.lat,lon:point.lon)
    }
    @discardableResult public mutating func start(_ feature: WatchMapSnapshot.Feature,sourceID: String,now: TimeInterval) -> Bool {
        stop()
        guard Self.canFollow(feature),!sourceID.isEmpty,sourceID.count <= 64,now.isFinite,now > 0 else {
            status = "Choose a complete route"; return false
        }
        self.feature = feature; self.sourceID = sourceID; runID = UUID()
        progress = .init(routeID:feature.id,name:feature.name,points:feature.points)
        after = now; lastNow = now; status = "WP1 of \(feature.points.count)"; return true
    }
    public mutating func stop(_ message: String = "Route off") {
        feature = nil; sourceID = nil; runID = nil; progress = nil
        after = 0; lastFix = 0; lastNow = 0; lastSampleID = nil; status = message
    }
    public mutating func pause() {
        guard var progress,!progress.complete else { return }
        progress.paused = true; self.progress = progress; status = "Paused · resume route"
    }
    @discardableResult public mutating func resume(now: TimeInterval) -> Bool {
        guard var progress,progress.paused,!progress.complete,now.isFinite,now >= lastNow else { return false }
        progress.paused = false; self.progress = progress; after = now; lastNow = now
        status = "WP\(progress.index+1) of \(progress.points.count)"; return true
    }
    public mutating func validateScene(_ scene: WatchMapSnapshot?) {
        guard let feature else { return }
        guard let scene,scene.isValid,scene.sourceID == sourceID,scene.features.contains(feature) else {
            stop("Route changed · choose again"); return
        }
    }
    public mutating func invalidateFix() {
        if active { status = "Waiting for watch GPS" }
    }
    /// One fresh post-Start/Resume fix can advance at most one checkpoint.
    public mutating func update(position: GeoPoint,accuracy: Double,fixTime: TimeInterval,
                                now: TimeInterval,usable: Bool,sampleID: TimeInterval? = nil) -> NavigationPulse? {
        guard active,var progress else { return nil }
        let identity = sampleID ?? fixTime
        // Preserve source ordering independently of wall-time/uptime conversion
        // jitter. An older callback must never revisit coincident checkpoints.
        guard usable,identity.isFinite,lastSampleID.map({ identity > $0 }) ?? true,now >= lastNow,fixTime > after,fixTime > lastFix,
              NavigationFixPolicy.isUsable(lat:position.lat,lon:position.lon,accuracyMeters:accuracy,
                                          timestampUptime:fixTime,nowUptime:now) else { invalidateFix(); return nil }
        lastFix = fixTime; lastNow = now; lastSampleID = identity
        let point = progress.points[progress.index]
        let nav = Geodesy.navInfo(fromLat:position.lat,fromLon:position.lon,toLat:point.lat,toLon:point.lon)
        let advanced = progress.arrive(distance:nav.distanceMeters,accuracy:accuracy)
        self.progress = progress
        status = progress.complete ? "Route complete" : "WP\(progress.index+1) of \(progress.points.count)"
        return advanced ? (progress.complete ? .complete : .checkpoint) : nil
    }
}
