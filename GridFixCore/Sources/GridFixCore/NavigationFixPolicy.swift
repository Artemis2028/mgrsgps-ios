import Foundation

/// Matches GridFix 1.0.4's NavigationFixPolicy. Uptime, rather than wall time,
/// keeps a device-clock adjustment from reviving an old navigation sample.
public enum NavigationFixPolicy {
    public static let maxAgeSeconds: TimeInterval = 10
    public static let maxAccuracyMeters: Double = 25

    public static func isUsable(lat: Double, lon: Double, accuracyMeters: Double,
                                timestampUptime: TimeInterval, nowUptime: TimeInterval) -> Bool {
        lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
            && accuracyMeters.isFinite && (0...maxAccuracyMeters).contains(accuracyMeters)
            && timestampUptime.isFinite && nowUptime.isFinite && timestampUptime > 0
            && nowUptime >= timestampUptime && nowUptime - timestampUptime <= maxAgeSeconds
    }

    /// The entire uncertainty circle must fit inside the 50 m arrival ring.
    public static func insideArrivalRadius(distanceMeters: Double, accuracyMeters: Double) -> Bool {
        distanceMeters.isFinite && distanceMeters >= 0 && accuracyMeters.isFinite
            && accuracyMeters >= 0 && distanceMeters + accuracyMeters < 50
    }
}
