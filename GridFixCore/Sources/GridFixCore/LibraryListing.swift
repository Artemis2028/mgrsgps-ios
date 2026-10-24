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

public enum WaypointSort: String,CaseIterable,Sendable {
    case distance,name,newest
    public var label: String { rawValue.capitalized }
}

public enum LibraryListing {
    /// Android WaypointListing.kt: favourites first, then the chosen stable order.
    /// A missing GPS fix falls back to case-insensitive name, not insertion order.
    public static func waypoints(_ input: [Waypoint],folder: String?,origin: GeoPoint?,query: String = "",sort: WaypointSort = .distance) -> [Waypoint] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let compact = q.replacingOccurrences(of: " ",with: "")
        let listed = input.filter { point in
            guard folder == nil || point.folder.caseInsensitiveCompare(folder!) == .orderedSame else { return false }
            return q.isEmpty || point.name.lowercased().contains(q) || point.folder.lowercased().contains(q)
                || point.designation.lowercased().contains(q)
                || (compact.utf16.count >= 3 && (MGRS.string(lat: point.lat,lon: point.lon,digits: 10)?.lowercased().replacingOccurrences(of: " ",with: "").contains(compact) ?? false))
        }
        return listed.enumerated().map { index,point -> (Int,Waypoint,Int,[UInt32]) in
            let metres: Float? = sort == .distance ? origin.map { Float(Geodesy.navInfo(fromLat: $0.lat,fromLon: $0.lon,toLat: point.lat,toLon: point.lon).distanceMeters) } : nil
            let bucket = metres.flatMap { $0.isFinite ? Int($0/25) : nil } ?? Int.max
            return (index,point,bucket,caseInsensitiveKey(point.name))
        }.sorted { a,b in
            if a.1.favorite != b.1.favorite { return a.1.favorite }
            if sort == .distance, origin != nil, a.2 != b.2 { return a.2 < b.2 }
            if sort == .newest, a.1.createdAt != b.1.createdAt { return a.1.createdAt > b.1.createdAt }
            if a.3 != b.3 { return a.3.lexicographicallyPrecedes(b.3) }
            return a.0 < b.0
        }.map { $0.1 }
    }
    /// Java CASE_INSENSITIVE_ORDER uses simple upper-then-lower case mapping,
    /// including supplementary code points. Avoid locale collation, expansion of ß to SS and
    /// canonical-equivalence comparisons changing Android's stable ties.
    private static func caseInsensitiveKey(_ value: String) -> [UInt32] {
        var result = ""
        for scalar in value.unicodeScalars {
            let upper = String(scalar).uppercased()
            let simple = upper.unicodeScalars.count == 1 ? upper : String(scalar)
            if simple == "İ" { result += "i"; continue }
            let lower = simple.lowercased()
            result += lower.unicodeScalars.count == 1 ? lower : simple
        }
        return result.unicodeScalars.map(\.value)
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
