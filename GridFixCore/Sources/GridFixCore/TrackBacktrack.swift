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
        try validateOptions(tolerance,maxPoints)
        for (index,point) in points.enumerated() {
            if index % 4096 == 0 { try Task.checkCancellation() }
            guard TrackCodec.validCoordinates(point.lat,point.lon) else { throw Failure.invalidPoints }
        }
        return try simplify(count: points.count,tolerance: tolerance,maxPoints: maxPoints,pointAt: { points[$0] })
    }
    private static func validateOptions(_ tolerance: Double,_ maxPoints: Int) throws {
        guard maxPoints >= 2, tolerance.isFinite, tolerance >= 0 else { throw Failure.invalidOptions }
        try Task.checkCancellation()
    }
    /// Index access lets a reverse route use the original coordinates without
    /// allocating a reversed copy. Retain only the chosen indices (at most the
    /// requested budget), instead of a second full-length keep array.
    private static func simplify(count: Int,tolerance: Double,maxPoints: Int,pointAt: (Int) -> GeoPoint) throws -> [GeoPoint] {
        try validateOptions(tolerance,maxPoints)
        guard count > 2 else { return (0..<count).map(pointAt) }
        let metresPerLatitude = 111_320.0
        let metresPerLongitude = metresPerLatitude*max(0.01,cos(pointAt(0).lat*Double.pi/180))
        func distance(_ p: GeoPoint,_ a: GeoPoint,_ b: GeoPoint) -> Double {
            let px = TerrainGeometry.wrap(p.lon-a.lon)*metresPerLongitude, py = (p.lat-a.lat)*metresPerLatitude
            let bx = TerrainGeometry.wrap(b.lon-a.lon)*metresPerLongitude, by = (b.lat-a.lat)*metresPerLatitude
            let lengthSquared = bx*bx+by*by
            if lengthSquared < 1e-18 { return hypot(px,py) }
            let t = max(0,min(1,(px*bx+py*by)/lengthSquared))
            return hypot(px-t*bx,py-t*by)
        }
        var segments: [Segment] = []
        func enqueue(_ first: Int,_ last: Int) throws {
            try Task.checkCancellation()
            var worst = tolerance, split = -1
            if first+1 < last {
                for i in (first+1)..<last {
                    if i % 4096 == 0 { try Task.checkCancellation() }
                    let error = distance(pointAt(i),pointAt(first),pointAt(last))
                    if error > worst { worst = error; split = i }
                }
            }
            if split >= 0 { segments.append(.init(first: first,last: last,split: split,error: worst)) }
        }
        var keep: Set<Int> = [0,count-1]
        try enqueue(0,count-1)
        // At most maxPoints candidates: a linear max preserves the same priority
        // and low-index tie break as Android's heap without unbounded recursion.
        while keep.count < maxPoints, let next = segments.indices.max(by: { a,b in
            if segments[a].error != segments[b].error { return segments[a].error < segments[b].error }
            return segments[a].split > segments[b].split
        }) {
            let segment = segments.remove(at: next)
            keep.insert(segment.split)
            try enqueue(segment.first,segment.split); try enqueue(segment.split,segment.last)
        }
        try Task.checkCancellation()
        return keep.sorted().map(pointAt)
    }

    public static func route(track: Backup.TrackMeta,points: [TrackPoint],now: Int64 = Int64(Date().timeIntervalSince1970*1000)) throws -> Backup.Graphic {
        guard points.count >= 2 else { throw Failure.tooShort }
        for (index,point) in points.enumerated() {
            if index % 4096 == 0 { try Task.checkCancellation() }
            guard TrackCodec.validCoordinates(point.lat,point.lon) else { throw Failure.invalidPoints }
        }
        let reduced = try simplify(count: points.count,tolerance: 20,maxPoints: 64) { index in
            let point = points[points.count-1-index]
            return GeoPoint(lat: point.lat,lon: point.lon)
        }
        return graphic(track: track,reduced: reduced,now: now)
    }

    /// Local recordings may exceed external backup budgets. Validate every row
    /// once and retain only coordinates needed by Android's exact random-access
    /// simplifier; no full TrackPoint array or reversed coordinate copy.
    public static func route(track: Backup.TrackMeta,data: Data,now: Int64 = Int64(Date().timeIntervalSince1970*1000)) throws -> Backup.Graphic {
        var coordinates: [GeoPoint] = []
        try TrackCodec.visitLocal(data) { coordinates.append(.init(lat: $0.lat,lon: $0.lon)) }
        guard coordinates.count >= 2 else { throw Failure.tooShort }
        let reduced = try simplify(count: coordinates.count,tolerance: 20,maxPoints: 64) { coordinates[coordinates.count-1-$0] }
        return graphic(track: track,reduced: reduced,now: now)
    }
    private static func graphic(track: Backup.TrackMeta,reduced: [GeoPoint],now: Int64) -> Backup.Graphic {
        Backup.Graphic(id: UUID().uuidString.lowercased(),name: String(("Back "+track.name).prefix(20)),type: "route",points: reduced.map { .init(lat: $0.lat,lon: $0.lon) },folder: track.folder,createdAt: now)
    }
}
