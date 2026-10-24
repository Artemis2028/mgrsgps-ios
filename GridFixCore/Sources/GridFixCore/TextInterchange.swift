import Foundation

public enum TextInterchangeFormat: String,CaseIterable,Sendable {
    case gpx,csv,geojson
    public var label: String { self == .geojson ? "GeoJSON" : rawValue.uppercased() }
    public var byteLimit: Int { self == .gpx ? 32*1024*1024 : CSV.byteLimit }
}
public struct InterchangePreview: Sendable {
    public let format: TextInterchangeFormat
    public let document: Backup.Document
    public let skipped: Int
    public var recordCount: Int { document.waypoints.count+document.graphics.count+document.tracks.count }
}
public enum TextInterchange {
    public static func preview(_ data: Data,format hint: TextInterchangeFormat? = nil,filename: String = "",knownFolders: [String] = [],now: Int64 = Int64(Date().timeIntervalSince1970*1000)) throws -> InterchangePreview {
        try Task.checkCancellation()
        guard data.count <= (hint?.byteLimit ?? 32*1024*1024) else { throw BackupError.notABackup("File exceeds the supported text import size") }
        let text = String(decoding: data,as: UTF8.self)
        let format: TextInterchangeFormat
        if let hint { format = hint }
        else {
            let head = text.replacingOccurrences(of: "\u{FEFF}",with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if head.hasPrefix("{") { format = .geojson }
            else if head.range(of: "<(?:[A-Za-z0-9_]+:)?gpx(?:[\\s/>])",options: .regularExpression) != nil { format = .gpx }
            else if filename.lowercased().hasSuffix(".csv") || (!head.hasPrefix("<") && [",",";","\t"].contains(where: { head.prefix(4096).contains($0) })) { format = .csv }
            else { throw BackupError.notABackup("Choose a GPX, CSV or GeoJSON file") }
        }
        guard data.count <= format.byteLimit else { throw BackupError.notABackup("\(format.label) exceeds \(format.byteLimit/(1024*1024)) MB") }
        switch format {
        case .gpx:
            let document = try GPX.parse(text,now: now,knownFolders: knownFolders)
            try Task.checkCancellation()
            return .init(format: format,document: document,skipped: 0)
        case .csv,.geojson:
            let content = try format == .csv ? CSV.parse(text) : GeoJSON.parse(text)
            let document = try content.document(now: now,knownFolders: knownFolders)
            try Task.checkCancellation()
            return .init(format: format,document: document,skipped: content.skipped)
        }
    }
}
