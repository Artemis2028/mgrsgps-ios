import Foundation

/// Complete latest-state phone → watch message. A nil target explicitly clears selection.
/// Never contains phone location: watch position always comes from its own CoreLocation session.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public static let contextKey = "gridfix.snapshot.v1"
    public var version = 1
    public var updatedAt: Date
    public var target: Target?
    public var nightMode: Bool
    public var mgrsDigits: Int
    public var units: Int
    public var angleUnit: Int
    /// 0 true, 1 magnetic, 2 grid (Android/iPhone settings contract).
    public var northRef: Int
    public var declinationOverride: Double?

    public struct Target: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var lat: Double
        public var lon: Double
        public init(id: String, name: String, lat: Double, lon: Double) {
            self.id = id; self.name = name; self.lat = lat; self.lon = lon
        }
    }

    public init(updatedAt: Date = Date(), target: Target? = nil, nightMode: Bool = false,
                mgrsDigits: Int = 10, units: Int = 0, angleUnit: Int = 0,
                northRef: Int = 0, declinationOverride: Double? = nil) {
        self.updatedAt = updatedAt; self.target = target; self.nightMode = nightMode
        self.mgrsDigits = mgrsDigits; self.units = units; self.angleUnit = angleUnit
        self.northRef = northRef; self.declinationOverride = declinationOverride
    }

    public var isValid: Bool {
        version == 1 && updatedAt.timeIntervalSince1970.isFinite
        && [4,6,8,10].contains(mgrsDigits) && (0...2).contains(units)
        && (0...1).contains(angleUnit) && (0...2).contains(northRef)
        && (declinationOverride.map { $0.isFinite && (-180...180).contains($0) } ?? true)
        && (target.map { !$0.id.isEmpty && $0.lat.isFinite && $0.lon.isFinite
            && (-90...90).contains($0.lat) && (-180...180).contains($0.lon) } ?? true)
    }

    public static func decode(_ data: Data) -> WatchSnapshot? {
        guard let snapshot = try? JSONDecoder().decode(Self.self, from: data), snapshot.isValid else { return nil }
        return snapshot
    }

    public func bearing(trueDegrees: Double, lat: Double, lon: Double, altitude: Double = 0,
                        date: Date = Date()) -> Double? {
        var value = trueDegrees
        if northRef == 1 {
            let year = WMM.decimalYear(from: date)
            let model = WMM.bundled
            guard let declination = declinationOverride ?? model.flatMap({
                $0.isValid(at: year) ? $0.declination(lat: lat, lon: lon, heightMeters: altitude, decimalYear: year) : nil
            }) else { return nil }
            value -= declination
        } else if northRef == 2 {
            value -= UTM.gridConvergence(lat: lat, lon: lon)
        }
        guard value.isFinite else { return nil }
        return (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
}
