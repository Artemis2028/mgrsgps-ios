import Foundation

/// Android TabularFormats.kt: flexible waypoint columns and RFC4180-style quoting.
public enum CSV {
    public static let byteLimit = 16*1024*1024
    private static let name = Set(["name","title","label","waypoint","wpt","id","description"])
    private static let lat = Set(["lat","latitude","y","lat_dd","latitude_dd"])
    private static let lon = Set(["lon","lng","long","longitude","x","lon_dd","longitude_dd"])
    private static let grid = Set(["mgrs","usng","grid","mgrs_grid","coordinate","coordinates","position"])
    private static let folder = Set(["folder","overlay","group","layer","category"])
    private static let elevation = Set(["elevation","ele","alt","altitude","elevation_m","altitude_m","height"])
    private static let time = Set(["time","timestamp","date","datetime","created"])
    private static let color = Set(["color","colour"])
    private static let symbol = Set(["symbolcode","symbol_code","milgps_symbolcode"])

    public static func parse(_ input: String) throws -> InterchangeContents {
        guard input.utf8.count <= byteLimit else { throw BackupError.notABackup("CSV exceeds 16 MB") }
        let text = input.hasPrefix("\u{FEFF}") ? String(input.dropFirst()) : input
        let rows = try readRows(text)
        guard let first = rows.first else { return .init() }
        let header = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ",with: "_") }
        let hasHeader = header.contains { name.contains($0) || lat.contains($0) || lon.contains($0) || grid.contains($0) }
        func col(_ names: Set<String>) -> Int { header.firstIndex { names.contains($0) } ?? -1 }
        let body = hasHeader ? Array(rows.dropFirst()) : rows
        let iName = hasHeader ? col(name) : 0
        var iLat = hasHeader ? col(lat) : -1, iLon = hasHeader ? col(lon) : -1, iGrid = hasHeader ? col(grid) : -1
        if !hasHeader {
            if first.count >= 2, MGRS.parse(first[1]) != nil { iGrid = 1 }
            else { iLat = 1; iLon = 2 }
        }
        let iFolder = hasHeader ? col(folder) : -1, iEle = hasHeader ? col(elevation) : -1
        let iTime = hasHeader ? col(time) : -1, iColor = hasHeader ? col(color) : -1, iSymbol = hasHeader ? col(symbol) : -1
        var result = InterchangeContents()
        for (index,row) in body.enumerated() {
            func cell(_ i: Int) -> String { row.indices.contains(i) ? row[i].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
            var latitude = coordinate(cell(iLat),limit: 90), longitude = coordinate(cell(iLon),limit: 180)
            if latitude == nil || longitude == nil, let point = MGRS.parse(cell(iGrid)) { latitude = point.lat; longitude = point.lon }
            guard let latitude, let longitude else { result.skipped += 1; continue }
            let title = cell(iName), group = cell(iFolder), colour = cell(iColor).lowercased()
            let code = Int32(cell(iSymbol)).map(Int.init).flatMap { MilGpsSymbols.decode($0) == nil ? nil : $0 }
            let height = Double(cell(iEle)).flatMap { $0.isFinite && (-500...9000).contains($0) ? $0 : nil }
            result.waypoints.append(.init(name: String((title.isEmpty ? "Point \(index+1)" : title).prefix(120)),lat: latitude,lon: longitude,
                                          folder: String((group.isEmpty ? "Imported" : group).prefix(60)),
                                          metadata: .init(color: MilGpsSymbols.colors.contains(colour) ? colour : nil,milgpsSymbolCode: code,
                                                          elevationMeters: height,timestampMillis: parseTime(cell(iTime)))))
        }
        return result
    }
    public static func build(_ waypoints: [Waypoint]) -> String {
        var output = "name,mgrs,latitude,longitude,elevation_m,folder,color,symbolcode,time\n"
        for point in waypoints {
            let m = point.metadata
            let fields = [point.name,MGRS.parts(lat: point.lat,lon: point.lon,digits: 10)?.full ?? "",
                          fixed(point.lat,7),fixed(point.lon,7),m.elevationMeters.flatMap { $0.isFinite ? fixed($0,1) : nil } ?? "",
                          point.folder,m.color ?? "",m.milgpsSymbolCode.map(String.init) ?? "",m.timestampMillis.map(timestamp) ?? ""]
            output += fields.map(quote).joined(separator: ",")+"\n"
        }
        return output
    }
    private static func readRows(_ text: String) throws -> [[String]] {
        let bytes = Array(text.utf8)
        let first = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var separator: UInt8 = 44, maximum = 0
        for candidate: UInt8 in [44,59,9] {
            let count = first.utf8.filter { $0 == candidate }.count
            if count > maximum { maximum = count; separator = candidate }
        }
        var result: [[String]] = [], row: [String] = [], field: [UInt8] = [], quoted = false, index = 0
        func finishField() { row.append(String(decoding: field,as: UTF8.self)); field.removeAll(keepingCapacity: true) }
        func finishRow() throws {
            finishField()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                guard result.count < 10_001 else { throw BackupError.notABackup("Too many CSV rows") }
                result.append(row)
            }
            row = []
        }
        while index < bytes.count {
            let byte = bytes[index]
            if quoted {
                if byte == 34 {
                    if index+1 < bytes.count, bytes[index+1] == 34 { field.append(34); index += 1 }
                    else { quoted = false }
                } else { field.append(byte) }
            } else if byte == 34, field.isEmpty { quoted = true }
            else if byte == separator { finishField() }
            else if byte == 10 { try finishRow() }
            else if byte != 13 { field.append(byte) }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { try finishRow() }
        return result
    }
    private static func quote(_ input: String) -> String {
        let safe = input.first.map { "=+@".contains($0) } == true ? "'"+input : input
        if safe.contains(where: { ",\"\n\r".contains($0) }) || safe != safe.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "\""+safe.replacingOccurrences(of: "\"",with: "\"\"")+"\""
        }
        return safe
    }
    private static func fixed(_ value: Double,_ digits: Int) -> String { String(format: "%.*f",locale: Locale(identifier: "en_US_POSIX"),digits,value) }
    static func coordinate(_ value: String,limit: Double) -> Double? { Double(value).flatMap { $0.isFinite && abs($0) <= limit ? $0 : nil } }
    static func parseTime(_ value: String) -> Int64? {
        if let n = Int64(value) { return n > 100_000_000_000 ? n : n &* 1000 }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: value) ?? { parser.formatOptions.insert(.withFractionalSeconds); return parser.date(from: value) }() {
            let millis = date.timeIntervalSince1970*1000
            if millis.isFinite, millis >= Double(Int64.min), millis < Double(Int64.max) { return Int64(millis.rounded()) }
        }
        return nil
    }
    static func timestamp(_ millis: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        if millis%1000 != 0 { formatter.formatOptions.insert(.withFractionalSeconds) }
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis)/1000))
    }
}
