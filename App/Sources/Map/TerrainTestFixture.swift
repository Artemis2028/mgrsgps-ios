#if DEBUG
import CoreGraphics
import GridFixCore
import UIKit

/// Real encoded Terrarium PNGs in the normal disk cache, only in isolated UI tests.
enum TerrainTestFixture {
    static func seed(_ pipeline: MapTilePipeline) throws {
        let tiles = try TileDownloadPlan.coverage(.init(south: 24.39,north: 24.52,west: 54.31,east: 54.45),minZoom: 13,maxZoom: 13,limit: 30)
        for tile in tiles {
            var pixels = [UInt8](repeating: 0,count: 256*256*4)
            for y in 0..<256 { for x in 0..<256 {
                let lon = MapTile.longitude(Double(tile.x)+(Double(x)+0.5)/256,zoom: 13)
                let height = (54.384...54.386).contains(lon) ? 180 : 100
                let i = (y*256+x)*4
                pixels[i] = UInt8(128+height/256); pixels[i+1] = UInt8(height%256); pixels[i+2] = 0; pixels[i+3] = 255
            } }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData), let cg = CGImage(width: 256,height: 256,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: 256*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent),let data = UIImage(cgImage: cg).pngData() else { throw URLError(.cannotDecodeContentData) }
            try pipeline.terrainCache.store(data,tile: tile)
        }
    }
}
#endif
