import GridFixCore
import UIKit

@MainActor
enum TerrainViewshedRenderer {
    static func image(_ value: TerrainAnalysis.Viewshed,night: Bool) -> UIImage? {
        let day: [UInt32] = [0,0x4600C853,0x55FFD600,0x50FF1744,0x66808080]
        let red: [UInt32] = [0,0x307F231D,0x48C42D24,0x60FF3B30,0x60FF3B30]
        let palette = night ? red : day
        var pixels = [UInt8](repeating: 0,count: value.classes.count*4)
        for (i,cell) in value.classes.enumerated() {
            guard Int(cell) < palette.count else { continue }
            if cell == TerrainSight.Cell.unknown.rawValue && ((i%value.size+i/value.size)%4 < 2) { continue }
            let color = palette[Int(cell)], base = i*4
            pixels[base] = UInt8((color>>16)&255); pixels[base+1] = UInt8((color>>8)&255); pixels[base+2] = UInt8(color&255); pixels[base+3] = UInt8((color>>24)&255)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),let cg = CGImage(width: value.size,height: value.size,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: value.size*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
