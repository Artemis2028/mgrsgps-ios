import Foundation

public struct GuideConfiguration: Codable, Equatable, Sendable {
    public var allowance = 10.0
    public var holdOff = 5.0
    public var heartbeat = 30.0
    public var holdAzimuth = true
    public var corridor = 0.0
    public init() {}
}
public enum GuideCue: String, Equatable, Sendable { case unavailable, onBearing, left, right }
public struct GuideDecision: Equatable, Sendable {
    public let cue: GuideCue
    public let deviation: Double?
    public let outsideCorridor: Bool
    public let changed: Bool
}
/// Direct port of Android release/1.1.0 GuideCueState. No boundary-monitor state.
public struct GuideCueState: Sendable {
    private var cue: GuideCue?
    private var offSince: TimeInterval?
    private var outside = false
    public init() {}
    public static func delta(_ target: Double,_ heading: Double) -> Double { ((target-heading+540).truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)-180 }
    public static func crossTrack(distance: Double,bearing: Double,leg: Double) -> Double { distance * sin(delta(bearing,leg) * .pi/180) }
    public mutating func update(now: TimeInterval,heading: Double?,bearing: Double?,leg: Double?,crossTrack: Double?,distance: Double?,config: GuideConfiguration) -> GuideDecision {
        func valid(_ x: Double?) -> Bool { x?.isFinite == true }
        guard now.isFinite, valid(heading), valid(bearing) else { offSince = nil; outside = false; return emit(.unavailable,nil) }
        let near = valid(distance) && distance! < 100
        let holding = config.holdAzimuth && !near && valid(leg)
        outside = holding && config.corridor > 0 && valid(crossTrack) && abs(crossTrack!) > (outside ? config.corridor * 0.8 : config.corridor)
        let reference: Double
        if outside {
            let intercept = min(60,max(30,config.allowance+15))
            reference = leg! + (crossTrack! > 0 ? -intercept : intercept)
        } else { reference = holding ? leg! : bearing! }
        let deviation = Self.delta(reference,heading!)
        let correcting = cue == .left || cue == .right
        let allowance = max(1,config.allowance)
        let limit = correcting ? allowance-min(3,allowance/3) : allowance
        if abs(deviation) <= limit { offSince = nil; return emit(.onBearing,deviation) }
        if offSince == nil { offSince = now }
        if !correcting && now-offSince! < config.holdOff { return emit(cue == .unavailable ? .onBearing : (cue ?? .onBearing),deviation) }
        return emit(deviation > 0 ? .right : .left,deviation)
    }
    private mutating func emit(_ next: GuideCue,_ deviation: Double?) -> GuideDecision {
        let changed = cue != next; cue = next
        return GuideDecision(cue: next,deviation: deviation,outsideCorridor: outside,changed: changed)
    }
}
public struct NavigationArrivalState: Sendable {
    private var target: String?
    private var alerted = false
    public init() {}
    public mutating func update(target: String,distance: Double?,accuracy: Double?) -> Bool {
        if self.target != target { self.target = target; alerted = false }
        guard let distance, let accuracy, distance.isFinite, distance >= 0, accuracy.isFinite, (0...25).contains(accuracy) else { return false }
        if distance > 150 { alerted = false }
        if !alerted && NavigationFixPolicy.insideArrivalRadius(distanceMeters: distance,accuracyMeters: accuracy) { alerted = true; return true }
        return false
    }
}
public enum NavigationPulse: String, Equatable, Sendable {
    case right, left, unavailable, onCourse, arrival, checkpoint, complete
    case laneLeftCrossing, laneRightCrossing, laneBackstopCrossing, laneReentered, laneOvershot
    public var backgroundNotificationTitle: String? {
        switch self {
        case .arrival: return "Arrived"
        case .checkpoint: return "Route advanced"
        case .complete: return "Route complete"
        case .laneLeftCrossing: return "Past left limit · turn right"
        case .laneRightCrossing: return "Past right limit · turn left"
        case .laneBackstopCrossing: return "Past backstop · turn back"
        case .laneReentered: return "Back inside lane"
        default: return nil
        }
    }
    public var isLaneCrossingEvent: Bool { [.laneLeftCrossing,.laneRightCrossing,.laneBackstopCrossing,.laneReentered].contains(self) }
}
/// Android's four-Hz scheduler, kept separate from playback so unavailable
/// hardware/background suspension cannot change navigation or arrival state.
public struct GuideCadence: Sendable {
    private var next = 0.0
    private var wasCorrecting = false
    public init() {}
    public mutating func pulse(now: TimeInterval,decision: GuideDecision,arrived: Bool,heartbeat: Double) -> NavigationPulse? {
        if decision.changed { next = 0 }
        defer { wasCorrecting = decision.cue == .left || decision.cue == .right }
        if arrived { next = now+1.8; return .arrival }
        if decision.cue == .onBearing {
            if decision.changed && wasCorrecting { next = now+max(heartbeat,0.001); return .onCourse }
            if heartbeat > 0 && now >= next { let play = next != 0; next = now+heartbeat; return play ? .onCourse : nil }
            return nil
        }
        guard now >= next else { return nil }
        let error = abs(decision.deviation ?? 0)
        next = now + (decision.cue == .unavailable ? 4 : (error > 60 ? 0.8 : (error > 25 ? 1.3 : 2)))
        switch decision.cue { case .right: return .right; case .left: return .left; case .unavailable: return .unavailable; case .onBearing: return nil }
    }
}
public struct RouteFollowingProgress: Codable, Equatable, Sendable {
    public let routeID: String
    public let name: String
    public let points: [GeoPoint]
    public var index: Int
    public var paused: Bool
    public var complete: Bool { index >= points.count }
    public init(routeID: String,name: String,points: [GeoPoint],index: Int = 0,paused: Bool = false) {
        self.routeID = routeID; self.name = name; self.points = points; self.index = index; self.paused = paused
    }
    /// Android's course checkpoint threshold, distinct from the guide's 50 m cue.
    public mutating func arrive(distance: Double,accuracy: Double) -> Bool {
        guard !paused, !complete, distance.isFinite, distance >= 0, accuracy.isFinite, (0...25).contains(accuracy), distance+accuracy < 25 else { return false }
        index += 1; return true
    }
}
