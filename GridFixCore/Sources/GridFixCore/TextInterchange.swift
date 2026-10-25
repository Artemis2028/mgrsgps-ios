import Foundation

public enum TextInterchangeFormat: String,CaseIterable,Sendable {
    case gpx,csv,geojson,kml,kmz,atak
    public var label: String {
        switch self { case .geojson: return "GeoJSON"; case .atak: return "ATAK package"; default: return rawValue.uppercased() }
    }
    public var byteLimit: Int {
        switch self { case .csv,.geojson: return CSV.byteLimit; case .gpx,.kml: return KML.byteLimit; case .kmz,.atak: return KMZ.inputByteLimit }
    }
    public var canPaste: Bool { self != .kmz && self != .atak }
    public var pasteSummary: String {
        switch self { case .csv: return "waypoints"; case .kml,.geojson: return "waypoints, routes and areas"; case .gpx: return "waypoints, routes and tracks"; case .kmz,.atak: return "field data" }
    }
    public var importNote: String {
        switch self {
        case .csv: return "CSV carries waypoint coordinates, folders and supported metadata."
        case .gpx: return "GPX carries waypoints, routes and separate continuous track segments."
        case .geojson: return "Lines become routes and outer polygon rings become areas. Polygon holes and original tactical types are not retained."
        case .kml,.kmz: return "Points become waypoints, lines become routes and polygons become areas. Polygons with holes are rejected. Original symbols, styling and altitude are not retained. KMZ reads its first KML document."
        case .atak: return "Reads CoT markers and bundled GPX/KML/KMZ. CoT routes, drawings, chat reports and unlocated markers are skipped. Export carries waypoints and routes, excluding other graphics and tracks. This opens a file; it does not connect to a TAK server."
        }
    }
}
public struct InterchangePreview: Sendable {
    public let format: TextInterchangeFormat
    public let document: Backup.Document
    public let skipped: Int
    public var recordCount: Int { document.waypoints.count+document.graphics.count+document.tracks.count }
}
public enum TextInterchange {
    public static func fileLimit(filename: String) -> Int {
        switch (filename as NSString).pathExtension.lowercased() {
        case "zip","dpk","kmz": return KMZ.inputByteLimit
        case "csv","geojson","json","txt": return CSV.byteLimit
        default: return KML.byteLimit
        }
    }
    public static func preview(_ data: Data,format hint: TextInterchangeFormat? = nil,filename: String = "",knownFolders: [String] = [],now: Int64 = Int64(Date().timeIntervalSince1970*1000)) throws -> InterchangePreview {
        try Task.checkCancellation()
        guard data.count <= (hint?.byteLimit ?? KMZ.inputByteLimit) else { throw BackupError.notABackup("File exceeds the supported import size") }
        let ext = (filename as NSString).pathExtension.lowercased()
        let format: TextInterchangeFormat
        if let hint { format = hint }
        else if ext == "kmz" { format = .kmz }
        else if ext == "zip" || ext == "dpk" || data.starts(with: [0x50,0x4b]) { format = .atak }
        else if ext == "kml" { format = .kml }
        else if ext == "gpx" { format = .gpx }
        else {
            guard data.count <= KML.byteLimit else { throw BackupError.notABackup("Text import exceeds 32 MB") }
            let decoded = String(data: data,encoding: .utf8) ?? String(data: data,encoding: .utf16) ?? String(decoding: data,as: UTF8.self)
            let head = decoded.replacingOccurrences(of: "\u{FEFF}",with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if head.hasPrefix("{") { format = .geojson }
            else if head.range(of: "<(?:[A-Za-z0-9_]+:)?gpx(?:[\\s/>])",options: .regularExpression) != nil { format = .gpx }
            else if head.range(of: "<(?:[A-Za-z0-9_]+:)?kml(?:[\\s/>])",options: .regularExpression) != nil { format = .kml }
            else if ext == "csv" || ext == "txt" || (!head.hasPrefix("<") && [",",";","\t"].contains(where: { head.prefix(4096).contains($0) })) { format = .csv }
            else { throw BackupError.notABackup("Choose GPX, KML, KMZ, CSV, GeoJSON or an ATAK ZIP/DPK package") }
        }
        guard data.count <= format.byteLimit else { throw BackupError.notABackup("\(format.label) exceeds \(format.byteLimit/(1024*1024)) MB") }
        let content: InterchangeContents
        switch format {
        case .gpx: content = try GPX.parseContents(data)
        case .kml: content = try KML.parse(data)
        case .kmz: content = try KMZ.parse(data)
        case .atak: content = try ATAKPackage.parse(data)
        case .csv: content = try CSV.parse(String(decoding: data,as: UTF8.self))
        case .geojson: content = try GeoJSON.parse(String(decoding: data,as: UTF8.self))
        }
        let document = try content.document(now: now,knownFolders: knownFolders)
        try Task.checkCancellation()
        return .init(format: format,document: document,skipped: content.skipped)
    }
}
