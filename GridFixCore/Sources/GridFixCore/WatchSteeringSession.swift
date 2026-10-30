import Foundation

/// Foreground-only local consent. Target and sensors are independent of phone guidance.
public struct WatchSteeringSession: Sendable {
    public private(set) var target: WatchSnapshot.Target?
    public private(set) var decision: GuideDecision?
    public private(set) var status = "Steering off"
    private var guide = GuideCueState()
    private var cadence = GuideCadence()
    private var arrival = NavigationArrivalState()
    private var lastTime: TimeInterval?
    public init() {}
    public var active: Bool { target != nil }
    @discardableResult public mutating func start(_ target: WatchSnapshot.Target) -> Bool {
        stop()
        guard WatchSnapshot(target:target).isValid else { status = "Invalid target"; return false }
        self.target = target; status = "Waiting for watch sensors"; return true
    }
    public mutating func stop(_ message: String = "Steering off") {
        target = nil; decision = nil; status = message
        guide = GuideCueState(); cadence = GuideCadence(); arrival = NavigationArrivalState(); lastTime = nil
    }
    public mutating func validateTarget(_ selected: WatchSnapshot.Target?) {
        if let target, target != selected { stop("Target changed · start again") }
    }
    public mutating func invalidateSensors() {
        guard active else { return }
        decision = nil; guide = GuideCueState(); cadence = GuideCadence()
        status = "Waiting for watch GPS and compass"
    }
    public mutating func update(position: GeoPoint,accuracy: Double,fixTime: TimeInterval,
                                heading: WatchHeadingSample?,now: TimeInterval,usable: Bool) -> NavigationPulse? {
        guard let target else { return nil }
        guard usable, now.isFinite, lastTime.map({ now >= $0 }) ?? true,
              NavigationFixPolicy.isUsable(lat:position.lat,lon:position.lon,accuracyMeters:accuracy,
                                          timestampUptime:fixTime,nowUptime:now),
              let heading,heading.isFreshForSteering(nowUptime:now) else { invalidateSensors(); return nil }
        lastTime = now
        let nav = Geodesy.navInfo(fromLat:position.lat,fromLon:position.lon,toLat:target.lat,toLon:target.lon)
        let arrived = arrival.update(target:target.id,distance:nav.distanceMeters,accuracy:accuracy)
        if NavigationFixPolicy.insideArrivalRadius(distanceMeters:nav.distanceMeters,accuracyMeters:accuracy) {
            decision = nil; guide = GuideCueState(); cadence = GuideCadence(); status = "Arrived"
            return arrived ? .arrival : nil
        }
        var config = GuideConfiguration(); config.holdAzimuth = false; config.heartbeat = 0
        let next = guide.update(now:now,heading:heading.trueDegrees,bearing:nav.bearingTrue,
                                leg:nil,crossTrack:nil,distance:nav.distanceMeters,config:config)
        decision = next
        switch next.cue {
        case .left: status = "Turn left"
        case .right: status = "Turn right"
        case .onBearing: status = abs(next.deviation ?? 0) > config.allowance ? "Confirming turn" : "On bearing"
        case .unavailable: status = "Waiting for watch sensors"
        }
        return cadence.pulse(now:now,decision:next,arrived:false,heartbeat:0)
    }
}
