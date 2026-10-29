import CoreGraphics
import Foundation

/// Declutter captions only. Marker views and their accessibility/tap targets stay intact.
enum WaypointLabelLayout {
    struct Candidate {
        let id: String
        let rect: CGRect
        let priority: Bool
    }
    private struct Cell: Hashable { let x: Int, y: Int }
    static func visible(_ candidates: [Candidate], in viewport: CGRect) -> Set<String> {
        guard !viewport.isEmpty, !viewport.isInfinite, !viewport.isNull else { return [] }
        var buckets: [Cell: [CGRect]] = [:], visible = Set<String>()
        for item in candidates.sorted(by: { $0.priority != $1.priority ? $0.priority : $0.id < $1.id }) {
            let rect = item.rect
            guard !rect.isEmpty, !rect.isInfinite, !rect.isNull, viewport.contains(rect) else { continue }
            // One-point separation on each side keeps contrasting backings distinct.
            let padded = rect.insetBy(dx: -1,dy: -1)
            let cells = (Int(floor(padded.minX/64))...Int(floor(padded.maxX/64))).flatMap { x in
                (Int(floor(padded.minY/64))...Int(floor(padded.maxY/64))).map { Cell(x: x,y: $0) }
            }
            guard !cells.contains(where: { buckets[$0,default: []].contains(where: { $0.intersects(padded) }) }) else { continue }
            visible.insert(item.id)
            for cell in cells { buckets[cell,default: []].append(padded) }
        }
        return visible
    }
}
