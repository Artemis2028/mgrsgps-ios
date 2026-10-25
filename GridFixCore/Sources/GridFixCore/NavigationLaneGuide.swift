import Foundation

public enum LaneState: String, Equatable, Sendable { case notYet, inside, outLeft, outRight, overshot }
public struct LaneGuideConfiguration: Equatable, Sendable {
    public var marginMeters = 5.0
    public var returnMeters = 3.0
    public var fixesToConfirm = 2
    public var warningMeters = 0.0
    public var maxAccuracyMeters = 50.0
    public var notInLaneReminderSeconds = 300.0
    public init() {}
}
public struct LaneDecision: Equatable, Sendable {
    public let state: LaneState
    public let changed: Bool
    public let backInside: Bool
    public let warning: LaneLimit?
    public let reading: LaneReading?
    public var reminder = false
}

/// Pushed Android 1.2 lane policy. Fix timestamps and cadence times use seconds.
/// The separate perimeter monitor never consumes this state or its approach cues.
public struct LaneGuideState: Sendable {
    public private(set) var state: LaneState = .notYet
    public var configuration: LaneGuideConfiguration
    private let shape: LaneShape
    private var lastFixTime: TimeInterval?
    private var waitingSince: TimeInterval?
    private var lastReminder: TimeInterval?
    private var pending: LaneState?
    private var pendingCount = 0
    private var reading: LaneReading?
    private var warned: Set<LaneLimit> = []
    private var warningPending: LaneLimit?
    private var warningCount = 0
    public init(shape: LaneShape,configuration: LaneGuideConfiguration = .init()) {
        self.shape = shape; self.configuration = configuration
    }
    public mutating func invalidateFix() { pending = nil; pendingCount = 0; warningPending = nil; warningCount = 0 }
    public mutating func update(position: GeoPoint,accuracy: Double,fixTime: TimeInterval) -> LaneDecision {
        if !fixTime.isFinite || lastFixTime.map({ fixTime <= $0 }) == true { return decision() }
        lastFixTime = fixTime
        if waitingSince == nil { waitingSince = fixTime }
        let reminder = reminderDue(fixTime)
        if configuration.warningMeters <= 0 { warned.removeAll() }
        guard accuracy.isFinite && accuracy >= 0 && accuracy <= configuration.maxAccuracyMeters,
              position.lat.isFinite && position.lon.isFinite && abs(position.lat) <= 90 && abs(position.lon) <= 180 else {
            pending = nil; pendingCount = 0; warningPending = nil; warningCount = 0
            return decision(reminder: reminder)
        }
        let now = shape.read(position)
        reading = now
        let target: LaneState = state == .notYet ? (clearlyInside(now) ? .inside : .notYet) : targetState(now,accuracy)
        var changed = false, backInside = false
        if target == state { pending = nil; pendingCount = 0 }
        else {
            if pending == target { pendingCount += 1 } else { pending = target; pendingCount = 1 }
            if pendingCount >= max(1,configuration.fixesToConfirm) {
                backInside = target == .inside; state = target; changed = true
                pending = nil; pendingCount = 0; warningPending = nil; warningCount = 0
            }
        }
        let warning = state == .inside && !changed ? warningFor(now) : nil
        return .init(state: state,changed: changed,backInside: backInside,warning: warning,reading: now,reminder: reminder)
    }
    private func decision(reminder: Bool = false) -> LaneDecision { .init(state: state,changed: false,backInside: false,warning: nil,reading: reading,reminder: reminder) }
    private func clearlyInside(_ r: LaneReading) -> Bool {
        guard let left=r.left,let right=r.right else { return false }
        return left < -configuration.returnMeters && right < -configuration.returnMeters && (r.backstop ?? -1) < -configuration.returnMeters
    }
    private mutating func reminderDue(_ time: TimeInterval) -> Bool {
        let every=configuration.notInLaneReminderSeconds
        guard state == .notYet,every.isFinite,every>0,let since=waitingSince,time-(lastReminder ?? since)>=every else { return false }
        lastReminder=time;return true
    }
    private func targetState(_ r: LaneReading,_ accuracy: Double) -> LaneState {
        func past(_ limit: LaneLimit) -> Bool { r[limit].map { $0 > configuration.marginMeters+accuracy } ?? false }
        func stillPast(_ limit: LaneLimit) -> Bool { r[limit].map { $0 > -configuration.returnMeters } ?? false }
        let crossed: LaneLimit?
        switch state { case .inside,.notYet: crossed = nil; case .outLeft: crossed = .left; case .outRight: crossed = .right; case .overshot: crossed = .backstop }
        if past(.backstop) || (crossed == .backstop && stillPast(.backstop)) { return .overshot }
        if crossed == .left && stillPast(.left) { return .outLeft }
        if crossed == .right && stillPast(.right) { return .outRight }
        let l = past(.left) ? r.left : nil, right = past(.right) ? r.right : nil
        if let l, let right { return l >= right ? .outLeft : .outRight }
        if l != nil { return .outLeft }; if right != nil { return .outRight }
        return .inside
    }
    private mutating func warningFor(_ r: LaneReading) -> LaneLimit? {
        let band = configuration.warningMeters
        guard band > 0 else { return nil }
        for limit in LaneLimit.allCases {
            if let distance = r[limit], warned.contains(limit), distance < -(band+10) { warned.remove(limit) }
        }
        var nearest: LaneLimit?, nearestDistance = -Double.infinity
        for limit in LaneLimit.allCases where !warned.contains(limit) {
            if let distance = r[limit], distance > -band, distance > nearestDistance { nearest = limit; nearestDistance = distance }
        }
        guard let nearest else { warningPending = nil; warningCount = 0; return nil }
        if warningPending == nearest { warningCount += 1 } else { warningPending = nearest; warningCount = 1 }
        guard warningCount >= max(1,configuration.fixesToConfirm) else { return nil }
        warned.insert(nearest); warningPending = nil; warningCount = 0
        return nearest
    }
}

public enum LanePulse: Equatable, Sendable {
    case turnRight, turnLeft, overshot, backInside, notInLane
    /// Android timing contract in milliseconds, alternating pause/pulse.
    /// Playback remains platform-specific; this does not promise locked-screen haptics.
    public var waveform: [Int] {
        switch self {
        case .turnRight: return [0,70,90,70]
        case .turnLeft: return [0,300]
        case .overshot: return [0,300,200,300,200,300]
        case .backInside: return [0,50]
        case .notInLane: return [0,300,150,80,150,300]
        }
    }
    static func warning(_ limit: LaneLimit) -> Self {
        switch limit { case .left: return .turnRight; case .right: return .turnLeft; case .backstop: return .overshot }
    }
}
public struct LaneCues: Equatable, Sendable {
    public var sides = true
    public var backstop = true
    public var insideTick = true
    public var reminder = true
    public init() {}
}
public struct LaneCueCadence: Sendable {
    public var cues = LaneCues()
    private var nextAt = 0.0
    public init() {}
    public mutating func reset() { nextAt = 0 }
    public mutating func next(decision: LaneDecision,now: TimeInterval) -> LanePulse? {
        guard now.isFinite else { return nil }
        if decision.backInside { nextAt = 0; return cues.insideTick ? .backInside : nil }
        if decision.reminder { return cues.reminder ? .notInLane : nil }
        let enabled: Bool
        switch decision.state {
        case .outLeft,.outRight: enabled=cues.sides
        case .overshot: enabled=cues.backstop
        case .inside,.notYet: enabled=true
        }
        if !enabled { nextAt=0;return decision.warning.map(LanePulse.warning) }
        let pulse: LanePulse
        switch decision.state {
        case .inside,.notYet: nextAt = 0; return decision.warning.map(LanePulse.warning)
        case .outLeft: pulse = .turnRight
        case .outRight: pulse = .turnLeft
        case .overshot: pulse = .overshot
        }
        guard decision.changed || now >= nextAt else { return nil }
        nextAt = now+(decision.state == .overshot ? 4 : 2.5)
        return pulse
    }
}
