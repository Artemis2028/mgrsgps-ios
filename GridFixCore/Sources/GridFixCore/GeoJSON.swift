import CoreFoundation
import Foundation

/// Android's geographic interchange contract. `kind` is descriptive on export;
/// imported lines are routes and polygon outer rings are assembly-area graphics.
public enum GeoJSON {
    public static func parse(_ input: String) throws -> InterchangeContents {
        guard input.utf8.count <= CSV.byteLimit else { throw BackupError.notABackup("GeoJSON exceeds 16 MB") }
        let text = input.hasPrefix("\u{FEFF}") ? String(input.dropFirst()) : input
        guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw BackupError.notABackup("GeoJSON root must be an object") }
        var result = InterchangeContents(), pointCount = 0
        func vertex(_ raw: Any?) -> GeoPoint? {
            guard let a = raw as? [Any], a.count >= 2, let lon = number(a[0]), let lat = number(a[1]), TrackCodec.validCoordinates(lat,lon) else { return nil }
            return .init(lat: lat,lon: lon)
        }
        func line(_ raw: Any?) throws -> [GeoPoint] {
            guard let a = raw as? [Any] else { return [] }
            pointCount += a.count
            guard pointCount <= 250_000 else { throw BackupError.notABackup("Too many GeoJSON points") }
            return a.compactMap { value in if let p = vertex(value) { return p }; result.skipped += 1; return nil }
        }
        func check() throws {
            guard result.waypoints.count+result.lines.count+result.areas.count <= 10_000 else { throw BackupError.notABackup("Too many GeoJSON features") }
        }
        func geometry(_ g: [String: Any]?,name: String,folder: String,elevation: Double?,depth: Int = 0) throws {
            guard let g else { result.skipped += 1; return }
            guard depth <= 4 else { result.skipped += 1; return }
            let c = g["coordinates"] as? [Any]
            switch g["type"] as? String {
            case "Point":
                if let point = vertex(c) {
                    let height = elevation ?? (c.flatMap { $0.count > 2 ? number($0[2]) : nil })
                    result.waypoints.append(.init(name: name,lat: point.lat,lon: point.lon,folder: folder,metadata: .init(elevationMeters: height)))
                } else { result.skipped += 1 }
            case "MultiPoint":
                for (i,raw) in (c ?? []).enumerated() {
                    if let point = vertex(raw) { result.waypoints.append(.init(name: (c?.count ?? 0)>1 ? "\(name) \(i+1)" : name,lat: point.lat,lon: point.lon,folder: folder)) }
                    else { result.skipped += 1 }
                    try check()
                }
            case "LineString":
                let points = try line(c); if points.count >= 2 { result.lines.append(.init(name: name,folder: folder,points: points)) } else { result.skipped += 1 }
            case "MultiLineString":
                for raw in c ?? [] {
                    let points = try line(raw); if points.count >= 2 { result.lines.append(.init(name: name,folder: folder,points: points)) } else { result.skipped += 1 }
                    try check()
                }
            case "Polygon", "MultiPolygon":
                let polygons: [[Any]] = (g["type"] as? String) == "Polygon" ? [c ?? []] : (c ?? []).compactMap { $0 as? [Any] }
                for polygon in polygons {
                    result.skipped += max(0,polygon.count-1)
                    var points = try line(polygon.first)
                    if points.count > 1, points.first == points.last { points.removeLast() }
                    if points.count >= 3 { result.areas.append(.init(name: name,folder: folder,points: points)) } else { result.skipped += 1 }
                    try check()
                }
            case "GeometryCollection":
                for raw in g["geometries"] as? [Any] ?? [] { try geometry(raw as? [String: Any],name: name,folder: folder,elevation: elevation,depth: depth+1) }
            default: result.skipped += 1
            }
            try check()
        }
        func feature(_ f: [String: Any],index: Int) throws {
            let p = f["properties"] as? [String: Any] ?? [:]
            func property(_ keys: [String]) -> String? {
                keys.compactMap { string(p[$0]) }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "null" }
            }
            let name = String((property(["name","title","Name","label","id"]) ?? "Feature \(index+1)").prefix(120))
            let folder = String((property(["folder","overlay","group","layer"]) ?? "Imported").prefix(60))
            let elevation = ["elevation","ele","elevation_m"].compactMap { number(p[$0]) }.first
            try geometry(f["geometry"] as? [String: Any],name: name,folder: folder,elevation: elevation)
        }
        switch root["type"] as? String {
        case "FeatureCollection":
            let features = root["features"] as? [Any] ?? []
            guard features.count <= 10_000 else { throw BackupError.notABackup("Too many GeoJSON features") }
            for (index,value) in features.enumerated() { if let f = value as? [String: Any] { try feature(f,index: index) } else { result.skipped += 1 } }
        case "Feature": try feature(root,index: 0)
        default: try geometry(root,name: "Feature 1",folder: "Imported",elevation: nil)
        }
        return result
    }
    public static func build(waypoints: [Waypoint],graphics: [Backup.Graphic],tracks: [GPX.Track]) throws -> String {
        var features: [[String: Any]] = []
        func position(_ lat: Double,_ lon: Double) -> [Double] { [floor(lon*1e7+0.5)/1e7,floor(lat*1e7+0.5)/1e7] }
        func feature(_ geometry: [String: Any],_ properties: [String: Any]) -> [String: Any] { ["type":"Feature","geometry":geometry,"properties":properties] }
        for w in waypoints {
            var props: [String: Any] = ["name":w.name,"kind":"waypoint","folder":w.folder]
            props["mgrs"] = MGRS.parts(lat: w.lat,lon: w.lon,digits: 10)?.full
            props["elevation"] = w.metadata.elevationMeters.flatMap { $0.isFinite ? $0 : nil }; props["color"] = w.metadata.color
            features.append(feature(["type":"Point","coordinates":position(w.lat,w.lon)],props))
        }
        for g in graphics {
            guard let shape = GraphicExportGeometry.make(g), let first = shape.points.first else { continue }
            var coords = shape.points.map { position($0.lat,$0.lon) }
            let geometry: [String: Any]
            if shape.area, shape.points.count >= 3 {
                if shape.points.first != shape.points.last { coords.append(position(first.lat,first.lon)) }
                geometry = ["type":"Polygon","coordinates":[coords]]
            } else if coords.count >= 2 { geometry = ["type":"LineString","coordinates":coords] }
            else { geometry = ["type":"Point","coordinates":position(first.lat,first.lon)] }
            features.append(feature(geometry,["name":GraphicExportGeometry.prefix(g.type)+g.name,"kind":g.type,"folder":g.folder]))
        }
        for track in tracks where track.points.count >= 2 {
            features.append(feature(["type":"LineString","coordinates":track.points.map { position($0.lat,$0.lon) }],["name":track.name,"kind":"track"]))
        }
        let data = try JSONSerialization.data(withJSONObject: ["type":"FeatureCollection","features":features],options: [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
        return String(decoding: data,as: UTF8.self)+"\n"
    }
    private static func number(_ raw: Any?) -> Double? {
        if let text = raw as? String { return Double(text).flatMap { $0.isFinite ? $0 : nil } }
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static func string(_ raw: Any?) -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue }
        return nil
    }
}
