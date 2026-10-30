import Foundation

/// Two-ray field fixes from Android FieldTools.kt / Coordinates.kt at 482b417.
/// Reference conversion happens at each known point before applying the
/// automatic back-azimuth for resection.
public enum FieldFix {
    public enum Mode: String, CaseIterable, Sendable { case resection, intersection }
    public struct Solution: Equatable, Sendable {
        public let point: GeoPoint
        public let range1: Double
        public let range2: Double
        public let cutAngle: Double
        public var poorCut: Bool { cutAngle < 30 || cutAngle > 150 }
        public var grid: String? { MGRS.parts(lat: point.lat,lon: point.lon,digits: 8)?.full }
    }
    public enum Failure: String, LocalizedError {
        case point = "Choose two different points within UTM coverage (80°S to 84°N)."
        case azimuth = "Enter both azimuths from 0 to 360 degrees, or 0 to 6400 mils."
        case reference = "The selected north reference is unavailable at a known point."
        case geometry = "The rays do not cross ahead of both points within 100 km. Choose different points or check the azimuths."
        public var errorDescription: String? { rawValue }
    }
    public static func parseAzimuth(_ text: String,unit: AngleUnit) -> Double? {
        let full = unit == .mils ? 6400.0 : 360.0
        guard let entered = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),entered.isFinite,(0...full).contains(entered) else { return nil }
        return entered*360/full
    }
    public static func solve(mode: Mode,point1: GeoPoint,point2: GeoPoint,azimuth1: String,azimuth2: String,
                             angleUnit: AngleUnit,northReference: Int,declination: (GeoPoint) -> Double?) throws -> Solution {
        func valid(_ p: GeoPoint) -> Bool { TrackCodec.validCoordinates(p.lat,p.lon) && (-80...84).contains(p.lat) }
        guard valid(point1),valid(point2),point1 != point2 else { throw Failure.point }
        guard let a = parseAzimuth(azimuth1,unit: angleUnit),let b = parseAzimuth(azimuth2,unit: angleUnit) else { throw Failure.azimuth }
        func bearing(_ value: Double,_ p: GeoPoint) throws -> Double {
            let offset: Double?
            switch northReference {
            case 0: offset = 0
            case 1: offset = declination(p)
            case 2: offset = UTM.gridConvergence(lat: p.lat,lon: p.lon)
            default: offset = nil
            }
            guard let offset,offset.isFinite else { throw Failure.reference }
            let trueDegrees = value+offset+(mode == .resection ? 180 : 0)
            return (trueDegrees.truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)
        }
        let first = try bearing(a,point1),second = try bearing(b,point2)
        guard let fix = Geodesy.rayIntersection(lat1: point1.lat,lon1: point1.lon,bearing1True: first,lat2: point2.lat,lon2: point2.lon,bearing2True: second) else { throw Failure.geometry }
        let difference = abs(first-second).truncatingRemainder(dividingBy: 360)
        return .init(point: .init(lat: fix.lat,lon: fix.lon),range1: fix.dist1,range2: fix.dist2,cutAngle: min(difference,360-difference))
    }
}
