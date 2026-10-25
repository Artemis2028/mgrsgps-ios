import Foundation
import GridFixCore

/// Android PositionScreen/NavigateScreen source selection at 482b417.
/// A GPS course is an earth-referenced direction of travel, never wrist/phone
/// orientation. Display rotation must not add an offset to it.
struct MovementHeading: Equatable {
    enum Source { case compass, course }
    let degreesTrue: Double
    let source: Source
    var label: String { source == .compass ? "Screen top" : "GPS course" }

    static func position(face: PositionFace, compassTrue: Double?, fix: Fix?) -> Self? {
        if face != .glance, let value = valid(compassTrue) { return .init(degreesTrue: value,source: .compass) }
        return course(fix)
    }
    static func navigation(hasCompass: Bool, compassTrue: Double?, fix: Fix?,
                           nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Self? {
        guard let fix, NavigationFixPolicy.isUsable(lat: fix.lat,lon: fix.lon,accuracyMeters: fix.accuracyMeters,
                                                    timestampUptime: fix.timestampUptime,nowUptime: nowUptime) else { return nil }
        if hasCompass {
            guard let value = valid(compassTrue) else { return nil }
            return .init(degreesTrue: value,source: .compass)
        }
        return course(fix)
    }
    private static func course(_ fix: Fix?) -> Self? {
        guard let fix, let speed = fix.speedMetersPerSecond, speed.isFinite, speed > 0.5,
              let bearing = valid(fix.courseDegrees) else { return nil }
        return .init(degreesTrue: bearing,source: .course)
    }
    private static func valid(_ angle: Double?) -> Double? {
        guard let angle, angle.isFinite, (0..<360).contains(angle) else { return nil }
        return angle
    }
}
