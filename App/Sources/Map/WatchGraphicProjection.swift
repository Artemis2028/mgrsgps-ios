import Foundation

/// Keep each projected leg in its nearest world copy. A date-line crossing must
/// remain a local leg rather than a line across the screen; preserve every vertex.
enum WatchGraphicProjection {
    static func continuous(_ points: [CGPoint],worldWidth: CGFloat,centerX: CGFloat) -> [CGPoint] {
        guard worldWidth.isFinite,worldWidth > 0,centerX.isFinite,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        var previous = centerX
        var result: [CGPoint] = []; result.reserveCapacity(points.count)
        for point in points {
            let difference = point.x-previous
            guard difference.isFinite else { return [] }
            let raw = difference.truncatingRemainder(dividingBy:worldWidth)
            let delta = raw >= worldWidth/2 ? raw-worldWidth : raw < -worldWidth/2 ? raw+worldWidth : raw
            previous += delta
            guard previous.isFinite else { return [] }
            result.append(.init(x:previous,y:point.y))
        }
        return result
    }
}
