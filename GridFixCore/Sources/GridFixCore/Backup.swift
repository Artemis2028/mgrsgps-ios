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

    public struct Graphic: Equatable, Sendable {
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

    public struct TrackMeta: Equatable, Sendable {
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
        let manifest = try encodeManifest(doc)
        var entries = [ZipArchive.Entry(name: manifestName, data: manifest)]
        for (id, data) in doc.trackFiles {
            entries.append(ZipArchive.Entry(name: "tracks/\(id).txt", data: data))
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
        root["settings"] = settings
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
        for e in entries where e.name.hasPrefix("tracks/") && e.name.hasSuffix(".txt") {
            let id = String(e.name.dropFirst("tracks/".count).dropLast(".txt".count))
            if !id.isEmpty { doc.trackFiles[id] = e.data }
        }
        // A track whose points entry is absent is skipped entirely.
        doc.tracks = doc.tracks.filter { doc.trackFiles[$0.id] != nil || $0.pointCount == 0 }
        return doc
    }

    public static func decodeManifest(_ data: Data) throws -> Document {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.notABackup("not an MGRS GPS backup")
        }
        if let v = root["version"] as? Int, v > VERSION {
            throw BackupError.unsupportedVersion(v)
        }
        let exportedAt = int64(root["exportedAt"]) ?? 0
        let waypoints = try (root["waypoints"] as? [[String: Any]] ?? []).map(decodeWaypoint)
        let folders = (root["folders"] as? [[String: Any]] ?? []).compactMap { f -> FolderInfo? in
            guard let name = f["name"] as? String else { return nil }
            return FolderInfo(name: Folders.canonical(name),
                              visible: f["visible"] as? Bool ?? true)
        }
        let graphics = try (root["graphics"] as? [[String: Any]] ?? []).map(decodeGraphic)
        let settings = decodeSettings(root["settings"] as? [String: Any] ?? [:])
        let tracks = (root["tracks"] as? [[String: Any]] ?? []).compactMap(decodeTrack)
        let course = (root["courseHistory"] as? [[String: Any]] ?? []).compactMap(decodeCourse)
        return Document(exportedAt: exportedAt, waypoints: waypoints, folders: folders,
                        graphics: graphics, settings: settings, tracks: tracks,
                        courseHistory: course)
    }

    /// Merge a document into a waypoint store (waypoints + folders only in this slice).
    public static func restoreWaypoints(_ doc: Document, into store: WaypointStore) -> RestoreResult {
        let added = store.merge(waypoints: doc.waypoints, folders: doc.folders)
        return RestoreResult(waypoints: added, graphics: 0, tracks: 0, course: 0,
                             settingsApplied: false)
    }

    // MARK: - Decoders

    private static func decodeWaypoint(_ o: [String: Any]) throws -> Waypoint {
        guard let id = o["id"] as? String else { throw BackupError.missingField("waypoint.id") }
        guard let name = o["name"] as? String else { throw BackupError.missingField("waypoint.name") }
        guard let lat = double(o["lat"]) else { throw BackupError.missingField("waypoint.lat") }
        guard let lon = double(o["lon"]) else { throw BackupError.missingField("waypoint.lon") }
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
            metadata: decodeMetadata(metaObj)
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

    private static func decodeCourse(_ o: [String: Any]) -> CourseResult? {
        guard let name = o["name"] as? String else { return nil }
        let splits = (o["splits"] as? [Any] ?? []).compactMap { int64($0) }
        return CourseResult(
            name: name,
            points: int(o["points"]) ?? 0,
            started: int64(o["started"]) ?? 0,
            total: int64(o["total"]) ?? 0,
            splits: splits
        )
    }

    private static func decodeSettings(_ o: [String: Any]) -> AppSettings {
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
            s.declinationOverride = double(o["declinationOverride"])
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
        case let d as Double: return Int(d)
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }
    private static func int64(_ v: Any?) -> Int64? {
        switch v {
        case let i as Int64: return i
        case let i as Int: return Int64(i)
        case let d as Double: return Int64(d)
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s)
        default: return nil
        }
    }
}
