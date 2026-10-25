import Foundation

final class ImportArchiveBudget {
    struct Limits {
        var entryBytes = 32*1024*1024
        var totalBytes = 128*1024*1024
        var entries = 2048
    }
    let limits: Limits
    private var total = 0, count = 0
    init(_ limits: Limits = .init()) { self.limits = limits }
    func consume(_ name: String,_ size: Int) throws {
        count += 1; total += size
        guard count <= limits.entries else { throw BackupError.notABackup("Package has too many entries at '\(name)' (limit \(limits.entries))") }
        guard size <= limits.entryBytes else { throw BackupError.notABackup("Package entry '\(name)' exceeds \(limits.entryBytes) bytes") }
        guard total <= limits.totalBytes else { throw BackupError.notABackup("Package exceeds \(limits.totalBytes) decompressed bytes at '\(name)'") }
    }
}

public enum KMZ {
    /// Compressed/container input cap; the decompressed budget remains 128 MiB.
    public static let inputByteLimit = 512*1024*1024
    public static func parse(_ data: Data) throws -> InterchangeContents { try parse(data,budget: .init(),filename: "KMZ",parseBudget: .init()) }
    static func parse(_ data: Data,budget: ImportArchiveBudget,filename: String,parseBudget: ImportParseBudget) throws -> InterchangeContents {
        guard data.count <= inputByteLimit else { throw BackupError.notABackup("Archive input exceeds 512 MB") }
        var content: InterchangeContents?
        try ZipArchive.visit(data,limits: .interchange,beforeEntry: { try budget.consume(filename+"!/"+$0,$1) }) { name,bytes in
            if content == nil, name.lowercased().hasSuffix(".kml"), !name.hasSuffix("/") {
                content = try KML.parse(bytes,budget: parseBudget)
            }
        }
        return content ?? .init()
    }
    public static func build(waypoints: [Waypoint],graphics: [Backup.Graphic],tracks: [GPX.Track]) throws -> Data {
        let xml = KML.build(waypoints: waypoints,graphics: graphics,tracks: tracks)
        guard xml.utf8.count <= KML.byteLimit else { throw BackupError.notABackup("Exported KML exceeds 32 MB; export a smaller library") }
        return ZipArchive.write(entries: [.init(name: "doc.kml",data: Data(xml.utf8))])
    }
}

/// Android's file-based mission-package interoperability, not a TAK network client.
public enum ATAKPackage {
    public static func parse(_ data: Data) throws -> InterchangeContents { try parse(data,budget: .init(),parseBudget: .init()) }
    static func parse(_ data: Data,budget: ImportArchiveBudget,parseBudget: ImportParseBudget) throws -> InterchangeContents {
        guard data.count <= KMZ.inputByteLimit else { throw BackupError.notABackup("Package input exceeds 512 MB") }
        var result = InterchangeContents()
        func append(_ content: InterchangeContents) {
            result.waypoints += content.waypoints; result.lines += content.lines; result.areas += content.areas
            result.tracks += content.tracks; result.skipped += content.skipped
        }
        try ZipArchive.visit(data,limits: .interchange,beforeEntry: { try budget.consume($0,$1) }) { name,bytes in
            guard !name.hasSuffix("/") else { return }
            if name == Backup.manifestName { throw BackupError.notABackup("This is a GridFix backup. Choose Import backup to restore its library and settings.") }
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "cot":
                if let point = CoTReader.read(bytes) { try parseBudget.waypoint(); result.waypoints.append(point) }
                else { result.skipped += 1 }
            case "gpx": append(try GPX.parseContents(bytes,budget: parseBudget))
            case "kml": append(try KML.parse(bytes,budget: parseBudget))
            case "kmz": append(try KMZ.parse(bytes,budget: budget,filename: name,parseBudget: parseBudget))
            default: break // Manifest, images and unrelated files still consume the archive budget.
            }
        }
        return result
    }

    public static func build(waypoints: [Waypoint],routes: [Backup.Graphic],nowMillis: Int64 = Int64(Date().timeIntervalSince1970*1000)) throws -> Data {
        let year: Int64 = 365*24*3600*1000
        guard nowMillis >= 0, nowMillis <= Int64.max-year, waypoints.count <= 10_000, routes.count <= 10_000,
              waypoints.allSatisfy({ TrackCodec.validCoordinates($0.lat,$0.lon) }),
              routes.allSatisfy({ $0.points.allSatisfy { TrackCodec.validCoordinates($0.lat,$0.lon) } }) else { throw BackupError.notABackup("Invalid ATAK package export") }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions.insert(.withFractionalSeconds)
        let time = formatter.string(from: Date(timeIntervalSince1970: Double(nowMillis)/1000)), stale = formatter.string(from: Date(timeIntervalSince1970: Double(nowMillis+year)/1000))
        var members: [ZipArchive.Entry] = []
        for (index,w) in waypoints.enumerated() {
            let type = w.kind == "unit" ? ["friendly":"a-f-G","hostile":"a-h-G","neutral":"a-n-G"][w.affiliation] ?? "a-u-G" : "b-m-p-w"
            let point = String(format: "  <point lat=\"%.7f\" lon=\"%.7f\" hae=\"9999999.0\" ce=\"9999999.0\" le=\"9999999.0\"/>\n",locale: Locale(identifier: "en_US_POSIX"),w.lat,w.lon)
            var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<event version=\"2.0\" uid=\""+KML.escape("GRIDFIX-"+w.id)+"\" type=\""+type+"\" time=\""+time+"\" start=\""+time+"\" stale=\""+stale+"\" how=\"h-g-i-g-o\">\n"+point
            xml += "  <detail>\n    <contact callsign=\""+KML.escape(w.name)+"\"/>\n"
            if !w.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { xml += "    <remarks>"+KML.escape(w.folder)+"</remarks>\n" }
            xml += "  </detail>\n</event>\n"
            members.append(.init(name: "cot/gridfix-\(index).cot",data: Data(xml.utf8)))
        }
        if !routes.isEmpty {
            let gpx = GPX.build(waypoints: [],routes: routes)
            guard gpx.utf8.count <= KML.byteLimit else { throw BackupError.notABackup("Exported routes exceed 32 MB") }
            members.append(.init(name: "routes.gpx",data: Data(gpx.utf8)))
        }
        var manifest = "<MissionPackageManifest version=\"2\">\n  <Configuration>\n    <Parameter name=\"uid\" value=\"gridfix-\(nowMillis)\"/>\n    <Parameter name=\"name\" value=\"MGRS GPS export\"/>\n  </Configuration>\n  <Contents>\n"
        for member in members { manifest += "    <Content ignore=\"false\" zipEntry=\""+KML.escape(member.name)+"\"/>\n" }
        manifest += "  </Contents>\n</MissionPackageManifest>\n"
        members.append(.init(name: "MANIFEST/manifest.xml",data: Data(manifest.utf8)))
        return ZipArchive.write(entries: members)
    }
}

private final class CoTReader: NSObject,XMLParserDelegate {
    private var lat: Double?, lon: Double?
    private var type = "", uid = "", callsign = "", depth = 0, textBytes = 0
    static func read(_ data: Data) -> WaypointDraft? {
        let reader = CoTReader(), parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), let lat = reader.lat, let lon = reader.lon, lat != 0 || lon != 0,
              !["b-m-r","u-d-","b-t-"].contains(where: reader.type.hasPrefix) else { return nil }
        let parts = reader.type.split(separator: "-",omittingEmptySubsequences: false)
        let aff: String
        if parts.count >= 2, parts[0] == "a" {
            aff = ["f":"friendly","a":"friendly","h":"hostile","j":"hostile","k":"hostile","n":"neutral","u":"unknown","p":"unknown","s":"unknown"][parts[1].lowercased()] ?? "none"
        } else { aff = "none" }
        let name = !reader.callsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? reader.callsign : !reader.uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? reader.uid : "ATAK point"
        return .init(name: String(decoding: name.utf16.prefix(30),as: UTF16.self),lat: lat,lon: lon,folder: "Imported",symbol: "target",affiliation: aff)
    }
    func parser(_ parser: XMLParser,didStartElement name: String,namespaceURI: String?,qualifiedName: String?,attributes: [String:String]) {
        depth += 1
        guard depth <= 512 else { parser.abortParsing(); return }
        switch name {
        case "event": type = attributes["type"] ?? ""; uid = attributes["uid"] ?? ""
        case "point": lat = CSV.coordinate(attributes["lat"] ?? "",limit: 90); lon = CSV.coordinate(attributes["lon"] ?? "",limit: 180)
        case "contact": callsign = attributes["callsign"] ?? callsign
        default: break
        }
    }
    func parser(_ parser: XMLParser,didEndElement name: String,namespaceURI: String?,qualifiedName: String?) { depth -= 1 }
    func parser(_ parser: XMLParser,foundCharacters text: String) { textBytes += text.utf8.count; if textBytes > KML.byteLimit { parser.abortParsing() } }
}
