import Foundation

/// Complete, bounded visible-field overlay. No basemap tiles, phone fix, live recorder or alert state.
public struct WatchMapSnapshot: Codable, Equatable, Sendable {
    public static let contextKey = "gridfix.map.v1"
    public static let maxEncodedBytes = 48 * 1024
    public static let maxWaypoints = 150
    public static let maxFeatures = 64
    public static let maxLinePoints = 160
    public static let maxAreaPoints = 256
    public var version = 1
    public var updatedAt: Date
    public var sourceID: String
    public var revision: Int64
    public var waypoints: [Point] = []
    public var features: [Feature] = []
    /// Optional for version-1 cache compatibility; nil is a complete empty lane replacement.
    public var lanes: [WatchLaneOverlay]?
    public var laneOverlays: [WatchLaneOverlay] { lanes ?? [] }
    public var omittedItems = 0
    public var simplifiedItems = 0

    public struct Point: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var coordinate: GeoPoint
        public var symbol: String
        public var affiliation: String
        public var echelon: String
        public var rotation: Double
        public var importedCode: Int?
        public var importedColor: String?
    }
    public struct Feature: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        /// graphic, track, boundary. Boundary is the phone's displayed monitor area, without alert state.
        public var kind: String
        public var name: String
        public var type: String
        public var affiliation: String
        public var echelon: String
        public var points: [GeoPoint]
        public var originalPointCount: Int
        public var simplified: Bool
        /// Optional additive v1 field. Each retained vertex's exact original ordinal.
        public var routeVertexIndices: [Int]? = nil
        public var routeLegLabels: [String]? {
            guard kind == "graphic", type == "route" else { return nil }
            guard let indices = routeVertexIndices else {
                return simplified ? nil : (1..<points.count).map(String.init)
            }
            guard validRouteIndices else { return nil }
            return zip(indices,indices.dropFirst()).map { a,b in a + 1 == b ? String(b) : "\(a+1)–\(b)" }
        }
        public var validRouteIndices: Bool {
            guard let indices = routeVertexIndices else { return true }
            return kind == "graphic" && type == "route" && points.count >= 2 && originalPointCount >= points.count && indices.count == points.count
                && indices.first == 0 && indices.last == originalPointCount-1
                && zip(indices,indices.dropFirst()).allSatisfy { $0 < $1 }
        }
        public var renderID: String { kind + ":" + id }
        public var isArea: Bool { kind == "boundary" || GraphicTypes.isArea(type) }
    }

    public init(updatedAt: Date = Date(), sourceID: String = "local", revision: Int64 = 0) {
        self.updatedAt = updatedAt; self.sourceID = sourceID; self.revision = revision
    }
    public func shouldApply(over cached: Self?) -> Bool {
        guard let cached, cached.sourceID == sourceID else { return true }
        return revision > cached.revision || (revision == cached.revision && self == cached)
    }
    public static func validCoordinate(_ point: GeoPoint) -> Bool {
        point.lat.isFinite && point.lon.isFinite && abs(point.lat) <= 85 && abs(point.lon) <= 180
    }
    public var isValid: Bool {
        version == 1 && updatedAt.timeIntervalSince1970.isFinite && !sourceID.isEmpty && sourceID.count <= 64 && revision >= 0 && omittedItems >= 0 && simplifiedItems >= 0
        && waypoints.count <= Self.maxWaypoints && features.count <= Self.maxFeatures
        && laneOverlays.count <= 8 && Set(laneOverlays.map(\.id)).count == laneOverlays.count && laneOverlays.allSatisfy(\.isValid)
        && Set(waypoints.map(\.id)).count == waypoints.count && Set(features.map(\.renderID)).count == features.count
        && waypoints.allSatisfy { !$0.id.isEmpty && $0.id.count <= 120 && $0.name.count <= 80
            && $0.symbol.count <= 80 && $0.affiliation.count <= 24 && $0.echelon.count <= 24
            && $0.rotation.isFinite && Self.validCoordinate($0.coordinate) && ($0.importedColor?.count ?? 0) <= 24 }
        && features.allSatisfy { !$0.id.isEmpty && $0.id.count <= 120 && $0.name.count <= 80
            && ["graphic", "track", "boundary"].contains($0.kind) && $0.type.count <= 40
            && $0.affiliation.count <= 24 && $0.echelon.count <= 24 && !$0.points.isEmpty
            && $0.points.count <= Self.maxAreaPoints && $0.originalPointCount >= $0.points.count
            && $0.validRouteIndices && $0.points.allSatisfy(Self.validCoordinate)
            && ($0.kind != "track" || ($0.type == "track" && $0.points.count >= 2))
            && ($0.kind != "boundary" || $0.type == "area")
            && ($0.kind != "graphic" || $0.points.count >= GraphicTypes.minPoints($0.type))
            && (!$0.isArea || ($0.points.count >= 3 && !$0.simplified && !WatchMapGeometry.crossesDateline($0.points, closed: true)))
            && ($0.type != "sector" || WatchMapGeometry.sectorOutline($0.points) != nil) }
    }
    public func encoded() -> Data? {
        guard isValid, let data = try? JSONEncoder().encode(self), data.count <= Self.maxEncodedBytes else { return nil }
        return data
    }
    public static func decode(_ data: Data) -> Self? {
        guard data.count <= maxEncodedBytes, let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }

    public static func build(waypoints source: [Waypoint], folders: [FolderInfo], document: Backup.Document,
                             boundary: BoundaryArea? = nil, lanes: [NavLane] = [], date: Date = Date(), sourceID: String = "local", revision: Int64 = 0) -> Self {
        var result = Self(updatedAt: date, sourceID: sourceID, revision: revision)
        let hidden = Set(folders.filter { !$0.visible }.map { Folders.canonical($0.name).lowercased() })
        func shown(_ folder: String) -> Bool { !hidden.contains(Folders.canonical(folder).lowercased()) }
        func short(_ value: String, _ limit: Int = 80) -> String { String(value.prefix(limit)) }
        result.lanes = []
        var laneIDs = Set<String>()
        for lane in lanes where lane.visible && shown(lane.folder) {
            guard result.laneOverlays.count < 8,laneIDs.insert(lane.id).inserted,let overlay = WatchLaneOverlay.build(lane,graphics: document.graphics,waypoints:source) else { result.omittedItems += 1; continue }
            result.lanes?.append(overlay)
        }
        var pointIDs = Set<String>(), featureIDs = Set<String>()
        for point in source where point.visible && shown(point.folder) {
            let id = short(point.id, 120), coordinate = GeoPoint(lat: point.lat, lon: point.lon)
            guard !id.isEmpty, validCoordinate(coordinate), point.rotation.isFinite,
                  result.waypoints.count < maxWaypoints, pointIDs.insert(id).inserted else { result.omittedItems += 1; continue }
            result.waypoints.append(.init(id: id, name: short(point.name), coordinate: coordinate,
                                         symbol: short(point.symbol), affiliation: short(point.affiliation, 24),
                                         echelon: short(point.echelon, 24), rotation: point.rotation,
                                         importedCode: point.metadata.milgpsSymbolCode, importedColor: point.metadata.color.map { short($0, 24) }))
        }
        func add(id rawID: String, kind: String, name: String, type: String, affiliation: String,
                 echelon: String, points original: [GeoPoint]) {
            let id = short(rawID, 120), area = kind == "boundary" || GraphicTypes.isArea(type)
            let minimum = kind == "boundary" ? 3 : kind == "track" ? 2 : GraphicTypes.minPoints(type)
            guard !id.isEmpty, original.count >= minimum, original.allSatisfy(validCoordinate),
                  result.features.count < maxFeatures, featureIDs.insert(kind + ":" + id).inserted,
                  (!area || ((3...maxAreaPoints).contains(original.count) && !WatchMapGeometry.crossesDateline(original, closed: true))),
                  (type != "sector" || WatchMapGeometry.sectorOutline(original) != nil) else { result.omittedItems += 1; return }
            let indices = area || original.count <= maxLinePoints ? Array(original.indices) : ((try? TrackBacktrack.retainedIndices(original, tolerance: 0, maxPoints: maxLinePoints)) ?? [])
            let sampled = indices.map { original[$0] }
            guard !sampled.isEmpty else { result.omittedItems += 1; return }
            let simplified = sampled.count != original.count
            if simplified { result.simplifiedItems += 1 }
            result.features.append(.init(id: id, kind: kind, name: short(name), type: short(type, 40),
                                         affiliation: short(affiliation, 24), echelon: short(echelon, 24),
                                         points: sampled, originalPointCount: original.count, simplified: simplified,
                                         routeVertexIndices: kind == "graphic" && type == "route" ? indices : nil))
        }
        for graphic in document.graphics where graphic.visible && shown(graphic.folder) {
            add(id: graphic.id, kind: "graphic", name: graphic.name, type: graphic.type, affiliation: graphic.affiliation,
                echelon: graphic.echelon, points: graphic.points.map { .init(lat: $0.lat, lon: $0.lon) })
        }
        for track in document.tracks where track.visible && shown(track.folder) {
            guard result.features.count < maxFeatures,
                  let bytes = try? document.trackData(track.id,maximumBytes:2 * 1024 * 1024),
                  let points = try? TrackCodec.decode(bytes), points.count >= 2 else { result.omittedItems += 1; continue }
            add(id: track.id, kind: "track", name: track.name, type: "track", affiliation: "none", echelon: "",
                points: points.map { .init(lat: $0.lat, lon: $0.lon) })
        }
        if let boundary {
            add(id: boundary.id, kind: "boundary", name: boundary.name, type: "area", affiliation: "none", echelon: "", points: boundary.vertices)
        }
        // Enforce an application budget before handing the dictionary to WatchConnectivity.
        // Never send a prefix that looks like a complete area or an unmarked truncated library.
        while result.encoded() == nil {
            if let removed = result.features.popLast() {
                if removed.simplified { result.simplifiedItems -= 1 }
            } else if result.waypoints.popLast() == nil {
                if result.lanes?.popLast() == nil { break }
            }
            result.omittedItems += 1
        }
        return result
    }
}
