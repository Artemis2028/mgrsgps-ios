import Foundation

/// Tactical control measures, and their GeoJSON.
///
/// The 30-graphic platoon field set the Android app draws — phase lines,
/// boundaries, objectives, engagement areas, obstacles. MapLibre consumes them
/// on both platforms as a GeoJSON source with line, fill and symbol layers, so
/// the encoding lives here rather than in either app.
///
/// The geometry rule mirrors the Android KML exporter exactly. The same graphic
/// exported two ways and coming back as two different shapes is a data bug the
/// user only finds after a round trip through someone else's app, so both
/// platforms are held to the `graphicGeometry` table in `golden.json`.
public struct TacGraphic: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    /// One of ``GraphicTypes/all``.
    public let type: String
    public let points: [GeoPoint]
    public let folder: String
    public let affiliation: String
    public let echelon: String

    public init(id: String, name: String, type: String, points: [GeoPoint],
                folder: String = Folders.defaultFolder,
                affiliation: String = "none", echelon: String = "") {
        self.id = id
        self.name = name
        self.type = type
        self.points = points
        self.folder = folder
        self.affiliation = affiliation
        self.echelon = echelon
    }
}

public enum GraphicTypes {

    /// Type key, label, minimum vertices. Identical to the Android table.
    public static let all: [(key: String, label: String, minPoints: Int)] = [
        ("phase_line", "Phase line", 2),
        ("boundary", "Boundary", 2),
        ("axis", "Axis of advance", 2),
        ("doa", "Direction of attack", 2),
        ("objective", "Objective", 3),
        ("aa", "Assembly area", 3),
        ("route", "Route", 2),
        ("lz", "Landing zone", 3),
        ("pz", "Pickup zone", 3),
        ("bp", "Battle position", 3),
        ("ea", "Engagement area", 3),
        ("nai", "NAI", 3),
        ("tai", "TAI", 3),
        ("area", "Area (sketch)", 3),
        ("screen_l", "Screen line", 2),
        ("guard_l", "Guard line", 2),
        ("cover_l", "Cover line", 2),
        ("flot", "FLOT", 2),
        ("obstacle_line", "Obstacle line", 2),
        ("wire", "Wire obstacle", 2),
        ("lane", "Lane", 2),
        ("minefield", "Minefield", 3),
        ("strongpoint", "Strongpoint", 3),
        ("roadblock", "Roadblock", 1),
        ("ring", "Range ring", 2),
        ("sector", "Sector of fire", 3),
        ("trp", "Target ref point", 1),
        ("checkpoint", "Checkpoint", 1),
        ("dp", "Decision point", 1),
        ("text", "Text label", 1),
    ]

    /// The types that close into a polygon once they have three vertices.
    /// A sector of fire needs three points but stays open, which is why this
    /// is its own list rather than "anything with minPoints 3".
    public static let areaTypes: Set<String> = [
        "objective", "aa", "lz", "pz", "area", "bp", "ea", "nai", "tai",
        "minefield", "strongpoint",
    ]

    public static func isArea(_ type: String) -> Bool { areaTypes.contains(type) }

    public static func label(_ type: String) -> String {
        all.first { $0.key == type }?.label ?? type
    }

    public static func minPoints(_ type: String) -> Int {
        all.first { $0.key == type }?.minPoints ?? 2
    }
}

public extension TacGraphic {

    /// Point / LineString / Polygon, or nil when there is nothing to draw.
    ///
    /// Nil matters. A graphic with no vertices has no valid GeoJSON geometry;
    /// emitting a Point with an empty coordinate array produces a document that
    /// fails to parse, and one bad feature takes the whole layer down with it.
    static func geometryKind(type: String, vertexCount: Int) -> String? {
        if vertexCount <= 0 { return nil }
        if vertexCount == 1 { return "Point" }
        if GraphicTypes.isArea(type) && vertexCount >= 3 { return "Polygon" }
        return "LineString"
    }

    var geometryKind: String? {
        Self.geometryKind(type: type, vertexCount: points.count)
    }

    /// One GeoJSON Feature, or nil when the graphic has no geometry.
    func geoJSONFeature() -> String? {
        guard let kind = geometryKind else { return nil }
        let geometry: String
        switch kind {
        case "Point":
            geometry = "{\"type\":\"Point\",\"coordinates\":\(lonLat(points[0]))}"
        case "Polygon":
            // A GeoJSON ring must close: repeat the first vertex last.
            let ring = points + [points[0]]
            geometry = "{\"type\":\"Polygon\",\"coordinates\":[[\(ring.map(lonLat).joined(separator: ","))]]}"
        default:
            geometry = "{\"type\":\"LineString\",\"coordinates\":[\(points.map(lonLat).joined(separator: ","))]}"
        }
        return "{\"type\":\"Feature\",\"geometry\":\(geometry),\"properties\":{"
            + "\"id\":\(jsonString(id)),"
            + "\"name\":\(jsonString(name)),"
            + "\"tacType\":\(jsonString(type)),"
            + "\"folder\":\(jsonString(folder)),"
            + "\"affiliation\":\(jsonString(affiliation)),"
            + "\"echelon\":\(jsonString(echelon))}}"
    }

    private func lonLat(_ p: GeoPoint) -> String {
        String(format: "[%.7f,%.7f]", locale: Locale(identifier: "en_US_POSIX"), p.lon, p.lat)
    }
}

public extension Array where Element == TacGraphic {
    /// A whole overlay as one FeatureCollection, ready for `MLNShapeSource`.
    /// Graphics with no geometry drop out rather than poisoning the document.
    func geoJSON() -> Data {
        let features = compactMap { $0.geoJSONFeature() }.joined(separator: ",")
        return Data("{\"type\":\"FeatureCollection\",\"features\":[\(features)]}".utf8)
    }
}

/// JSON string escaping. Every control character has to go: a raw tab or
/// newline inside a JSON string is invalid, and a user is perfectly capable of
/// pasting one into a graphic name.
func jsonString(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        default:
            if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    return out + "\""
}
