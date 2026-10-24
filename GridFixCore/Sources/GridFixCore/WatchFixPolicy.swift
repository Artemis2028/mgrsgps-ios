import Foundation

/// The watch accepts poor-but-finite samples for honest status reporting, and applies
/// the stricter shared navigation policy only while authorized, precise and active.
public enum WatchFixPolicy {
    public static func accepts(lat: Double, lon: Double, accuracy: Double, age: TimeInterval) -> Bool {
        lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
            && accuracy.isFinite && accuracy >= 0 && age.isFinite && age >= 0
    }

    public static func isUsable(authorized: Bool, precise: Bool, foreground: Bool,
                                lat: Double, lon: Double, accuracy: Double,
                                timestampUptime: TimeInterval, nowUptime: TimeInterval) -> Bool {
        authorized && precise && foreground
            && NavigationFixPolicy.isUsable(lat: lat, lon: lon, accuracyMeters: accuracy,
                                             timestampUptime: timestampUptime, nowUptime: nowUptime)
    }

    /// Handles malformed dates and extremely old cache timestamps without trapping an Int conversion.
    public static func ageLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "AGE UNKNOWN" }
        guard seconds >= 0 else { return "CLOCK CHANGED" }
        if seconds < 60 { return "\(Int(seconds))S AGO" }
        if seconds < 3600 { return "\(Int(seconds / 60))M AGO" }
        if seconds < 86400 { return "\(Int(seconds / 3600))H AGO" }
        return String(format: "%.0fD AGO", seconds / 86400)
    }
}
