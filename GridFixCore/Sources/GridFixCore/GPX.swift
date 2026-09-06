import Foundation

/// GPX 1.1 waypoint import/export with optional MilGPS extensions
/// (`xmlns:milgps`), matching Android `InterchangeFiles` at 0.9.31/0.9.32.
public enum GPX {

    public static let namespace = "http://www.topografix.com/GPX/1/1"
    public static let milgpsNamespace = "http://www.milgps.com"

    public static func build(waypoints: [Waypoint]) -> String {
        var sb = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        sb += "<gpx version=\"1.1\" creator=\"MGRS GPS\" xmlns=\"\(namespace)\" xmlns:milgps=\"\(milgpsNamespace)\">\n"
        for w in waypoints {
            sb += String(format: "  <wpt lat=\"%.7f\" lon=\"%.7f\">", w.lat, w.lon)
            if let ele = w.metadata.elevationMeters, ele.isFinite {
                sb += "<ele>\(plain(ele))</ele>"
            }
            if let t = w.metadata.timestampMillis {
                sb += "<time>\(iso8601(t))</time>"
            }
            sb += "<name>\(escape(w.name))</name>"
            let m = w.metadata
            if m.color != nil || m.milgpsSymbolCode != nil {
                sb += "<extensions>"
                if let code = m.milgpsSymbolCode {
                    sb += "<milgps:symbolcode>\(code)</milgps:symbolcode>"
                }
                if let color = m.color {
                    sb += "<milgps:color>\(escape(color))</milgps:color>"
                }
                sb += "</extensions>"
            }
            sb += "</wpt>\n"
        }
        sb += "</gpx>\n"
        return sb
    }

    /// Parse GPX waypoints into drafts. Routes/tracks are ignored in this slice.
    public static func parseWaypoints(_ xml: String,
                                      defaultFolder: String = "Imported") -> [WaypointDraft] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = GPXParser(defaultFolder: defaultFolder)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.shouldProcessNamespaces = true
        xmlParser.parse()
        return parser.waypoints
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func plain(_ d: Double) -> String {
        // Avoid scientific notation for elevations.
        String(format: "%g", d)
    }

    private static func iso8601(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        return ISO8601DateFormatter().string(from: date)
    }
}

private final class GPXParser: NSObject, XMLParserDelegate {
    let defaultFolder: String
    var waypoints: [WaypointDraft] = []

    private var inWpt = false
    private var wptLat = Double.nan
    private var wptLon = Double.nan
    private var name = ""
    private var metadata = WaypointMetadata()
    private var text = ""
    private var inExtensions = false
    private var milgpsLocalName: String?

    init(defaultFolder: String) {
        self.defaultFolder = defaultFolder
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        let local = elementName.contains(":")
            ? String(elementName.split(separator: ":").last!)
            : elementName
        if local == "wpt" {
            inWpt = true
            wptLat = Double(attributes["lat"] ?? "") ?? .nan
            wptLon = Double(attributes["lon"] ?? "") ?? .nan
            name = ""
            metadata = WaypointMetadata()
            inExtensions = false
        } else if inWpt && local == "extensions" {
            inExtensions = true
        } else if inWpt && inExtensions && (namespaceURI == GPX.milgpsNamespace
                                            || elementName.hasPrefix("milgps:")) {
            milgpsLocalName = local.lowercased()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let local = elementName.contains(":")
            ? String(elementName.split(separator: ":").last!)
            : elementName
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inWpt {
            switch local {
            case "name" where !inExtensions:
                if name.isEmpty { name = trimmed }
            case "ele" where !inExtensions:
                if let v = Double(trimmed), v.isFinite {
                    metadata.elevationMeters = v
                }
            case "time" where !inExtensions:
                if let d = ISO8601DateFormatter().date(from: trimmed) {
                    metadata.timestampMillis = Int64(d.timeIntervalSince1970 * 1000)
                }
            case "symbolcode" where inExtensions:
                metadata.milgpsSymbolCode = Int(trimmed)
            case "color" where inExtensions:
                let c = trimmed.lowercased()
                if !c.isEmpty { metadata.color = c }
            case "extensions":
                inExtensions = false
            case "wpt":
                if !wptLat.isNaN && !wptLon.isNaN {
                    let n = name.isEmpty ? "Waypoint" : name
                    waypoints.append(WaypointDraft(
                        name: n, lat: wptLat, lon: wptLon,
                        folder: defaultFolder,
                        metadata: metadata
                    ))
                }
                inWpt = false
            default:
                break
            }
        }
        milgpsLocalName = nil
        text = ""
    }
}
