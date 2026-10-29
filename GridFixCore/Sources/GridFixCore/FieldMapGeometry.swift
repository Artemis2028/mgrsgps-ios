import Foundation

public enum FieldMapGeometry {
    public struct OverlaySnapshot: Sendable {
        public let data: Data
        /// Exact fit extrema, independent of the sampled drawing path.
        public let points: [GeoPoint]
        public let routes: Int
        public let tracks: Int
    }

    /// Android TracksOverlay uses count / 1500 stride plus the final point.
    /// Draw only that preview; retain all local bytes and all geographic bounds.
    public static func prepareOverlay(document: Backup.Document,folders: [FolderInfo]) throws -> OverlaySnapshot {
        try Task.checkCancellation()
        let hidden = Set(folders.filter { !$0.visible }.map { $0.name.lowercased() })
        var extent = FitExtent(),features: [[String:Any]] = []
        var routes = 0,tracks = 0
        for graphic in document.graphics where graphic.visible && !hidden.contains(graphic.folder.lowercased()) {
            try Task.checkCancellation()
            let points = graphic.mapExtentPoints
            guard !points.isEmpty else { continue }
            guard points.allSatisfy({ TrackCodec.validCoordinates($0.lat,$0.lon) }) else { throw BackupError.notABackup("Invalid map graphic coordinates") }
            if graphic.type == "route" { routes += 1 }
            for point in points { extent.include(point) }
        }
        for track in document.tracks where track.visible && !hidden.contains(track.folder.lowercased()) {
            try Task.checkCancellation()
            let count: Int
            if let bytes = document.trackFiles[track.id] { count = try TrackCodec.countLocalRows(bytes) }
            else {
                var actual = 0
                try document.visitTrackPoints(track.id) { _ in actual += 1 }
                count = actual
            }
            let step = max(1,count/1500)
            var sampled: [GeoPoint] = [],index = 0
            // One validated point at a time: long logs need no full decoded array.
            try document.visitTrackPoints(track.id) { point in
                defer { index += 1 }
                guard count >= 2 else { return }
                let coordinate = GeoPoint(lat: point.lat,lon: point.lon)
                extent.include(coordinate)
                if index % step == 0 || index == count-1 { sampled.append(coordinate) }
            }
            guard count >= 2 else { continue }
            tracks += 1
            let segments = lineSegments(sampled).filter { $0.count >= 2 }
            features.append(["type":"Feature","geometry":["type":"MultiLineString","coordinates":segments.map { $0.map { [$0.lon,$0.lat] } }],
                             "properties":["id":track.id,"name":track.name,"kind":"track"]])
            if let first = sampled.first {
                features.append(["type":"Feature","geometry":["type":"Point","coordinates":[first.lon,first.lat]],
                                 "properties":["id":track.id,"name":track.name,"kind":"label"]])
            }
        }
        try Task.checkCancellation()
        let data = try JSONSerialization.data(withJSONObject: ["type":"FeatureCollection","features":features])
        try Task.checkCancellation()
        return .init(data: data,points: extent.points,routes: routes,tracks: tracks)
    }

    /// Exact camera extent of every validated saved row, with constant output
    /// space. A single-point log still has a useful camera location.
    public static func trackFitPoints(_ data: Data) throws -> [GeoPoint] {
        try trackFitPoints(visit: { try TrackCodec.visitLocal(data,point: $0) })
    }

    public static func trackFitPoints(visit: (_ point: (TrackPoint) throws -> Void) throws -> Void) throws -> [GeoPoint] {
        var extent = FitExtent()
        try visit { extent.include(.init(lat: $0.lat,lon: $0.lon)) }
        return extent.points
    }

    private struct FitExtent {
        var south: GeoPoint?,north: GeoPoint?,west: GeoPoint?,east: GeoPoint?,wrappedWest: GeoPoint?,wrappedEast: GeoPoint?
        private func wrapped(_ point: GeoPoint) -> Double { point.lon < 0 ? point.lon+360 : point.lon }
        mutating func include(_ point: GeoPoint) {
            if south == nil || point.lat < south!.lat { south = point }
            if north == nil || point.lat > north!.lat { north = point }
            if west == nil || point.lon < west!.lon { west = point }
            if east == nil || point.lon > east!.lon { east = point }
            if wrappedWest == nil || wrapped(point) < wrapped(wrappedWest!) { wrappedWest = point }
            if wrappedEast == nil || wrapped(point) > wrapped(wrappedEast!) { wrappedEast = point }
        }
        var points: [GeoPoint] { [south,north,west,east,wrappedWest,wrappedEast].compactMap { $0 } }
    }
    public static func lineSegments(_ points: [GeoPoint]) -> [[GeoPoint]] {
        guard let first = points.first else { return [] }
        var segments = [[first]]
        for point in points.dropFirst() {
            let previous = segments[segments.count - 1].last!
            let delta = point.lon - previous.lon
            if abs(delta) > 180 {
                let unwrapped = point.lon + (delta > 0 ? -360 : 360)
                let edge = unwrapped > previous.lon ? 180.0 : -180.0
                let latitude = previous.lat + (point.lat - previous.lat) * (edge - previous.lon) / (unwrapped - previous.lon)
                segments[segments.count - 1].append(GeoPoint(lat: latitude, lon: edge))
                segments.append([GeoPoint(lat: latitude, lon: -edge), point])
            } else { segments[segments.count - 1].append(point) }
        }
        return segments
    }

    public static func geoJSON(document: Backup.Document, folders: [FolderInfo]) throws -> (data: Data, points: [GeoPoint], routes: Int, tracks: Int) {
        let hidden = Set(folders.filter { !$0.visible }.map { $0.name.lowercased() })
        var features: [[String: Any]] = []
        var allPoints: [GeoPoint] = []
        var routeCount = 0, trackCount = 0
        func line(_ points: [GeoPoint]) -> [String: Any] {
            let segments = lineSegments(points)
            return ["type": "MultiLineString", "coordinates": segments.filter { $0.count >= 2 }.map { $0.map { [$0.lon, $0.lat] } }]
        }
        func add(_ geometry: [String: Any], id: String, name: String, kind: String, points: [GeoPoint]) {
            features.append(["type": "Feature", "geometry": geometry, "properties": ["id": id, "name": name, "kind": kind]])
            allPoints += points
            if let first = points.first {
                features.append(["type": "Feature", "geometry": ["type": "Point", "coordinates": [first.lon, first.lat]],
                                 "properties": ["id": id, "name": name, "kind": "label"]])
            }
        }
        for graphic in document.graphics where graphic.visible && !hidden.contains(graphic.folder.lowercased()) {
            let points = graphic.points.map { GeoPoint(lat: $0.lat, lon: $0.lon) }
            guard let first = points.first else { continue }
            let geometry: [String: Any]
            if GraphicTypes.isArea(graphic.type), points.count >= 3 {
                geometry = ["type": "Polygon", "coordinates": [(points + [first]).map { [$0.lon, $0.lat] }]]
            } else if points.count == 1 { geometry = ["type": "Point", "coordinates": [first.lon, first.lat]] }
            else { geometry = line(points) }
            let kind = graphic.type == "route" ? "route" : "graphic"
            if kind == "route" { routeCount += 1 }
            add(geometry, id: graphic.id, name: graphic.name, kind: kind, points: points)
        }
        for track in document.tracks where track.visible && !hidden.contains(track.folder.lowercased()) {
            let points = try TrackCodec.decodeLocal(document.trackData(track.id)).map { GeoPoint(lat: $0.lat, lon: $0.lon) }
            guard points.count >= 2 else { continue }
            trackCount += 1
            add(line(points), id: track.id, name: track.name, kind: "track", points: points)
        }
        return (try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features]), allPoints, routeCount, trackCount)
    }

    /// Shorter circular longitude interval for the map's fit action. MapLibre
    /// explicitly accepts bounds beyond ±180 for antimeridian-spanning data.
    public static func bounds(_ points: [GeoPoint]) -> (south: Double, north: Double, west: Double, east: Double)? {
        guard let first = points.first else { return nil }
        var south = first.lat, north = first.lat, west = first.lon, east = first.lon
        var wrappedWest = first.lon < 0 ? first.lon + 360 : first.lon, wrappedEast = wrappedWest
        for point in points {
            south = min(south, point.lat); north = max(north, point.lat)
            west = min(west, point.lon); east = max(east, point.lon)
            let wrapped = point.lon < 0 ? point.lon + 360 : point.lon
            wrappedWest = min(wrappedWest, wrapped); wrappedEast = max(wrappedEast, wrapped)
        }
        return wrappedEast - wrappedWest < east - west ? (south, north, wrappedWest, wrappedEast) : (south, north, west, east)
    }
}
