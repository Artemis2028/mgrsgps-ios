import CSQLite
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

public struct TileArchiveInfo: Equatable, Sendable {
    public let name: String
    public let attribution: String
    public let minZoom: Int, maxZoom: Int, tileSize: Int
    public let bounds: MapBounds
    public let tileCount: Int
}

/// A serialised SQLite connection. Standard MBTiles rows are TMS, not XYZ.
/// Imported archives are opened read-only; tiles may be supplied by a view.
public final class MapTileArchive: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let writable: Bool
    private var xyz = false
    public init(url: URL, create: Bool = false) throws {
        writable = create
        let flags = (create ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; db = nil
            throw BackupError.notABackup("Could not open MBTiles database")
        }
        sqlite3_busy_timeout(db, 2000)
        do {
            try execute("PRAGMA trusted_schema=OFF")
            if create {
                try execute("CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB, PRIMARY KEY(zoom_level,tile_column,tile_row));")
            }
            xyz = (try? metadata("scheme")) == "xyz"
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw BackupError.notABackup("Invalid MBTiles database") }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK, let result else { throw BackupError.notABackup("MBTiles is missing required tables or columns") }
        return result
    }
    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
    public func metadata(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        let q = try statement("SELECT value FROM metadata WHERE name=? LIMIT 1"); defer { sqlite3_finalize(q) }
        bind(key, at: 1, to: q)
        guard sqlite3_step(q) == SQLITE_ROW, let text = sqlite3_column_text(q, 0) else { return nil }
        return String(cString: text)
    }
    public func setMetadata(_ values: [String: String]) throws {
        lock.lock(); defer { lock.unlock() }
        guard writable else { throw BackupError.notABackup("Map archive is read-only") }
        try execute("BEGIN IMMEDIATE")
        do {
            for (key, value) in values {
                let q = try statement("INSERT OR REPLACE INTO metadata(name,value) VALUES(?,?)"); defer { sqlite3_finalize(q) }
                bind(key, at: 1, to: q); bind(value, at: 2, to: q)
                guard sqlite3_step(q) == SQLITE_DONE else { throw BackupError.notABackup("Could not save map metadata") }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func tile(_ tile: MapTile) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard tile.valid else { return nil }
        let q = try statement("SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=? LIMIT 1"); defer { sqlite3_finalize(q) }
        sqlite3_bind_int(q, 1, Int32(tile.z)); sqlite3_bind_int(q, 2, Int32(tile.x)); sqlite3_bind_int(q, 3, Int32(xyz ? tile.y : tile.tmsRow))
        guard sqlite3_step(q) == SQLITE_ROW else { return nil }
        let size = Int(sqlite3_column_bytes(q, 0))
        guard size > 0, size <= 4 * 1024 * 1024, let blob = sqlite3_column_blob(q, 0) else { throw BackupError.notABackup("Invalid raster tile size") }
        return Data(bytes: blob, count: size)
    }
    public func put(_ data: Data, tile: MapTile) throws {
        lock.lock(); defer { lock.unlock() }
        guard writable, tile.valid, Self.rasterFormat(data) != nil, data.count <= 4 * 1024 * 1024 else { throw BackupError.notABackup("Invalid raster tile") }
        let q = try statement("INSERT OR REPLACE INTO tiles(zoom_level,tile_column,tile_row,tile_data) VALUES(?,?,?,?)"); defer { sqlite3_finalize(q) }
        sqlite3_bind_int(q, 1, Int32(tile.z)); sqlite3_bind_int(q, 2, Int32(tile.x)); sqlite3_bind_int(q, 3, Int32(xyz ? tile.y : tile.tmsRow))
        _ = data.withUnsafeBytes { sqlite3_bind_blob(q, 4, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(q) == SQLITE_DONE else { throw BackupError.notABackup("Could not save offline tile. Check available storage.") }
    }
    public func inspect() throws -> TileArchiveInfo {
        lock.lock(); defer { lock.unlock() }
        let format = (try? metadata("format"))?.lowercased() ?? ""
        guard !["pbf", "mvt", "mlt"].contains(format) else { throw BackupError.notABackup("Vector MBTiles aren't supported. Use raster PNG/JPEG/WebP tiles.") }
        let q = try statement("SELECT MIN(zoom_level),MAX(zoom_level),COUNT(*) FROM tiles"); defer { sqlite3_finalize(q) }
        guard sqlite3_step(q) == SQLITE_ROW else { throw BackupError.notABackup("Not a usable MBTiles archive") }
        let minZ = Int(sqlite3_column_int(q, 0)), maxZ = Int(sqlite3_column_int(q, 1)), count = Int(sqlite3_column_int64(q, 2))
        guard count > 0, (0...22).contains(minZ), (minZ...22).contains(maxZ) else { throw BackupError.notABackup("MBTiles contains no supported tiles") }
        let sample = try statement("SELECT tile_data FROM tiles LIMIT 1"); defer { sqlite3_finalize(sample) }
        guard sqlite3_step(sample) == SQLITE_ROW, let blob = sqlite3_column_blob(sample, 0) else { throw BackupError.notABackup("MBTiles contains no raster images") }
        let size = Int(sqlite3_column_bytes(sample, 0))
        guard size > 0, size <= 4 * 1024 * 1024, Self.rasterFormat(Data(bytes: blob, count: size)) != nil else { throw BackupError.notABackup("MBTiles contains unsupported or invalid raster images") }
        #if canImport(ImageIO)
        let bytes = Data(bytes: blob, count: size)
        guard let imageSource = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...1024).contains(width), (1...1024).contains(height),
              CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil else { throw BackupError.notABackup("MBTiles contains an invalid or oversized raster image") }
        #endif
        let raw = (try? metadata("bounds"))?.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? []
        let bounds = raw.count == 4 ? MapBounds(south: raw[1], north: raw[3], west: raw[0], east: raw[2]) : MapBounds(south: -85.05112878, north: 85.05112878, west: -180, east: 180)
        guard bounds.valid else { throw BackupError.notABackup("Invalid MBTiles bounds") }
        let tileSize = Int((try? metadata("tile_size")) ?? "256") ?? 256
        return TileArchiveInfo(name: (try? metadata("name")) ?? "Offline map", attribution: (try? metadata("attribution")) ?? "Imported MBTiles", minZoom: minZ, maxZoom: maxZ, tileSize: [256,512].contains(tileSize) ? tileSize : 256, bounds: bounds, tileCount: count)
    }
    public static func rasterFormat(_ data: Data) -> String? {
        let p = [UInt8](data.prefix(12))
        if p.starts(with: [137,80,78,71,13,10,26,10]) { return "png" }
        if p.starts(with: [255,216,255]) { return "jpeg" }
        if p.count >= 12, String(bytes: p[0..<4], encoding: .ascii) == "RIFF", String(bytes: p[8..<12], encoding: .ascii) == "WEBP" { return "webp" }
        return nil
    }
}

public struct SavedMap: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public let layerKey: String?
    public let bounds: MapBounds
    public let minZoom: Int, maxZoom: Int, tileSize: Int
    public let attribution: String
    public let expectedTiles: Int
    public var complete: Bool
    public var imported: Bool { layerKey == nil }
}

/// One file per map. Downloads keep partial tiles on pause/failure; imported
/// files are staged and validated before they become selectable.
public final class MapTileLibrary: @unchecked Sendable {
    public static let cacheLimit: Int64 = 600 * 1024 * 1024
    private let directory: URL
    private let lock = NSRecursiveLock()
    private var records: [SavedMap] = []
    private var archives: [String: MapTileArchive] = [:]
    public init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("OfflineMaps", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let file = self.directory.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: file.path) { records = try JSONDecoder().decode([SavedMap].self, from: Data(contentsOf: file)) }
        guard records.allSatisfy({ UUID(uuidString: $0.id)?.uuidString.lowercased() == $0.id && $0.bounds.valid }), Set(records.map(\.id)).count == records.count else { throw BackupError.notABackup("Offline map library is damaged; files were kept") }
    }
    public var maps: [SavedMap] { lock.lock(); defer { lock.unlock() }; return records }
    public func fileURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".mbtiles") }
    private func archive(_ id: String) throws -> MapTileArchive {
        guard records.contains(where: { $0.id == id }) else { throw BackupError.notABackup("Offline map not found") }
        if let archive = archives[id] { return archive }
        let opened = try MapTileArchive(url: fileURL(id), create: records.first(where: { $0.id == id })?.layerKey != nil)
        archives[id] = opened; return opened
    }
    public func data(for tile: MapTile, mapID: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return try archive(mapID).tile(tile)
    }
    public func pinnedTile(_ tile: MapTile, layerKey: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        for map in records.reversed() where map.layerKey == layerKey {
            if let data = try? archive(map.id).tile(tile) { return data }
        }
        return nil
    }
    public func downloadedCount(_ id: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return (try? archive(id).inspect().tileCount) ?? 0
    }
    public func bytes(_ id: String) -> Int64 { (try? FileManager.default.attributesOfItem(atPath: fileURL(id).path)[.size] as? NSNumber)?.int64Value ?? 0 }
    public var downloadedBytes: Int64 { lock.lock(); defer { lock.unlock() }; return records.filter { !$0.imported && $0.layerKey != "dem" }.reduce(0) { $0 + bytes($1.id) } }
    public var elevationBytes: Int64 { lock.lock(); defer { lock.unlock() }; return records.filter { $0.layerKey == "dem" }.reduce(0) { $0 + bytes($1.id) } }
    public func importFile(_ file: URL) throws -> SavedMap {
        lock.lock(); defer { lock.unlock() }
        let id = UUID().uuidString.lowercased(), stage = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: file, to: stage)
        let info = try MapTileArchive(url: stage).inspect()
        let original = file.deletingPathExtension().lastPathComponent
        let base = original.isEmpty ? info.name : original
        var name = base, suffix = 2
        while records.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { name = base + "-\(suffix)"; suffix += 1 }
        let map = SavedMap(id: id, name: name, layerKey: nil, bounds: info.bounds, minZoom: info.minZoom, maxZoom: info.maxZoom, tileSize: info.tileSize, attribution: info.attribution, expectedTiles: info.tileCount, complete: true)
        let target = fileURL(id)
        try FileManager.default.moveItem(at: stage, to: target)
        do { try publish(records + [map]) } catch { try? FileManager.default.removeItem(at: target); throw error }
        return map
    }
    public func begin(_ plan: TileDownloadPlan, name: String, layer: RasterLayer) throws -> SavedMap {
        lock.lock(); defer { lock.unlock() }
        guard layer.bulkDownload, plan.layerKey == layer.key else { throw BackupError.notABackup("Area download not allowed for this layer") }
        let id = UUID().uuidString.lowercased(), file = fileURL(id)
        let map = SavedMap(id: id, name: name.isEmpty ? layer.label : name, layerKey: layer.key, bounds: plan.bounds, minZoom: plan.minZoom, maxZoom: plan.maxZoom, tileSize: layer.tileSize, attribution: layer.attribution, expectedTiles: plan.tiles.count, complete: false)
        do {
            let db = try MapTileArchive(url: file, create: true)
            try db.setMetadata(["name": map.name, "format": "png", "scheme": "tms", "attribution": layer.attribution, "tile_size": "\(layer.tileSize)", "bounds": "\(plan.bounds.west),\(plan.bounds.south),\(plan.bounds.east),\(plan.bounds.north)"])
            try publish(records + [map]); archives[id] = db
        } catch { try? FileManager.default.removeItem(at: file); throw error }
        return map
    }
    public func store(_ data: Data, tile: MapTile, in id: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let map = records.first(where: { $0.id == id }), !map.imported else { throw BackupError.notABackup("Cannot modify an imported map") }
        let total = map.layerKey == "dem" ? records.filter { $0.layerKey == "dem" }.reduce(Int64(0)) { $0 + bytes($1.id) } : downloadedBytes
        guard total + Int64(data.count) < (map.layerKey == "dem" ? 300 * 1024 * 1024 : Self.cacheLimit) else { throw BackupError.notABackup("Offline storage limit reached. Remove a saved area and retry.") }
        try archive(id).put(data, tile: tile)
    }
    public func finish(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var next = records
        guard let index = next.firstIndex(where: { $0.id == id }), downloadedCount(id) >= next[index].expectedTiles else { throw BackupError.notABackup("Area is incomplete; saved tiles were kept") }
        next[index].complete = true; try publish(next)
    }
    public func delete(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard records.contains(where: { $0.id == id }) else { throw BackupError.notABackup("Offline map not found") }
        archives.removeValue(forKey: id)
        let file = fileURL(id), trash = directory.appendingPathComponent(id + ".trash")
        let exists = FileManager.default.fileExists(atPath: file.path)
        if exists { try FileManager.default.moveItem(at: file, to: trash) }
        do { try publish(records.filter { $0.id != id }) }
        catch { if exists { try? FileManager.default.moveItem(at: trash, to: file) }; throw error }
        if exists { try? FileManager.default.removeItem(at: trash) }
    }
    private func publish(_ next: [SavedMap]) throws {
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        records = next
    }
}
