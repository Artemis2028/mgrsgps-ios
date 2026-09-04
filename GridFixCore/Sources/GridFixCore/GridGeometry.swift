import Foundation

/// Portable grid geometry — no CoreGraphics, no MapKit, no MapLibre.
///
/// The Android overlay computes interval, sampling and drawing in one pass.
/// The iOS build consumes this model instead and hands the lines to whatever
/// renderer is in front of it:
///
///     bbox -> chooseGridInterval -> sample UTM lines -> [GridLine] -> renderer
public struct GeoPoint: Equatable, Sendable, Codable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

public struct GridLine: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable { case gzd, square, metre }
    /// The line in lat/lon. The engine projects it.
    public let points: [GeoPoint]
    public let heavy: Bool
    public let kind: Kind

    public init(points: [GeoPoint], heavy: Bool = false, kind: Kind = .metre) {
        self.points = points
        self.heavy = heavy
        self.kind = kind
    }
}

/// An edge label anchored at a lat/lon.
public struct GridLabel: Equatable, Sendable, Codable {
    public let text: String
    public let lat: Double
    public let lon: Double
    public init(text: String, lat: Double, lon: Double) {
        self.text = text
        self.lat = lat
        self.lon = lon
    }
}

public enum Grid {
    /// Minimum on-screen spacing between grid lines, in points (Android: dp).
    /// Matches `MgrsGridOverlay.draw():124`.
    public static let minSpacingPoints: Double = 48.0

    static let intervals = [10, 100, 1000, 10000, 100000]

    /// The finest grid interval (metres) whose lines still sit at least
    /// ``minSpacingPoints`` apart. 0 means "too far out — draw GZD only".
    ///
    /// Takes metres per **pixel** and the screen scale, exactly as the Android
    /// overlay does, so both platforms answer identically for the same view.
    /// Mixing the two units silently coarsens the grid by the scale factor —
    /// a 3x phone drops from a 1 km grid to a 10 km one — so if you have
    /// metres per *point*, use the other overload rather than passing it here.
    public static func chooseInterval(metersPerPixel: Double, scale: Double) -> Int {
        guard metersPerPixel > 0.0, scale > 0.0 else { return 0 }
        let minSpacing = minSpacingPoints * scale
        for interval in intervals where Double(interval) / metersPerPixel >= minSpacing {
            return interval
        }
        return 0
    }

    /// The same rule expressed in points, which is what MapLibre reports.
    /// The screen scale cancels: 48 dp of pixels at scale s is 48 points.
    public static func chooseInterval(metersPerPoint: Double) -> Int {
        guard metersPerPoint > 0.0 else { return 0 }
        for interval in intervals where Double(interval) / metersPerPoint >= minSpacingPoints {
            return interval
        }
        return 0
    }

    /// The readout label for an interval from ``chooseInterval(metersPerPoint:scale:)``.
    public static func intervalLabel(_ interval: Int) -> String {
        switch interval {
        case 0: return "GZD"
        case 100000: return "100 km"
        case 10000: return "10 km"
        case 1000: return "1 km"
        case 100: return "100 m"
        default: return "10 m"
        }
    }
}
