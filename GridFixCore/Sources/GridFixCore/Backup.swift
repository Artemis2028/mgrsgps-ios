import Foundation

/// Whole-app backup as one zip: JSON snapshot of waypoints, folders, graphics,
/// settings, tracks metadata and course history, plus optional track point files.
///
/// Spec: `docs/backup-format-v1.md`. Restore is additive and id-keyed.
public enum Backup {

    public static let VERSION = 1
    public static let manifestName = "gridfix-backup.json"

    public struct AppSettings: Equatable, Sendable {
        public var nightMode: Bool = false
        public var keepScreenOn: Bool = true
        public var mgrsDigits: Int = 10
        public var latLonFormat: Int = 1
        public var units: Int = 0
        public var angleUnit: Int = 0
        public var northRef: Int = 0
        public var pacePer100m: Int = 65
        public var face: Int = 1
        public var orientation: Int = 0
        public var disclaimerAccepted: Bool = false
        /// Nil means unset — never conflate with 0.0° (a real meridian value).
        public var declinationOverride: Double? = nil

        public init() {}
    }

    public struct GraphicPoint: Equatable, Sendable {
        public var lat: Double
        public var lon: Double
        public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    }

    public struct Graphic: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var type: String
        /// `[lat, lon]` pairs — opposite of GeoJSON order.
        public var points: [GraphicPoint]
        public var folder: String
        public var affiliation: String
        public var createdAt: Int64
        public var echelon: String
        public var visible: Bool

        public init(id: String, name: String, type: String,
                    points: [GraphicPoint],
                    folder: String = Folders.defaultFolder,
                    affiliation: String = "none",
                    createdAt: Int64 = 0,
                    echelon: String = "",
                    visible: Bool = true) {
            self.id = id; self.name = name; self.type = type
            self.points = points; self.folder = folder
            self.affiliation = affiliation; self.createdAt = createdAt
            self.echelon = echelon; self.visible = visible
        }
    }

    public struct TrackMeta: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var startedAt: Int64
        public var endedAt: Int64
        public var distanceM: Double
        public var pointCount: Int
        public var folder: String
        public var visible: Bool

        public init(id: String, name: String, startedAt: Int64, endedAt: Int64,
                    distanceM: Double, pointCount: Int,
                    folder: String = Folders.defaultFolder, visible: Bool = true) {
            self.id = id; self.name = name
            self.startedAt = startedAt; self.endedAt = endedAt
            self.distanceM = distanceM; self.pointCount = pointCount
            self.folder = folder; self.visible = visible
        }
    }

    public struct CourseResult: Equatable, Sendable {
        public var name: String
        public var points: Int
        public var started: Int64
        public var total: Int64
        public var splits: [Int64]

        public init(name: String, points: Int, started: Int64, total: Int64, splits: [Int64]) {
            self.name = name; self.points = points
            self.started = started; self.total = total; self.splits = splits
        }
    }

    public struct Document: Equatable, Sendable {
        public var exportedAt: Int64
        public var waypoints: [Waypoint]
        public var folders: [FolderInfo]
        public var graphics: [Graphic]
        public var settings: AppSettings
        public var tracks: [TrackMeta]
        public var courseHistory: [CourseResult]
        /// Track id → raw points file bytes (lat lon time alt lines).
        public var trackFiles: [String: Data]
        public var hasSettings: Bool = true

        public init(exportedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                    waypoints: [Waypoint] = [],
                    folders: [FolderInfo] = [],
                    graphics: [Graphic] = [],
                    settings: AppSettings = AppSettings(),
                    tracks: [TrackMeta] = [],
                    courseHistory: [CourseResult] = [],
                    trackFiles: [String: Data] = [:]) {
            self.exportedAt = exportedAt
            self.waypoints = waypoints
            self.folders = folders
            self.graphics = graphics
            self.settings = settings
            self.tracks = tracks
            self.courseHistory = courseHistory
            self.trackFiles = trackFiles
        }
    }

    public struct RestoreResult: Equatable, Sendable {
        public var waypoints: Int
        public var graphics: Int
        public var tracks: Int
        public var course: Int
        public var settingsApplied: Bool

        public init(waypoints: Int, graphics: Int, tracks: Int, course: Int, settingsApplied: Bool) {
            self.waypoints = waypoints; self.graphics = graphics
            self.tracks = tracks; self.course = course
            self.settingsApplied = settingsApplied
        }
    }

    // MARK: - Export

    public static func exportZip(_ doc: Document) throws -> Data {
        try validate(doc)
        let manifest = try encodeManifest(doc)
        var entries = [ZipArchive.Entry(name: manifestName, data: manifest)]
        for (id, data) in doc.trackFiles {
            entries.append(ZipArchive.Entry(name: "tracks/\(id).txt", data: data))
        }
        guard entries.count <= 512, manifest.count <= ZipArchive.manifestLimit,
              entries.allSatisfy({ $0.data.count <= ZipArchive.entryLimit }),
              entries.reduce(0, { $0 + $1.data.count }) <= ZipArchive.totalLimit else {
            throw BackupError.notABackup("Backup exceeds supported size limits")
        }
        return ZipArchive.write(entries: entries)
    }

    public static func encodeManifest(_ doc: Document) throws -> Data {
        let root = NSMutableDictionary()
        root["app"] = "GridFix"
        root["version"] = VERSION
        root["exportedAt"] = doc.exportedAt

        root["waypoints"] = doc.waypoints.map { w -> [String: Any] in
            var d: [String: Any] = [
                "id": w.id, "name": w.name,
                "lat": w.lat, "lon": w.lon,
                "createdAt": w.createdAt, "folder": w.folder,
                "symbol": w.symbol, "affiliation": w.affiliation,
                "echelon": w.echelon, "designation": w.designation,
                "kind": w.kind, "rotation": w.rotation,
                "visible": w.visible,
            ]
            d["metadata"] = metadataJSON(w.metadata)
            d["sourceRouteId"] = w.sourceRouteId
            d["sourceRoutePointIndex"] = w.sourceRoutePointIndex
            return d
        }
        root["folders"] = doc.folders.map { ["name": $0.name, "visible": $0.visible] as [String: Any] }
        root["graphics"] = doc.graphics.map { g -> [String: Any] in
            [
                "id": g.id, "name": g.name, "type": g.type,
                "points": g.points.map { [$0.lat, $0.lon] as [Double] },
                "folder": g.folder, "affiliation": g.affiliation,
                "createdAt": g.createdAt, "echelon": g.echelon,
                "visible": g.visible,
            ]
        }
        var settings: [String: Any] = [
            "nightMode": doc.settings.nightMode,
            "keepScreenOn": doc.settings.keepScreenOn,
            "mgrsDigits": doc.settings.mgrsDigits,
            "latLonFormat": doc.settings.latLonFormat,
            "units": doc.settings.units,
            "angleUnit": doc.settings.angleUnit,
            "northRef": doc.settings.northRef,
            "pacePer100m": doc.settings.pacePer100m,
            "face": doc.settings.face,
            "orientation": doc.settings.orientation,
            "disclaimerAccepted": doc.settings.disclaimerAccepted,
        ]
        if let d = doc.settings.declinationOverride {
            settings["declinationOverride"] = d
        } else {
            settings["declinationOverride"] = NSNull()
        }
        if doc.hasSettings { root["settings"] = settings }
        root["tracks"] = doc.tracks.map { t -> [String: Any] in
            [
                "id": t.id, "name": t.name,
                "startedAt": t.startedAt, "endedAt": t.endedAt,
                "distanceM": t.distanceM, "pointCount": t.pointCount,
                "folder": t.folder, "visible": t.visible,
            ]
        }
        root["courseHistory"] = doc.courseHistory.map { r -> [String: Any] in
            [
                "name": r.name, "points": r.points,
                "started": r.started, "total": r.total,
                "splits": r.splits,
            ]
        }

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Import

    public static func importZip(_ data: Data) throws -> Document {
        let entries = try ZipArchive.read(data)
        guard let manifest = entries.first(where: { $0.name == manifestName })?.data else {
            throw BackupError.notABackup("not an MGRS GPS backup")
        }
        var doc = try decodeManifest(manifest)
        for entry in entries where entry.name.hasPrefix("tracks/") {
            guard entry.name.hasSuffix(".txt") else { throw BackupError.notABackup("Invalid track filename") }
            let id = String(entry.name.dropFirst(7).dropLast(4))
            guard TrackCodec.validID(id) else { throw BackupError.notABackup("Invalid track ID") }
            doc.trackFiles[id] = entry.data
        }
        try validate(doc)
        for index in doc.tracks.indices {
            let points = try TrackCodec.decode(doc.trackFiles[doc.tracks[index].id] ?? Data())
            doc.tracks[index].pointCount = points.count
            doc.tracks[index].distanceM = TrackCodec.distance(points)
        }
        return doc
    }

    public static func decodeManifest(_ data: Data) throws -> Document {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.notABackup("not an MGRS GPS backup")
        }
        guard let version = root["version"] as? Int, version == VERSION else {
            throw BackupError.unsupportedVersion(root["version"] as? Int ?? 0)
        }
        guard ["GridFix", "MGRS GPS"].contains(root["app"] as? String ?? "") else {
            throw BackupError.notABackup("Not an MGRS GPS backup")
        }
        for key in ["waypoints", "folders", "graphics", "tracks", "courseHistory"] {
            guard root[key] == nil || root[key] is [[String: Any]], (root[key] as? [Any])?.count ?? 0 <= 10_000 else {
                throw BackupError.notABackup("Invalid or oversized \(key) section")
            }
        }
        guard root["settings"] == nil || root["settings"] is [String: Any] else { throw BackupError.notABackup("Invalid settings section") }
        let exportedAt = int64(root["exportedAt"]) ?? 0
        let waypoints = try (root["waypoints"] as? [[String: Any]] ?? []).map(decodeWaypoint)
        let folders = try (root["folders"] as? [[String: Any]] ?? []).map { f -> FolderInfo in
            guard let name = f["name"] as? String else { throw BackupError.missingField("folder.name") }
            return FolderInfo(name: Folders.canonical(name),
                              visible: f["visible"] as? Bool ?? true)
        }
        let graphics = try (root["graphics"] as? [[String: Any]] ?? []).map(decodeGraphic)
        let settings = try decodeSettings(root["settings"] as? [String: Any] ?? [:])
        let tracks = try (root["tracks"] as? [[String: Any]] ?? []).map { record -> TrackMeta in
            guard let track = decodeTrack(record) else { throw BackupError.missingField("track.id/name") }
            return track
        }
        let course = try (root["courseHistory"] as? [[String: Any]] ?? []).map { record -> CourseResult in
            try decodeCourse(record)
        }
        var document = Document(exportedAt: exportedAt, waypoints: waypoints, folders: folders,
                                graphics: graphics, settings: settings, tracks: tracks, courseHistory: course)
        document.hasSettings = root["settings"] != nil
        try validate(document, includingTrackFiles: false)
        return document
    }

    /// Merge a document into a waypoint store (waypoints + folders only in this slice).
    public static func restoreWaypoints(_ doc: Document, into store: WaypointStore) -> RestoreResult {
        let added = store.merge(waypoints: doc.waypoints, folders: doc.folders)
        return RestoreResult(waypoints: added, graphics: 0, tracks: 0, course: 0,
                             settingsApplied: false)
    }

    public static func validate(_ doc: Document, includingTrackFiles: Bool = true) throws {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw BackupError.notABackup(message) }
        }
        func ids(_ values: [String]) -> Bool {
            values.count <= 10_000 && Set(values).count == values.count
                && values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 256 }
        }
        try require(ids(doc.waypoints.map(\.id)) && ids(doc.graphics.map(\.id)) && ids(doc.tracks.map(\.id)), "Duplicate or invalid record IDs")
        try require(doc.folders.count <= 10_000, "Too many folders")
        for point in doc.waypoints {
            try require(TrackCodec.validCoordinates(point.lat, point.lon) && point.rotation.isFinite
                        && (point.sourceRoutePointIndex.map { $0 >= 0 } ?? true), "Invalid waypoint coordinates or route ownership")
        }
        try require(doc.graphics.reduce(0) { $0 + $1.points.count } <= 250_000, "Too many graphic vertices")
        for graphic in doc.graphics {
            try require(graphic.points.count >= GraphicTypes.minPoints(graphic.type)
                        && graphic.points.allSatisfy { TrackCodec.validCoordinates($0.lat, $0.lon) }, "Invalid graphic vertices")
        }
        let s = doc.settings
        if doc.hasSettings {
            try require([4,6,8,10].contains(s.mgrsDigits) && (0...2).contains(s.latLonFormat)
                        && (0...2).contains(s.units) && (0...1).contains(s.angleUnit) && (0...2).contains(s.northRef)
                        && (1...1000).contains(s.pacePer100m) && (0...2).contains(s.face) && (0...3).contains(s.orientation)
                        && (s.declinationOverride.map { $0.isFinite && (-180...180).contains($0) } ?? true), "Invalid settings in backup")
        }
        try require(doc.courseHistory.count <= 10_000 && doc.courseHistory.allSatisfy {
            $0.points >= 0 && $0.started >= 0 && $0.total >= 0 && $0.splits.count <= 10_000 && $0.splits.allSatisfy { $0 >= 0 }
        }, "Invalid course history")
        var totalPoints = 0
        for track in doc.tracks {
            try require(TrackCodec.validID(track.id) && track.pointCount >= 0 && track.distanceM.isFinite && track.distanceM >= 0, "Invalid track metadata")
            if includingTrackFiles {
                try require(doc.trackFiles[track.id] != nil || track.pointCount == 0, "Missing points for track \(track.name)")
                let points = try TrackCodec.decode(doc.trackFiles[track.id] ?? Data())
                totalPoints += points.count
                try require(totalPoints <= 250_000, "Too many backup track points")
            }
        }
        if includingTrackFiles {
            try require(Set(doc.trackFiles.keys).isSubset(of: Set(doc.tracks.map(\.id))), "Track file is missing from manifest")
        }
    }

    // MARK: - Decoders

    private static func decodeWaypoint(_ o: [String: Any]) throws -> Waypoint {
        guard let id = o["id"] as? String else { throw BackupError.missingField("waypoint.id") }
        guard let name = o["name"] as? String else { throw BackupError.missingField("waypoint.name") }
        guard let lat = double(o["lat"]) else { throw BackupError.missingField("waypoint.lat") }
        guard let lon = double(o["lon"]) else { throw BackupError.missingField("waypoint.lon") }
        if let rawIndex = o["sourceRoutePointIndex"], !(rawIndex is NSNull), int(rawIndex) == nil {
            throw BackupError.notABackup("Invalid route point index")
        }
        let metaObj = o["metadata"] as? [String: Any]
        return Waypoint(
            id: id, name: name, lat: lat, lon: lon,
            createdAt: int64(o["createdAt"]) ?? 0,
            folder: Folders.canonical(o["folder"] as? String),
            symbol: o["symbol"] as? String ?? DEFAULT_SYMBOL,
            affiliation: o["affiliation"] as? String ?? "none",
            echelon: o["echelon"] as? String ?? "",
            designation: o["designation"] as? String ?? "",
            kind: o["kind"] as? String ?? KIND_WP,
            rotation: double(o["rotation"]) ?? 0,
            visible: o["visible"] as? Bool ?? true,
            metadata: decodeMetadata(metaObj),
            sourceRouteId: o["sourceRouteId"] as? String,
            sourceRoutePointIndex: int(o["sourceRoutePointIndex"])
        )
    }

    private static func decodeGraphic(_ o: [String: Any]) throws -> Graphic {
        guard let id = o["id"] as? String else { throw BackupError.missingField("graphic.id") }
        guard let name = o["name"] as? String else { throw BackupError.missingField("graphic.name") }
        guard let type = o["type"] as? String else { throw BackupError.missingField("graphic.type") }
        guard let rawPts = o["points"] as? [[Any]] else { throw BackupError.missingField("graphic.points") }
        let points: [GraphicPoint] = try rawPts.map { pair in
            guard pair.count >= 2, let la = double(pair[0]), let lo = double(pair[1]) else {
                throw BackupError.missingField("graphic.points")
            }
            return GraphicPoint(lat: la, lon: lo)
        }
        return Graphic(
            id: id, name: name, type: type, points: points,
            folder: Folders.canonical(o["folder"] as? String),
            affiliation: o["affiliation"] as? String ?? "none",
            createdAt: int64(o["createdAt"]) ?? 0,
            echelon: o["echelon"] as? String ?? "",
            visible: o["visible"] as? Bool ?? true
        )
    }

    private static func decodeTrack(_ o: [String: Any]) -> TrackMeta? {
        guard let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
        return TrackMeta(
            id: id, name: name,
            startedAt: int64(o["startedAt"]) ?? 0,
            endedAt: int64(o["endedAt"]) ?? 0,
            distanceM: double(o["distanceM"]) ?? 0,
            pointCount: int(o["pointCount"]) ?? 0,
            folder: Folders.canonical(o["folder"] as? String),
            visible: o["visible"] as? Bool ?? true
        )
    }

    private static func decodeCourse(_ o: [String: Any]) throws -> CourseResult {
        guard let name = o["name"] as? String, let points = int(o["points"]),
              let started = int64(o["started"]), let total = int64(o["total"]),
              let rawSplits = o["splits"] as? [Any] else { throw BackupError.missingField("course result") }
        let splits = try rawSplits.map { value -> Int64 in
            guard let split = int64(value) else { throw BackupError.notABackup("Invalid course split") }
            return split
        }
        return CourseResult(
            name: name,
            points: points,
            started: started,
            total: total,
            splits: splits
        )
    }

    private static func decodeSettings(_ o: [String: Any]) throws -> AppSettings {
        var s = AppSettings()
        s.nightMode = o["nightMode"] as? Bool ?? false
        s.keepScreenOn = o["keepScreenOn"] as? Bool ?? true
        s.mgrsDigits = int(o["mgrsDigits"]) ?? 10
        s.latLonFormat = int(o["latLonFormat"]) ?? 1
        s.units = int(o["units"]) ?? 0
        s.angleUnit = int(o["angleUnit"]) ?? 0
        s.northRef = int(o["northRef"]) ?? 0
        s.pacePer100m = int(o["pacePer100m"]) ?? 65
        s.face = int(o["face"]) ?? 1
        s.orientation = int(o["orientation"]) ?? 0
        s.disclaimerAccepted = o["disclaimerAccepted"] as? Bool ?? false
        if o["declinationOverride"] is NSNull || o["declinationOverride"] == nil {
            s.declinationOverride = nil
        } else {
            guard let degrees = double(o["declinationOverride"]) else { throw BackupError.notABackup("Invalid declination override") }
            s.declinationOverride = degrees
        }
        return s
    }

    private static func decodeMetadata(_ o: [String: Any]?) -> WaypointMetadata {
        guard let o else { return WaypointMetadata() }
        let color = (o["color"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return WaypointMetadata(
            color: (color?.isEmpty == false) ? color : nil,
            milgpsSymbolCode: int(o["milgpsSymbolCode"]),
            elevationMeters: double(o["elevationMeters"]),
            timestampMillis: int64(o["timestampMillis"])
        )
    }

    private static func metadataJSON(_ m: WaypointMetadata) -> [String: Any] {
        var d: [String: Any] = [:]
        if let c = m.color { d["color"] = c }
        if let s = m.milgpsSymbolCode { d["milgpsSymbolCode"] = s }
        if let e = m.elevationMeters, e.isFinite { d["elevationMeters"] = e }
        if let t = m.timestampMillis { d["timestampMillis"] = t }
        return d
    }

    private static func double(_ v: Any?) -> Double? {
        switch v {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let i as Int64: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
    private static func int(_ v: Any?) -> Int? {
        switch v {
        case let i as Int: return i
        case let i as Int64: return Int(i)
        case let d as Double: return d.isFinite ? Int(exactly: d) : nil
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }
    private static func int64(_ v: Any?) -> Int64? {
        switch v {
        case let i as Int64: return i
        case let i as Int: return Int64(i)
        case let d as Double: return d.isFinite ? Int64(exactly: d) : nil
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s)
        default: return nil
        }
    }
}
