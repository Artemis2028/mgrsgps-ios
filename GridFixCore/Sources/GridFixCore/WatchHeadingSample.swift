import Foundation

/// A compass callback from this foreground watch session, never a phone/cache value.
public struct WatchHeadingSample: Equatable, Sendable {
    public static let maxAge: TimeInterval = 5
    public let trueDegrees: Double
    public let accuracy: Double
    public let uptime: TimeInterval

    public init?(trueDegrees: Double, accuracy: Double, sampleUptime: TimeInterval,
                 sessionUptime: TimeInterval, nowUptime: TimeInterval) {
        guard trueDegrees.isFinite, (0..<360).contains(trueDegrees),
              accuracy.isFinite, (0...25).contains(accuracy),
              sessionUptime.isFinite, sessionUptime > 0,
              sampleUptime.isFinite, sampleUptime >= sessionUptime,
              nowUptime.isFinite, nowUptime >= sampleUptime,
              nowUptime-sampleUptime <= Self.maxAge else { return nil }
        self.trueDegrees = trueDegrees; self.accuracy = accuracy; self.uptime = sampleUptime
    }
    public func isFresh(nowUptime: TimeInterval) -> Bool {
        nowUptime.isFinite && nowUptime >= uptime && nowUptime-uptime <= Self.maxAge
    }
}
