import Foundation

/// Android TrackSimplify.kt's largest-deviation-first, endpoint-preserving budget.
public enum TrackBacktrack {
    public enum Failure: LocalizedError {
        case invalidOptions, invalidPoints, tooShort
        public var errorDescription: String? {
            switch self {
            case .invalidOptions: return "A route needs at least two vertices and a finite, nonnegative tolerance."
            case .invalidPoints: return "The track contains invalid coordinates."
            case .tooShort: return "The track needs at least two recorded positions."
            }
        }
    }
    private struct Segment { let first: Int; let last: Int; let split: Int; let error: Double }

    public static func simplify(_ points: [GeoPoint],tolerance: Double = 20,maxPoints: Int = 64) throws -> [GeoPoint] {
        guard maxPoints >= 2, tolerance.isFinite, tolerance >= 0 else { throw Failure.invalidOptions }
        guard points.allSatisfy({ TrackCodec.validCoordinates($0.lat,$0.lon) }) else { throw Failure.invalidPoints }
        guard points.count > 2 else { return points }
        let metresPerLatitude = 111_320.0
        let metresPerLongitude = metresPerLatitude*max(0.01,cos(points[0].lat*Double.pi/180))
        func distance(_ p: GeoPoint,_ a: GeoPoint,_ b: GeoPoint) -> Double {
            let px = TerrainGeometry.wrap(p.lon-a.lon)*metresPerLongitude, py = (p.lat-a.lat)*metresPerLatitude
            let bx = TerrainGeometry.wrap(b.lon-a.lon)*metresPerLongitude, by = (b.lat-a.lat)*metresPerLatitude
            let lengthSquared = bx*bx+by*by
            if lengthSquared < 1e-18 { return hypot(px,py) }
            let t = max(0,min(1,(px*bx+py*by)/lengthSquared))
            return hypot(px-t*bx,py-t*by)
        }
        var segments: [Segment] = []
        func enqueue(_ first: Int,_ last: Int) {
            var worst = tolerance, split = -1
            if first+1 < last {
                for i in (first+1)..<last {
                    let error = distance(points[i],points[first],points[last])
                    if error > worst { worst = error; split = i }
                }
            }
            if split >= 0 { segments.append(.init(first: first,last: last,split: split,error: worst)) }
        }
        var keep = [Bool](repeating: false,count: points.count), kept = 2
        keep[0] = true; keep[points.count-1] = true; enqueue(0,points.count-1)
        // At most maxPoints candidates: a linear max preserves the same priority
        // and low-index tie break as Android's heap without unbounded recursion.
        while kept < maxPoints, let next = segments.indices.max(by: { a,b in
            if segments[a].error != segments[b].error { return segments[a].error < segments[b].error }
            return segments[a].split > segments[b].split
        }) {
            let segment = segments.remove(at: next)
            keep[segment.split] = true; kept += 1
            enqueue(segment.first,segment.split); enqueue(segment.split,segment.last)
        }
        return points.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    public static func route(track: Backup.TrackMeta,points: [TrackPoint],now: Int64 = Int64(Date().timeIntervalSince1970*1000)) throws -> Backup.Graphic {
        guard points.count >= 2 else { throw Failure.tooShort }
        let reversed = points.reversed().map { GeoPoint(lat: $0.lat,lon: $0.lon) }
        let reduced = try simplify(reversed)
        return Backup.Graphic(id: UUID().uuidString.lowercased(),name: String(("Back "+track.name).prefix(20)),type: "route",points: reduced.map { .init(lat: $0.lat,lon: $0.lon) },folder: track.folder,createdAt: now)
    }
}
