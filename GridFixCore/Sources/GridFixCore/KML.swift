import Foundation

/// Geographic KML interchange, matching Android's scoped MultiGeometry reader.
/// Polygon holes are rejected; an unsupported outline is never silently filled.
public enum KML {
    public static let byteLimit = 32*1024*1024
    public static func parse(_ xml: String) throws -> InterchangeContents { try parse(xml,budget: .init()) }
    static func parse(_ xml: String,budget: ImportParseBudget) throws -> InterchangeContents {
        try parse(Data(xml.utf8),budget: budget)
    }
    public static func parse(_ bytes: Data) throws -> InterchangeContents { try parse(bytes,budget: .init()) }
    static func parse(_ bytes: Data,budget: ImportParseBudget) throws -> InterchangeContents {
        guard bytes.count <= byteLimit else { throw BackupError.notABackup("KML exceeds 32 MB") }
        let reader = KMLReader(budget: budget), parser = XMLParser(data: bytes)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = reader
        let success = parser.parse()
        if let error = reader.failure { throw error }
        guard success, reader.hasRoot else { throw BackupError.notABackup("Malformed KML") }
        return reader.result
    }
    public static func build(waypoints: [Waypoint],graphics: [Backup.Graphic],tracks: [GPX.Track]) -> String {
        var output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document>\n<name>MGRS GPS export</name>\n"
        func placemark(_ name: String,_ points: [GeoPoint],area: Bool,forceLine: Bool = false) -> String {
            guard !points.isEmpty || forceLine else { return "" }
            let first = points.first
            var text = "<Placemark><name>"+escape(name)+"</name>"
            if points.count == 1 && !forceLine { text += "<Point><coordinates>"+position(first!)+"</coordinates></Point>" }
            else {
                var coords = points.map(position)
                if area, let first, first != points.last { coords.append(position(first)) }
                let content = coords.joined(separator: " ")
                text += area ? "<Polygon><outerBoundaryIs><LinearRing><coordinates>"+content+"</coordinates></LinearRing></outerBoundaryIs></Polygon>" : "<LineString><tessellate>1</tessellate><coordinates>"+content+"</coordinates></LineString>"
            }
            return text+"</Placemark>\n"
        }
        // Kotlin groupBy preserves the first occurrence of each folder.
        var folders: [String] = [], groups: [String:[Waypoint]] = [:]
        for point in waypoints {
            if groups[point.folder] == nil { folders.append(point.folder) }
            groups[point.folder,default: []].append(point)
        }
        for folder in folders {
            output += "<Folder><name>"+escape(folder)+"</name>\n"
            for point in groups[folder] ?? [] { output += placemark(point.name,[.init(lat: point.lat,lon: point.lon)],area: false) }
            output += "</Folder>\n"
        }
        if !graphics.isEmpty {
            output += "<Folder><name>Graphics</name>\n"
            for g in graphics {
                if let shape = GraphicExportGeometry.make(g) { output += placemark(GraphicExportGeometry.prefix(g.type)+g.name,shape.points,area: shape.area) }
            }
            output += "</Folder>\n"
        }
        if !tracks.isEmpty {
            output += "<Folder><name>Tracks</name>\n"
            for track in tracks { output += placemark(track.name,track.points.map { .init(lat: $0.lat,lon: $0.lon) },area: false,forceLine: true) }
            output += "</Folder>\n"
        }
        return output+"</Document></kml>\n"
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&",with: "&amp;").replacingOccurrences(of: "<",with: "&lt;")
            .replacingOccurrences(of: ">",with: "&gt;").replacingOccurrences(of: "\"",with: "&quot;")
    }
    private static func position(_ point: GeoPoint) -> String { String(format: "%.7f,%.7f,0",locale: Locale(identifier: "en_US_POSIX"),point.lon,point.lat) }
}

private final class KMLReader: NSObject,XMLParserDelegate {
    enum Role { case container,folder,folderName,placemark,placemarkName,multi,point,line,polygon,outer,ring,coordinates,ignored }
    struct Geometry { var type: Role; var points: [GeoPoint] }
    struct Frame {
        var role: Role
        var name = "", text = "", folder = "Imported"
        var points: [GeoPoint] = []
        var geometries: [Geometry] = []
    }
    let budget: ImportParseBudget
    var result = InterchangeContents(), hasRoot = false
    var failure: Error?
    private var stack: [Frame] = []
    private var textBytes = 0
    init(budget: ImportParseBudget) { self.budget = budget }
    private func supported(_ namespace: String?) -> Bool {
        ["","http://www.opengis.net/kml/2.2","http://earth.google.com/kml/2.0","http://earth.google.com/kml/2.1","http://earth.google.com/kml/2.2"].contains(namespace ?? "")
    }
    private func fail(_ error: Error,_ parser: XMLParser) { failure = error; parser.abortParsing() }
    private func geometry(_ name: String) -> Role {
        ["MultiGeometry":Role.multi,"Point":.point,"LineString":.line,"Polygon":.polygon][name] ?? .ignored
    }
    func parser(_ parser: XMLParser,didStartElement name: String,namespaceURI: String?,qualifiedName: String?,attributes: [String:String]) {
        guard failure == nil else { return }
        guard stack.count < 512 else { fail(BackupError.notABackup("KML XML nesting is too deep"),parser); return }
        var role = Role.ignored
        if stack.isEmpty { hasRoot = name == "kml" && supported(namespaceURI); role = hasRoot ? .container : .ignored }
        else if supported(namespaceURI), let parent = stack.last?.role {
            switch parent {
            case .container,.folder:
                if name == "Folder" { role = .folder }
                else if name == "Document" { role = .container }
                else if name == "Placemark" { role = .placemark }
                else if name == "name", parent == .folder { role = .folderName }
            case .placemark: role = name == "name" ? .placemarkName : geometry(name)
            case .multi: role = geometry(name)
            case .point,.line,.ring: if name == "coordinates" { role = .coordinates }
            case .polygon:
                if name == "innerBoundaryIs" { fail(BackupError.notABackup("KML polygons with holes are not supported"),parser); return }
                if name == "outerBoundaryIs" { role = .outer }
            case .outer: if name == "LinearRing" { role = .ring }
            default: break
            }
        }
        if [.multi,.point,.line,.polygon].contains(role), stack.filter({ $0.role == .multi }).count > 64 {
            fail(BackupError.notABackup("KML geometry nesting is too deep"),parser); return
        }
        var frame = Frame(role: role)
        if role == .placemark { frame.folder = stack.reversed().first { $0.role == .folder && !$0.name.isEmpty }?.name ?? "Imported" }
        stack.append(frame)
    }
    func parser(_ parser: XMLParser,foundCDATA block: Data) { self.parser(parser,foundCharacters: String(decoding: block,as: UTF8.self)) }
    func parser(_ parser: XMLParser,foundCharacters text: String) {
        guard failure == nil, let role = stack.last?.role, [.folderName,.placemarkName,.coordinates].contains(role) else { return }
        textBytes += text.utf8.count
        guard textBytes <= KML.byteLimit else { fail(BackupError.notABackup("Expanded KML text exceeds 32 MB"),parser); return }
        stack[stack.count-1].text += text
    }
    func parser(_ parser: XMLParser,didEndElement name: String,namespaceURI: String?,qualifiedName: String?) {
        guard failure == nil, let frame = stack.popLast() else { return }
        do {
            switch frame.role {
            case .folderName,.placemarkName:
                if !stack.isEmpty { stack[stack.count-1].name = frame.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .coordinates:
                var points: [GeoPoint] = []
                for token in frame.text.split(whereSeparator: \.isWhitespace) {
                    let parts = token.split(separator: ",",omittingEmptySubsequences: false)
                    if parts.count >= 2, let lon = Double(parts[0]), let lat = Double(parts[1]), TrackCodec.validCoordinates(lat,lon) {
                        guard points.count <= budget.pointLimit else { throw BackupError.notABackup("Too many KML geometry points") }
                        points.append(.init(lat: lat,lon: lon))
                    } else { result.skipped += 1 }
                }
                if stack.last?.role == .ring, points.count >= 2, points.first == points.last { points.removeLast() }
                if !stack.isEmpty { stack[stack.count-1].points = points }
            case .ring,.outer:
                if !stack.isEmpty { stack[stack.count-1].points = frame.points }
            case .point,.line,.polygon:
                let valid = frame.role == .point ? frame.points.count == 1 : frame.points.count >= (frame.role == .line ? 2 : 3)
                if valid, let i = stack.lastIndex(where: { $0.role == .placemark }) {
                    if frame.role == .point { try budget.waypoint() }
                    else { try budget.shape(); try budget.shapePoints(frame.points.count) }
                    stack[i].geometries.append(.init(type: frame.role,points: frame.points))
                } else { result.skipped += 1 }
            case .placemark:
                for g in frame.geometries {
                    if g.type == .point, let p = g.points.first {
                        result.waypoints.append(.init(name: frame.name.isEmpty ? "WP \(result.waypoints.count+1)" : frame.name,lat: p.lat,lon: p.lon,folder: frame.folder))
                    } else if g.type == .line { result.lines.append(.init(name: frame.name.isEmpty ? "Imported line" : frame.name,folder: frame.folder,points: g.points)) }
                    else { result.areas.append(.init(name: frame.name.isEmpty ? "Imported area" : frame.name,folder: frame.folder,points: g.points)) }
                }
            default: break
            }
        } catch { fail(error,parser) }
    }
}
