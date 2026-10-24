import Foundation

/// Pure calculations ported from Android release/1.1.0 TerrainSight.kt.
public enum TerrainSight {
    public static let earthRadius = 6_371_008.8
    public static let effectiveRadius = earthRadius * 4 / 3
    public enum Status: String, Sendable { case visible, masked, unknown }
    public enum Cell: UInt8, Sendable { case none = 0, visible = 1, marginal = 2, masked = 3, unknown = 4 }
    public struct Result: Sendable {
        public let status: Status
        public let blockIndex: Int
        public let clearObserverHeight: Float
        public let minClearance: Float
        public let minClearanceDistance: Float
        public let sightLine: [Float]
        public let effectiveTerrain: [Float]
    }
    public static func lineOfSight(distances: [Float], elevations: [Float], observerHeight: Float, targetHeight: Float) -> Result? {
        let n = elevations.count
        guard n >= 2, distances.count == n, let total = distances.last, total.isFinite, total > 0,
              distances.first == 0, distances.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= total }),
              zip(distances,distances.dropFirst()).allSatisfy({ $0 <= $1 }),
              elevations[0].isFinite, elevations[n-1].isFinite, observerHeight.isFinite, targetHeight.isFinite else { return nil }
        let ground = elevations[0], a = ground+observerHeight, b = elevations[n-1]+targetHeight
        var sight = [Float](repeating: 0,count: n), effective = sight
        var blocker = -1, missing = false, required: Float = 0, minGap = Float.infinity, minDistance: Float = 0
        for i in 0..<n {
            let d = Double(distances[i]), t = Float(d/Double(total))
            sight[i] = a+(b-a)*t
            let curve = d*(Double(total)-d)/(2*effectiveRadius)
            effective[i] = elevations[i].isFinite ? Float(Double(elevations[i])+curve) : .nan
            if i == 0 || i == n-1 { continue }
            guard effective[i].isFinite else { missing = true; continue }
            let gap = sight[i]-effective[i]
            if gap < minGap { minGap = gap; minDistance = distances[i] }
            if gap < 0.5 && blocker == -1 { blocker = i }
            if t < 1 {
                let need = (effective[i]+0.5-b*t)/(1-t)-ground
                required = max(required,need)
            }
        }
        return Result(status: blocker >= 0 ? .masked : (missing ? .unknown : .visible),blockIndex: blocker,
                      clearObserverHeight: missing ? .nan : max(0,required), minClearance: !missing && minGap.isFinite ? minGap : .nan,
                      minClearanceDistance: missing ? .nan : minDistance,sightLine: sight,effectiveTerrain: effective)
    }
    public struct Ray: Sendable {
        private let eye: Double
        private var maxSlope = -Double.infinity
        private var hasGap = false
        public init(eye: Double) { self.eye = eye }
        public mutating func sample(distance: Double,elevation: Double?) -> Cell {
            guard distance.isFinite, distance > 0 else { return .unknown }
            guard let elevation, elevation.isFinite else { hasGap = true; return .unknown }
            let terrain = elevation-distance*distance/(2*effectiveRadius)
            let low = (terrain+0.5-eye)/distance, standing = (terrain+3-eye)/distance
            let result: Cell
            if standing < maxSlope { result = .masked }
            else if hasGap { result = .unknown }
            else if low >= maxSlope { result = .visible }
            else { result = .marginal }
            maxSlope = max(maxSlope,(terrain-eye)/distance)
            return result
        }
    }
    public static func merge(_ previous: Cell,_ incoming: Cell) -> Cell { previous.rawValue >= incoming.rawValue ? previous : incoming }
}

public enum TerrainGeometry {
    public static func wrap(_ longitude: Double) -> Double { ((longitude+180).truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)-180 }
    public static func distance(_ a: GeoPoint,_ b: GeoPoint) -> Double { Geodesy.greatCircleMeters(a.lat,a.lon,b.lat,b.lon) }
    public static func position(from a: GeoPoint,to b: GeoPoint,fraction: Double) -> GeoPoint {
        if fraction <= 0 { return .init(lat: a.lat,lon: wrap(a.lon)) }
        if fraction >= 1 { return .init(lat: b.lat,lon: wrap(b.lon)) }
        let lat = a.lat*Double.pi/180, lon = a.lon*Double.pi/180, latB = b.lat*Double.pi/180, lonB = b.lon*Double.pi/180
        let ax = cos(lat)*cos(lon), ay = cos(lat)*sin(lon), az = sin(lat)
        let bx = cos(latB)*cos(lonB), by = cos(latB)*sin(lonB), bz = sin(latB)
        let dot = min(1,max(-1,ax*bx+ay*by+az*bz))
        var tx = bx-dot*ax, ty = by-dot*ay, tz = bz-dot*az
        let length = sqrt(tx*tx+ty*ty+tz*tz)
        if length < 1e-12 {
            if dot > 0 { return .init(lat: a.lat,lon: wrap(a.lon)) }
            tx = -sin(lat)*cos(lon); ty = -sin(lat)*sin(lon); tz = cos(lat)
        } else { tx /= length; ty /= length; tz /= length }
        let angle = atan2(length,dot)*fraction
        let x = ax*cos(angle)+tx*sin(angle), y = ay*cos(angle)+ty*sin(angle), z = az*cos(angle)+tz*sin(angle)
        return .init(lat: atan2(z,hypot(x,y))*180/Double.pi,lon: wrap(atan2(y,x)*180/Double.pi))
    }
}
