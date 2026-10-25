import Foundation

/// Android WaypointDialog / osmdroid destinationPoint: radius 6378137 m.
public enum WaypointProjection {
    public enum Failure: String, LocalizedError {
        case base = "Choose a valid base point."
        case azimuth = "Enter a finite, non-negative azimuth. Full turns wrap around north."
        case distance = "Enter a distance greater than zero and no more than 200,000 metres."
        case reference = "The selected north reference is unavailable at the base point."
        public var errorDescription: String? { rawValue }
    }
    public struct Result: Equatable,Sendable {
        public let point: GeoPoint
        public let bearingTrue: Double
        public let meters: Double
    }
    public static func project(base: GeoPoint,azimuth: String,distance: String,angleUnit: AngleUnit,northReference: Int,
                               declination: (GeoPoint) -> Double?) throws -> Result {
        guard TrackCodec.validCoordinates(base.lat,base.lon) else { throw Failure.base }
        guard let entered = Double(azimuth.trimmingCharacters(in: .whitespacesAndNewlines)),entered.isFinite,entered >= 0 else { throw Failure.azimuth }
        guard let meters = Double(distance.trimmingCharacters(in: .whitespacesAndNewlines)),meters.isFinite,meters > 0,meters <= 200_000 else { throw Failure.distance }
        let degrees = angleUnit == .mils ? entered*360/6400 : entered
        guard degrees.isFinite else { throw Failure.azimuth }
        let correction: Double?
        switch northReference {
        case 0: correction = 0
        case 1: correction = declination(base)
        case 2: correction = (-80...84).contains(base.lat) ? UTM.gridConvergence(lat: base.lat,lon: base.lon) : nil
        default: correction = nil
        }
        guard let correction,correction.isFinite else { throw Failure.reference }
        let angle = degrees.truncatingRemainder(dividingBy: 360)+correction
        let bearing = (angle.truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)
        let p = base.lat*Double.pi/180, l = base.lon*Double.pi/180, a = bearing*Double.pi/180, arc = meters/6_378_137
        let latitude = asin(max(-1,min(1,sin(p)*cos(arc)+cos(p)*sin(arc)*cos(a))))
        let longitude = l+atan2(sin(a)*sin(arc)*cos(p),cos(arc)-sin(p)*sin(latitude))
        let point = GeoPoint(lat: latitude*180/Double.pi,lon: TerrainGeometry.wrap(longitude*180/Double.pi))
        guard TrackCodec.validCoordinates(point.lat,point.lon) else { throw Failure.base }
        return .init(point: point,bearingTrue: bearing,meters: meters)
    }
}
