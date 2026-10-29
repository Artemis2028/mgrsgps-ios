import Foundation

/// A locally armed wrist session, independent of phone guidance and the
/// separate quiet-inside perimeter monitor. Process restarts never auto-arm.
public struct WatchLaneSession: Sendable {
    public private(set) var lane: WatchLaneOverlay?
    public private(set) var continuesInBackground = false
    public private(set) var decision: LaneDecision?
    public private(set) var status = "Wrist alerts off"
    private var guide: LaneGuideState?
    private var cadence = LaneCueCadence()
    private var lastBackgroundNotice: LaneState?
    public init() {}
    public var active: Bool { lane != nil }

    public mutating func start(_ lane: WatchLaneOverlay,continueInBackground: Bool = false) throws {
        stop()
        guard lane.isValid else { throw LaneShapeError("This cached lane is invalid") }
        let shape = try LaneShape(leftDrawn: lane.left, rightDrawn: lane.right, backstopDrawn: lane.backstop)
        var config = LaneGuideConfiguration()
        config.notInLaneReminderSeconds = 0
        guide = LaneGuideState(shape: shape, configuration: config)
        self.lane = lane; continuesInBackground = continueInBackground; decision = nil
        cadence = LaneCueCadence(); cadence.cues.insideTick = false; cadence.cues.reminder = false
        status = "Waiting for watch GPS"
    }
    public mutating func stop(_ message: String = "Wrist alerts off") {
        lane = nil; continuesInBackground = false; guide = nil; decision = nil; lastBackgroundNotice = nil; cadence.reset(); status = message
    }
    /// Retain consent/entry only while a real platform background owner exists.
    /// Ordinary foreground-only sessions still require explicit rearming.
    public mutating func leaveForeground(backgroundAvailable: Bool) {
        guard active else { return }
        if !continuesInBackground || !backgroundAvailable { stop("Paused · start wrist alerts again") }
    }
    public mutating func validateScene(_ lanes: [WatchLaneOverlay]) {
        guard let lane else { return }
        if !lanes.contains(lane) { stop("Lane changed · start again") }
    }
    public mutating func invalidateFix() {
        guard active else { return }
        guide?.invalidateFix(); decision = nil; lastBackgroundNotice = nil; cadence.reset(); status = "Waiting for watch GPS"
    }
    /// System notifications provide a background alert where custom watch
    /// haptics are unavailable. One notice per confirmed outside state, quiet
    /// inside/not-yet; another excursion or a fresh post-gap confirmation rearms.
    public mutating func takeBackgroundNotice() -> LaneDecision? {
        guard continuesInBackground,let decision else { return nil }
        guard decision.state != .inside,decision.state != .notYet else { lastBackgroundNotice = nil; return nil }
        guard decision.state != lastBackgroundNotice else { return nil }
        lastBackgroundNotice = decision.state
        return decision
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
        if result.state == .inside || result.state == .notYet { lastBackgroundNotice = nil }
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
