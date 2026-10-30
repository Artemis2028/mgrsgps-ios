import Foundation
import GridFixCore

/// Like Android's DEM cache: fetched elevation stays available offline, with
/// oldest-use eviction and a separate 300 MB budget shared with saved DEM areas.
final class TerrainTileCache: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private let pinnedBytes: @Sendable () -> Int64
    init(directory: URL, pinnedBytes: @escaping @Sendable () -> Int64) {
        self.directory = directory.appendingPathComponent("ElevationTiles", isDirectory: true)
        self.pinnedBytes = pinnedBytes
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }
    private func file(_ tile: MapTile) -> URL { directory.appendingPathComponent("\(tile.z)-\(tile.x)-\(tile.y).png") }
    func read(_ tile: MapTile) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: file(tile)), data.count <= 4 * 1024 * 1024, MapTileArchive.rasterFormat(data) == "png" else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file(tile).path)
        return data
    }
    func store(_ data: Data, tile: MapTile) throws {
        lock.lock(); defer { lock.unlock() }
        try data.write(to: file(tile), options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey,.contentModificationDateKey]).compactMap { url -> (URL, Int64, Date)? in
            guard let value = try? url.resourceValues(forKeys: [.fileSizeKey,.contentModificationDateKey]) else { return nil }
            return (url,Int64(value.fileSize ?? 0),value.contentModificationDate ?? .distantPast)
        }
        var size = files.reduce(Int64(0)) { $0 + $1.1 }
        let budget = max(0, 300 * 1024 * 1024 - pinnedBytes())
        for item in files.sorted(by: { $0.2 < $1.2 }) where size > budget {
            try FileManager.default.removeItem(at: item.0); size -= item.1
        }
    }
    func remove(_ tile: MapTile) { lock.lock(); defer { lock.unlock() }; try? FileManager.default.removeItem(at: file(tile)) }
}
