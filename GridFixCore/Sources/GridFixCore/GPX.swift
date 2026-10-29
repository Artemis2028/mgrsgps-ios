import Foundation

/// GPX interchange matching Android 1.0.4, including continuous track segments
/// and the current MilGPS namespace. Old iOS-exported extensions remain readable.
public enum GPX {
    public static let namespace = "http://www.topografix.com/GPX/1/1"
    public static let milgpsNamespace = "https://milgps.com/gpx/v1"

    public static func build(waypoints: [Waypoint], routes: [Backup.Graphic] = [], tracks: [Track] = []) -> String {
        var xml = header
        for waypoint in waypoints { xml += waypointXML(waypoint) }
        for route in routes where route.type == "route" {
            xml += "<rte><name>\(escape(route.name))</name>"
            for point in route.points { xml += "<rtept \(coordinate(point.lat, point.lon))/>" }
            xml += "</rte>\n"
        }
        for track in tracks {
            xml += "<trk><name>\(escape(track.name))</name><trkseg>"
            for point in track.points {
                xml += "<trkpt \(coordinate(point.lat, point.lon))>"
                if let altitude = point.altitudeMeters, altitude.isFinite { xml += "<ele>\(number(altitude))</ele>" }
                if point.time > 0 { xml += "<time>\(timestamp(point.time))</time>" }
                xml += "</trkpt>"
            }
            xml += "</trkseg></trk>\n"
        }
        return xml + "</gpx>\n"
    }

    private static var header: String { "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"MGRS GPS\" xmlns=\"\(namespace)\" xmlns:milgps=\"\(milgpsNamespace)\">\n" }
    private static func waypointXML(_ waypoint: Waypoint) -> String {
        var xml = ""
        xml += "<wpt \(coordinate(waypoint.lat, waypoint.lon))>"
        if let altitude = waypoint.metadata.elevationMeters, altitude.isFinite { xml += "<ele>\(number(altitude))</ele>" }
        if let time = waypoint.metadata.timestampMillis { xml += "<time>\(timestamp(time))</time>" }
        xml += "<name>\(escape(waypoint.name))</name>"
        if waypoint.metadata.color != nil || waypoint.metadata.milgpsSymbolCode != nil {
            xml += "<extensions>"
            if let code = waypoint.metadata.milgpsSymbolCode { xml += "<milgps:symbolcode>\(code)</milgps:symbolcode>" }
            if let color = waypoint.metadata.color { xml += "<milgps:color>\(escape(color))</milgps:color>" }
            xml += "</extensions>"
        }
        xml += "</wpt>\n"
        return xml
    }

    /// A source visit must validate its complete input before returning. Output
    /// is provisional until write returns; callers discard partial files on error.
    public struct TrackStream: Sendable {
        public let name: String
        let visit: @Sendable (_ point: (TrackPoint) throws -> Void) throws -> Void
        public init(name: String,visit: @escaping @Sendable (_ point: (TrackPoint) throws -> Void) throws -> Void) {
            self.name = name; self.visit = visit
        }
    }
    /// Whole local logs have no import count/byte ceiling. Bound the writer's
    /// buffer, retain exact point order/metadata and check cancellation throughout.
    public static func write(waypoints: [Waypoint],routes: [Backup.Graphic] = [],tracks: [TrackStream] = [],
                             sink: (Data) throws -> Void) throws {
        try Task.checkCancellation()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        var buffer = ""
        func emit(_ text: String) throws {
            try Task.checkCancellation()
            buffer += text
            if buffer.utf8.count >= 64 * 1024 { try sink(Data(buffer.utf8)); buffer = "" }
        }
        try emit(header)
        for waypoint in waypoints { try emit(waypointXML(waypoint)) }
        for route in routes where route.type == "route" {
            try emit("<rte><name>\(escape(route.name))</name>")
            for point in route.points { try emit("<rtept \(coordinate(point.lat,point.lon))/>") }
            try emit("</rte>\n")
        }
        for track in tracks {
            try emit("<trk><name>\(escape(track.name))</name><trkseg>")
            try track.visit { point in
                var xml = "<trkpt \(coordinate(point.lat,point.lon))>"
                if let altitude = point.altitudeMeters,altitude.isFinite { xml += "<ele>\(number(altitude))</ele>" }
                if point.time > 0 { xml += "<time>\(formatter.string(from:Date(timeIntervalSince1970:Double(point.time)/1000)))</time>" }
                try emit(xml + "</trkpt>")
            }
            try emit("</trkseg></trk>\n")
        }
        try emit("</gpx>\n")
        if !buffer.isEmpty { try sink(Data(buffer.utf8)) }
        try Task.checkCancellation()
    }

    public struct Track: Sendable {
        public let name: String
        public let points: [TrackPoint]
        public init(name: String, points: [TrackPoint]) { self.name = name; self.points = points }
    }

    public static func parse(_ xml: String, defaultFolder: String = "Imported",
                              now: Int64 = Int64(Date().timeIntervalSince1970 * 1000),knownFolders: [String] = []) throws -> Backup.Document {
        try parseContents(xml,defaultFolder: defaultFolder).document(now: now,knownFolders: knownFolders)
    }

    static func parseContents(_ xml: String,defaultFolder: String = "Imported",budget: ImportParseBudget = .init()) throws -> InterchangeContents {
        try parseContents(Data(xml.utf8),defaultFolder: defaultFolder,budget: budget)
    }
    static func parseContents(_ bytes: Data,defaultFolder: String = "Imported",budget: ImportParseBudget = .init()) throws -> InterchangeContents {
        guard bytes.count <= ZipArchive.totalLimit else { throw BackupError.notABackup("GPX exceeds 32 MB") }
        let reader = GPXReader(folder: defaultFolder,budget: budget)
        let parser = XMLParser(data: bytes)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let parsed = parser.parse()
        if let failure = reader.failure { throw failure }
        guard parsed, reader.hasRoot, !reader.exceededLimit else { throw BackupError.notABackup("Malformed or oversized GPX") }
        var content = InterchangeContents()
        content.waypoints = reader.waypoints.map { WaypointDraft(name: $0.name,lat: $0.lat,lon: $0.lon,folder: $0.folder,symbol: $0.symbol,
                                                               affiliation: $0.affiliation,echelon: $0.echelon,designation: $0.designation,
                                                               kind: $0.kind,rotation: $0.rotation,metadata: $0.metadata) }
        content.lines = reader.routes.map { .init(name: $0.name,folder: $0.folder,points: $0.points.map { .init(lat: $0.lat,lon: $0.lon) }) }
        content.tracks = reader.tracks
        return content
    }

    public static func parseWaypoints(_ xml: String, defaultFolder: String = "Imported") -> [WaypointDraft] {
        ((try? parse(xml, defaultFolder: defaultFolder))?.waypoints ?? []).map {
            WaypointDraft(name: $0.name, lat: $0.lat, lon: $0.lon, folder: $0.folder, metadata: $0.metadata)
        }
    }

    private static func coordinate(_ lat: Double, _ lon: Double) -> String {
        String(format: "lat=\"%.7f\" lon=\"%.7f\"", locale: Locale(identifier: "en_US_POSIX"), lat, lon)
    }
    private static func number(_ value: Double) -> String { String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value) }
    private static func timestamp(_ millis: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
}

private final class GPXReader: NSObject, XMLParserDelegate {
    struct Element { let name: String; let namespace: String; var text = "" }
    private var stack: [Element] = []
    private let folder: String
    private var pendingWaypoint: Waypoint?
    private var pendingTrackPoint: TrackPoint?
    private var routeName = "", trackName = ""
    private var routePoints: [Backup.GraphicPoint] = []
    private var segment: [TrackPoint] = []
    private var segments: [[TrackPoint]] = []
    private let budget: ImportParseBudget
    var failure: Error?
    var waypoints: [Waypoint] = []
    var routes: [Backup.Graphic] = []
    var tracks: [GPX.Track] = []
    var hasRoot = false
    var exceededLimit = false

    init(folder: String,budget: ImportParseBudget) { self.folder = Folders.canonical(folder); self.budget = budget }
    private func consume(_ parser: XMLParser,_ action: () throws -> Void) -> Bool {
        do { try action(); return true } catch { failure = error; parser.abortParsing(); return false }
    }
    private func gpx(_ uri: String) -> Bool { ["", GPX.namespace, "http://www.topografix.com/GPX/1/0"].contains(uri) }
    private func finishSegment() { if !segment.isEmpty { segments.append(segment) }; segment = [] }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let uri = namespaceURI ?? ""
        stack.append(Element(name: name, namespace: uri))
        guard stack.count <= 64 else { exceededLimit = true; parser.abortParsing(); return }
        if stack.count == 1 { hasRoot = name == "gpx" && gpx(uri) }
        guard gpx(uri), hasRoot, stack.dropLast().allSatisfy({ gpx($0.namespace) }) else { return }
        func coordinate() -> (Double, Double)? {
            guard let lat = Double(attributes["lat"] ?? ""), let lon = Double(attributes["lon"] ?? ""), TrackCodec.validCoordinates(lat, lon) else { return nil }
            return (lat, lon)
        }
        switch (name, stack.count) {
        case ("wpt", 2): pendingWaypoint = coordinate().map { Waypoint(name: "", lat: $0.0, lon: $0.1, folder: folder) }
        case ("rte", 2): routeName = ""; routePoints = []
        case ("rtept", 3) where stack[1].name == "rte":
            if let point = coordinate(), consume(parser,{ try budget.shapePoints() }) { routePoints.append(Backup.GraphicPoint(lat: point.0, lon: point.1)) }
        case ("trk", 2): trackName = ""; segment = []; segments = []
        case ("trkseg", 3) where stack[1].name == "trk": finishSegment()
        case ("trkpt", 4) where stack[2].name == "trkseg": pendingTrackPoint = coordinate().map { TrackPoint(lat: $0.0, lon: $0.1) }
        default: break
        }

    }

    func parser(_ parser: XMLParser,foundCDATA block: Data) { self.parser(parser,foundCharacters: String(decoding: block,as: UTF8.self)) }

    func parser(_ parser: XMLParser, foundCharacters text: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += text
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let element = stack.last else { return }
        let depth = stack.count, text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { stack.removeLast() }
        let parent = depth > 1 ? stack[depth - 2].name : ""
        if depth == 4, parent == "extensions", stack[1].name == "wpt", gpx(stack[1].namespace), gpx(stack[2].namespace),
           [GPX.milgpsNamespace, "http://www.milgps.com"].contains(element.namespace) {
            if name == "color" { pendingWaypoint?.metadata.color = text.isEmpty ? nil : text.lowercased() }
            if name == "symbolcode" { pendingWaypoint?.metadata.milgpsSymbolCode = Int32(text).map(Int.init) }
        }
        guard gpx(element.namespace), stack.dropLast().allSatisfy({ gpx($0.namespace) }) else { return }
        func time() -> Int64? {
            let formatter = ISO8601DateFormatter()
            var date = formatter.date(from: text)
            if date == nil { formatter.formatOptions.insert(.withFractionalSeconds); date = formatter.date(from: text) }
            return date.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        }
        switch (name, depth) {
        case ("name", 3) where parent == "wpt": if pendingWaypoint?.name.isEmpty == true { pendingWaypoint?.name = text }
        case ("ele", 3) where parent == "wpt": pendingWaypoint?.metadata.elevationMeters = Double(text).flatMap { $0.isFinite ? $0 : nil }
        case ("time", 3) where parent == "wpt": pendingWaypoint?.metadata.timestampMillis = time()
        case ("name", 3) where parent == "rte": if routeName.isEmpty { routeName = text }
        case ("name", 3) where parent == "trk": if trackName.isEmpty { trackName = text }
        case ("ele", 5) where parent == "trkpt":
            if let p = pendingTrackPoint { pendingTrackPoint = TrackPoint(lat: p.lat, lon: p.lon, time: p.time, altitudeMeters: Double(text).flatMap { $0.isFinite ? $0 : nil }) }
        case ("time", 5) where parent == "trkpt":
            if let p = pendingTrackPoint { pendingTrackPoint = TrackPoint(lat: p.lat, lon: p.lon, time: time() ?? 0, altitudeMeters: p.altitudeMeters) }
        case ("trkpt", 4): if let point = pendingTrackPoint, consume(parser,{ try budget.trackPoint() }) { segment.append(point) }; pendingTrackPoint = nil
        case ("trkseg", 3): finishSegment()
        case ("wpt", 2):
            if var point = pendingWaypoint, consume(parser,{ try budget.waypoint() }) {
                if point.name.isEmpty { point.name = "WP \(waypoints.count + 1)" }
                waypoints.append(point)
            }
            pendingWaypoint = nil
        case ("rte", 2):
            if routePoints.count >= 2, consume(parser,{ try budget.shape() }) { routes.append(Backup.Graphic(id: UUID().uuidString.lowercased(), name: routeName.isEmpty ? "Imported route" : routeName, type: "route", points: routePoints, folder: folder)) }
        case ("trk", 2):
            finishSegment()
            for (index, points) in segments.enumerated() {
                guard consume(parser,{ try budget.track() }) else { break }
                let base = trackName.isEmpty ? "Imported track" : trackName
                tracks.append(GPX.Track(name: segments.count == 1 ? base : "\(base) — segment \(index + 1)", points: points))
            }
        default: break
        }
    }
}
