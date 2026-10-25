import Foundation

/// Android eacf084's indexed name/place review. This does not mutate a store or
/// replace the content-derived IDs used for safe retry after partial publication.
public enum ImportDuplicates {
    public struct Check: Sendable {
        public let total: Int
        public let duplicates: Int
        public let withoutDuplicates: InterchangeContents
    }
    public static func check(_ data:InterchangeContents,waypoints:[Waypoint],graphics:[Backup.Graphic],tracks:[Backup.TrackMeta]) throws -> Check {
        func key(_ name:String)->String { name.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() }
        func near(_ a:Double,_ b:Double,_ c:Double,_ d:Double)->Bool { abs(a-c)<1e-5 && abs(b-d)<1e-5 }
        func sameLine(_ points:[GeoPoint],_ graphic:Backup.Graphic)->Bool {
            graphic.points.count == points.count && zip(points,graphic.points).allSatisfy { near($0.lat,$0.lon,$1.lat,$1.lon) }
        }
        try Task.checkCancellation()
        let wpByName=Dictionary(grouping:waypoints,by:{key($0.name)})
        let graphicsByName=Dictionary(grouping:graphics,by:{key($0.name)})
        let tracksByName=Dictionary(grouping:tracks,by:{key($0.name)})
        var kept=data
        kept.waypoints=try data.waypoints.filter { point in
            try Task.checkCancellation()
            return !(wpByName[key(point.name)] ?? []).contains { near($0.lat,$0.lon,point.lat,point.lon) }
        }
        func shapes(_ values:[InterchangeContents.Shape]) throws -> [InterchangeContents.Shape] {
            try values.filter { shape in
                try Task.checkCancellation()
                return !(graphicsByName[key(shape.name)] ?? []).contains { sameLine(shape.points,$0) }
            }
        }
        kept.lines=try shapes(data.lines);kept.areas=try shapes(data.areas)
        kept.tracks=try data.tracks.filter { track in
            try Task.checkCancellation()
            let candidates=(tracksByName[key(track.name)] ?? []).filter {$0.pointCount == track.points.count}
            guard !candidates.isEmpty else {return true}
            let length=TrackCodec.distance(track.points)
            return !candidates.contains {abs($0.distanceM-length)<1}
        }
        let total=data.waypoints.count+data.lines.count+data.areas.count+data.tracks.count
        let retained=kept.waypoints.count+kept.lines.count+kept.areas.count+kept.tracks.count
        try Task.checkCancellation()
        return .init(total:total,duplicates:total-retained,withoutDuplicates:kept)
    }
}
