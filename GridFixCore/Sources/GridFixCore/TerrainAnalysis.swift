import Foundation

/// Sampling policies and terrain-only visibility, matching Android Terrain.kt.
public enum TerrainAnalysis {
    public typealias Sampler = @Sendable (GeoPoint) async -> Double?
    public struct Profile: Sendable {
        public let distances: [Float]
        public let elevations: [Float]
        public let legEnds: [Int]
        public let missing: Int
        public var total: Float { distances.last ?? 0 }
        public func gainLoss(threshold: Float = 1.5) -> (gain: Float,loss: Float) {
            var gain: Float = 0, loss: Float = 0, anchor = Float.nan
            for height in elevations where height.isFinite {
                if !anchor.isFinite { anchor = height; continue }
                let delta = height-anchor
                if delta >= threshold { gain += delta; anchor = height }
                else if delta <= -threshold { loss -= delta; anchor = height }
            }
            return (gain,loss)
        }
    }
    public struct Sight: Sendable {
        public let profile: Profile
        public let analysis: TerrainSight.Result
        public let observer: GeoPoint
        public let target: GeoPoint
        public let observerHeight: Float
        public let targetHeight: Float
        public var blockPosition: GeoPoint? {
            let i = analysis.blockIndex
            return i >= 0 ? TerrainGeometry.position(from: observer,to: target,fraction: Double(profile.distances[i]/profile.total)) : nil
        }
    }
    public struct Viewshed: Sendable {
        public let id = UUID()
        public let classes: [UInt8]
        public let size: Int
        public let north: Double, south: Double, west: Double, east: Double
        public let observer: GeoPoint
        public let radius: Double
        public let missing: Int
        public var unknownCells: Int { classes.filter { $0 == TerrainSight.Cell.unknown.rawValue }.count }
    }
    public static func profile(points: [GeoPoint],step: Double = 25,maxSamples: Int = 600,elevation: Sampler) async throws -> Profile? {
        guard points.count >= 2, step.isFinite, step > 0, maxSamples >= 2,
              points.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 85 }) else { return nil }
        let lengths = zip(points,points.dropFirst()).map { TerrainGeometry.distance($0,$1) }
        let total = lengths.reduce(0,+)
        guard total.isFinite, total > 0 else { return nil }
        let spacing = max(step,total/Double(maxSamples))
        var distances: [Float] = [], heights: [Float] = [], legEnds: [Int] = [], missing = 0, walked = 0.0
        func sample(_ point: GeoPoint,_ distance: Double) async throws {
            try Task.checkCancellation()
            let value = await elevation(point)
            distances.append(Float(distance))
            if let value, value.isFinite, Float(value).isFinite { heights.append(Float(value)) } else { heights.append(.nan); missing += 1 }
        }
        try await sample(points[0],0)
        for i in lengths.indices {
            let length = lengths[i]
            if length > 0 {
                var d = spacing
                while d < length {
                    try await sample(TerrainGeometry.position(from: points[i],to: points[i+1],fraction: d/length),walked+d)
                    d += spacing
                }
            }
            walked += length; try await sample(points[i+1],walked); legEnds.append(distances.count-1)
        }
        return Profile(distances: distances,elevations: heights,legEnds: legEnds,missing: missing)
    }
    public static func lineOfSight(observer: GeoPoint,target: GeoPoint,observerHeight: Float = 2,targetHeight: Float = 2,elevation: Sampler) async throws -> Sight? {
        guard let profile = try await profile(points: [observer,target],step: 20,maxSamples: 500,elevation: elevation),
              let result = TerrainSight.lineOfSight(distances: profile.distances,elevations: profile.elevations,observerHeight: observerHeight,targetHeight: targetHeight) else { return nil }
        return Sight(profile: profile,analysis: result,observer: observer,target: target,observerHeight: observerHeight,targetHeight: targetHeight)
    }
    public static func viewshed(observer: GeoPoint,height: Double = 2,radius: Double = 2000,size: Int = 192,rays: Int = 768,elevation: Sampler,progress: @Sendable (Double) async -> Void = { _ in }) async throws -> Viewshed? {
        try Task.checkCancellation()
        guard observer.lat.isFinite, observer.lon.isFinite, abs(observer.lat) <= 85, height.isFinite,
              radius.isFinite, radius > 0, radius <= 20_000, (16...512).contains(size), (16...4096).contains(rays),
              let ground = await elevation(observer), ground.isFinite else { return nil }
        let eye = ground+height, kx = cos(observer.lat*Double.pi/180)
        let dLat = radius/111319.49, dLon = radius/(111319.49*kx)
        let north = observer.lat+dLat, south = observer.lat-dLat, west = observer.lon-dLon, east = observer.lon+dLon
        var classes = [UInt8](repeating: 0,count: size*size), missing = 0
        let step = (2*radius/Double(size))*0.7, samples = Int(ceil(radius/step))
        for r in 0..<rays {
            try Task.checkCancellation()
            if r%16 == 0 { await progress(Double(r)/Double(rays)) }
            let azimuth = 2*Double.pi*Double(r)/Double(rays)
            var ray = TerrainSight.Ray(eye: eye), distance = step
            for _ in 0..<samples {
                if distance > radius { break }
                let lat = observer.lat+distance*cos(azimuth)/111319.49
                let lon = observer.lon+distance*sin(azimuth)/(111319.49*kx)
                let x = Int((lon-west)/(east-west)*Double(size)), y = Int((north-lat)/(north-south)*Double(size))
                let value = await elevation(.init(lat: lat,lon: TerrainGeometry.wrap(lon)))
                if value == nil || !value!.isFinite { missing += 1 }
                let cell = ray.sample(distance: distance,elevation: value)
                if (0..<size).contains(x), (0..<size).contains(y) { classes[y*size+x] = max(classes[y*size+x],cell.rawValue) }
                distance += step
            }
        }
        classes[(size/2)*size+size/2] = TerrainSight.Cell.visible.rawValue
        await progress(1)
        return Viewshed(classes: classes,size: size,north: north,south: south,west: west,east: east,observer: observer,radius: radius,missing: missing)
    }
}
