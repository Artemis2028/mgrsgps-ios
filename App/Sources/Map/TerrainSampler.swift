import GridFixCore
import ImageIO
import Foundation
import CoreGraphics

/// Shared with map downloads/contours: no independent or hidden online source.
actor TerrainSampler {
    struct Raster: Sendable {
        let heights: [Double]
        static func decode(_ data: Data) throws -> Raster {
            guard let source = CGImageSourceCreateWithData(data as CFData,nil), let image = CGImageSourceCreateImageAtIndex(source,0,nil), image.width == 256, image.height == 256 else { throw URLError(.cannotDecodeContentData) }
            var pixels = [UInt8](repeating: 0,count: 256*256*4)
            let success = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let c = CGContext(data: buffer.baseAddress,width: 256,height: 256,bitsPerComponent: 8,bytesPerRow: 256*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                c.draw(image,in: CGRect(x: 0,y: 0,width: 256,height: 256)); return true
            }
            guard success else { throw URLError(.cannotDecodeContentData) }
            var values = [Double](); values.reserveCapacity(256*256)
            for i in stride(from: 0,to: pixels.count,by: 4) {
                let elevation: Double? = TerrainContours.elevation(red: pixels[i],green: pixels[i+1],blue: pixels[i+2])
                let value: Double = pixels[i+3] == 0 ? .nan : (elevation ?? .nan)
                values.append(value)
            }
            return Raster(heights: values)
        }
    }
    let pipeline: MapTilePipeline
    private var rasters: [MapTile: Raster] = [:]
    private var lru: [MapTile] = []
    private var failures: [MapTile: TimeInterval] = [:]
    private var loading: [MapTile: Task<Raster?,Never>] = [:]
    private var previousOffline: Bool?
    init(pipeline: MapTilePipeline) { self.pipeline = pipeline }
    func invalidateFailures() { failures.removeAll() }
    func elevation(_ point: GeoPoint) async -> Double? {
        guard !Task.isCancelled, point.lat.isFinite,point.lon.isFinite,abs(point.lat) <= 85 else { return nil }
        let size = Double(1 << 13), x = (TerrainGeometry.wrap(point.lon)+180)/360*size
        let angle = point.lat*Double.pi/180, y = (1-asinh(tan(angle))/Double.pi)/2*size
        let tile = MapTile(z: 13,x: Int(floor(x)),y: Int(floor(y)))
        let raster: Raster
        if let existing = rasters[tile] { raster = existing }
        else {
            let offline = pipeline.offlineOnly
            if previousOffline != offline { failures.removeAll(); previousOffline = offline }
            if let failed = failures[tile], ProcessInfo.processInfo.systemUptime-failed < 60 { return nil }
            let pending: Task<Raster?,Never>
            if let task = loading[tile] { pending = task }
            else {
                let pipeline = pipeline
                pending = Task.detached(priority: .utility) {
                    do { return try Raster.decode(await pipeline.fetch(MapCatalog.elevation,tile: tile,allowParentFallback: false)) }
                    catch { return nil }
                }
                loading[tile] = pending
            }
            guard let value = await pending.value else { loading[tile] = nil; failures[tile] = ProcessInfo.processInfo.systemUptime; if failures.count > 128 { failures = failures.filter { ProcessInfo.processInfo.systemUptime-$0.value < 60 } }; return nil }
            loading[tile] = nil; rasters[tile] = value; raster = value
        }
        lru.removeAll { $0 == tile }; lru.append(tile)
        while lru.count > 12 { rasters.removeValue(forKey: lru.removeFirst()) }
        let px = min(255,max(0,Int((x-floor(x))*256))), py = min(255,max(0,Int((y-floor(y))*256)))
        let value = raster.heights[py*256+px]
        return value.isFinite ? value : nil
    }
    func readout(_ point: GeoPoint) async -> Readout {
        let elevation = await elevation(point)
        let delta = 30.0/111319.49, dx = delta/cos(point.lat*Double.pi/180)
        let north = await self.elevation(.init(lat: point.lat+delta,lon: point.lon))
        let south = await self.elevation(.init(lat: point.lat-delta,lon: point.lon))
        let east = await self.elevation(.init(lat: point.lat,lon: point.lon+dx))
        let west = await self.elevation(.init(lat: point.lat,lon: point.lon-dx))
        let slope: Double?
        if let north, let south, let east, let west { slope = atan(hypot((east-west)/60,(north-south)/60))*180/Double.pi } else { slope = nil }
        return Readout(elevation: elevation,slope: slope)
    }
    struct Readout: Sendable { let elevation: Double?; let slope: Double? }
}
