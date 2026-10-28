import Foundation

/// A locally armed foreground wrist session, independent of phone guidance and
/// of the user's separate quiet-inside perimeter monitor. Never auto-resumes.
public struct WatchLaneSession: Sendable {
    public private(set) var lane: WatchLaneOverlay?
    public private(set) var decision: LaneDecision?
    public private(set) var status = "Wrist alerts off"
    private var guide: LaneGuideState?
    private var cadence = LaneCueCadence()
    public init() {}
    public var active: Bool { lane != nil }

    public mutating func start(_ lane: WatchLaneOverlay) throws {
        stop()
        guard lane.isValid else { throw LaneShapeError("This cached lane is invalid") }
        let shape = try LaneShape(leftDrawn: lane.left, rightDrawn: lane.right, backstopDrawn: lane.backstop)
        var config = LaneGuideConfiguration()
        config.notInLaneReminderSeconds = 0
        guide = LaneGuideState(shape: shape, configuration: config)
        self.lane = lane; decision = nil
        cadence = LaneCueCadence(); cadence.cues.insideTick = false; cadence.cues.reminder = false
        status = "Waiting for watch GPS"
    }
    public mutating func stop(_ message: String = "Wrist alerts off") {
        lane = nil; guide = nil; decision = nil; cadence.reset(); status = message
    }
    public mutating func validateScene(_ lanes: [WatchLaneOverlay]) {
        guard let lane else { return }
        if !lanes.contains(lane) { stop("Lane changed · start again") }
    }
    public mutating func invalidateFix() {
        guard active else { return }
        guide?.invalidateFix(); decision = nil; cadence.reset(); status = "Waiting for watch GPS"
    }
    public mutating func update(position: GeoPoint, accuracy: Double, fixTime: TimeInterval,
                                now: TimeInterval, usable: Bool) -> LanePulse? {
        guard let lane, var guide else { return nil }
        guard usable, NavigationFixPolicy.isUsable(lat: position.lat, lon: position.lon, accuracyMeters: accuracy,
                                                   timestampUptime: fixTime, nowUptime: now) else {
            invalidateFix(); return nil
        }
        let result = guide.update(position: position, accuracy: accuracy, fixTime: fixTime)
        self.guide = guide; decision = result
        switch result.state {
        case .notYet: status = "Not in lane yet"
        case .inside: status = "Inside lane"
        case .outLeft: status = "Past \(lane.leftLabel) · turn right"
        case .outRight: status = "Past \(lane.rightLabel) · turn left"
        case .overshot: status = "Past \(lane.backstopLabel) · turn back"
        }
        return cadence.next(decision: result, now: now)
    }
}
