import Foundation

public enum LibraryBatchAction: Equatable, Sendable { case swapVisibility, delete }

public struct LibrarySelection: Equatable, Sendable {
    public var waypoints: Set<String> = []
    public var graphics: Set<String> = []
    public var tracks: Set<String> = []
    public init() {}
    public var count: Int { waypoints.count+graphics.count+tracks.count }
    public mutating func retain(waypoints: Set<String>,graphics: Set<String>,tracks: Set<String>) {
        self.waypoints.formIntersection(waypoints); self.graphics.formIntersection(graphics); self.tracks.formIntersection(tracks)
    }
}

public enum LibraryListing {
    /// Android's 25 m buckets prevent GPS noise from constantly reshuffling cards.
    /// Without a fix, retain repository insertion order. Kotlin compares UTF-16 names.
    public static func waypoints(_ input: [Waypoint],folder: String?,origin: GeoPoint?) -> [Waypoint] {
        let listed = input.filter { folder == nil || $0.folder.caseInsensitiveCompare(folder!) == .orderedSame }
        guard let origin else { return listed }
        return listed.enumerated().map { index,point -> (Int,Waypoint,Int) in
            let metres = Float(Geodesy.navInfo(fromLat: origin.lat,fromLon: origin.lon,toLat: point.lat,toLon: point.lon).distanceMeters)
            let bucket = metres.isFinite ? Int(metres/25) : Int.max
            return (index,point,bucket)
        }.sorted { a,b in
            if a.2 != b.2 { return a.2 < b.2 }
            if a.1.name != b.1.name { return a.1.name.utf16.lexicographicallyPrecedes(b.1.name.utf16) }
            return a.0 < b.0
        }.map { $0.1 }
    }
}

public enum LibraryBatches {
    public struct Outcome {
        public let completed: Int
        public let remaining: LibrarySelection
        public let failure: String?
    }
    /// Each repository commits independently, as on Android. Return only the
    /// unfinished IDs, so retrying a partial visibility swap never flips an
    /// already committed waypoint a second time.
    public static func apply(_ selection: LibrarySelection,action: LibraryBatchAction,waypoints: WaypointStore,field: FieldDataStore) -> Outcome {
        var remaining = selection, completed = 0
        remaining.retain(waypoints: Set(waypoints.waypoints.map(\.id)),graphics: Set(field.document.graphics.map(\.id)),tracks: Set(field.document.tracks.map(\.id)))
        do {
            try waypoints.applyLibraryBatch(ids: remaining.waypoints,action: action)
            completed += remaining.waypoints.count; remaining.waypoints = []
            try field.applyLibraryBatch(graphicIDs: remaining.graphics,trackIDs: remaining.tracks,action: action)
            completed += remaining.graphics.count+remaining.tracks.count
            return Outcome(completed: completed,remaining: LibrarySelection(),failure: nil)
        } catch { return Outcome(completed: completed,remaining: remaining,failure: error.localizedDescription) }
    }
}
