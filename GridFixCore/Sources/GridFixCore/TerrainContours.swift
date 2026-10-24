import Foundation

/// Android's Terrarium decoding and marching-squares cases. Geometry stays in
/// pixel coordinates until rendering, so the math can be tested independently.
public enum TerrainContours {
    public struct Point: Sendable, Equatable { public let x: Double, y: Double }
    public struct Segment: Sendable, Equatable { public let a: Point, b: Point }
    public struct Level: Sendable, Equatable {
        public let elevation: Int
        public let major: Bool
        public let segments: [Segment]
        public let label: Point?
    }
    public static func elevation(red: UInt8, green: UInt8, blue: UInt8) -> Double? {
        let value = Double(red) * 256 + Double(green) + Double(blue) / 256 - 32768
        return (-11_000...9_000).contains(value) ? value : nil
    }
    public static func interval(metersPerPoint: Double) -> Int? {
        guard metersPerPoint.isFinite, metersPerPoint > 0, metersPerPoint <= 20 else { return nil }
        return metersPerPoint <= 4 ? 10 : (metersPerPoint <= 10 ? 20 : 50)
    }
    public static func build(elevations: [Double], width: Int, interval: Int) -> [Level] {
        guard (2...512).contains(width), elevations.count == width * width, interval > 0 else { return [] }
        let valid = elevations.filter { $0.isFinite && (-11_000...9_000).contains($0) }
        guard let minimum = valid.min(), let maximum = valid.max(), maximum - minimum >= 0.75 else { return [] }
        var step = interval
        while (maximum - minimum) / Double(step) > 90 { step *= 2 }
        var result: [Level] = []
        for level in stride(from: Int(ceil(minimum / Double(step))) * step, through: Int(maximum), by: step) {
            let value = Double(level), major = level % (step * 5) == 0
            var segments: [Segment] = []
            var label: Point?, best = Double.greatestFiniteMagnitude
            func fraction(_ p: Double, _ q: Double) -> Double { p == q ? 0.5 : min(1, max(0, (value - p) / (q - p))) }
            func add(_ a: Point, _ b: Point) {
                segments.append(Segment(a: Point(x: a.x + 0.5, y: a.y + 0.5), b: Point(x: b.x + 0.5, y: b.y + 0.5)))
                if major {
                    let x = (a.x + b.x) / 2, y = (a.y + b.y) / 2
                    let distance = pow(x - Double(width) / 2, 2) + pow(y - Double(width) / 2, 2)
                    if distance < best { best = distance; label = Point(x: x + 0.5, y: y + 0.5) }
                }
            }
            for y in 0..<(width - 1) { for x in 0..<(width - 1) {
                let a = elevations[y * width + x], b = elevations[y * width + x + 1]
                let c = elevations[(y + 1) * width + x + 1], d = elevations[(y + 1) * width + x]
                guard [a,b,c,d].allSatisfy({ $0.isFinite && (-11_000...9_000).contains($0) }) else { continue }
                let mask = (a >= value ? 1 : 0) | (b >= value ? 2 : 0) | (c >= value ? 4 : 0) | (d >= value ? 8 : 0)
                if mask == 0 || mask == 15 { continue }
                let xx = Double(x), yy = Double(y)
                let top = Point(x: xx + fraction(a,b), y: yy), right = Point(x: xx + 1, y: yy + fraction(b,c))
                let bottom = Point(x: xx + fraction(d,c), y: yy + 1), left = Point(x: xx, y: yy + fraction(a,d))
                switch mask {
                case 1,14: add(left,top)
                case 2,13: add(top,right)
                case 3,12: add(left,right)
                case 4,11: add(right,bottom)
                case 6,9: add(top,bottom)
                case 7,8: add(left,bottom)
                case 5,10:
                    let high = (a + b + c + d) / 4 >= value
                    if (mask == 5 && high) || (mask == 10 && !high) { add(top,right); add(left,bottom) }
                    else { add(left,top); add(right,bottom) }
                default: break
                }
            } }
            if !segments.isEmpty { result.append(Level(elevation: level, major: major, segments: segments, label: label)) }
        }
        return result
    }
}
