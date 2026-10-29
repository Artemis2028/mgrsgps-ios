import Foundation
import CryptoKit
import zlib

/// Separate from the bounded vector scene. Publication time is not a terrain survey date.
public struct WatchTerrainManifest: Codable, Equatable, Sendable {
    public var version = 1
    public var encoding = "terrarium"
    public let source: String
    public let revision: Int64
    public let publishedAtMillis: Int64
    public let z: Int
    public let x: Int
    public let y: Int
    public let bytes: Int
    public let sha256: String
    public let attribution: String

    public init(source: String, revision: Int64, publishedAtMillis: Int64, x: Int, y: Int, png: Data, attribution: String) {
        self.source = source; self.revision = revision; self.publishedAtMillis = publishedAtMillis
        z = 13; self.x = x; self.y = y; bytes = png.count
        sha256 = Self.hash(png); self.attribution = attribution
    }
    public var valid: Bool {
        version == 1 && encoding == "terrarium" && !source.isEmpty && source.utf8.count <= 64 &&
        source.utf8.allSatisfy { $0 >= 33 && $0 <= 126 } && (1...9_007_199_254_740_991).contains(revision) &&
        (1...9_007_199_254_740_991).contains(publishedAtMillis) &&
        z == 13 && (0..<8192).contains(x) && (0..<8192).contains(y) &&
        (1...WatchTerrainRaster.maxBytes).contains(bytes) && sha256.count == 64 &&
        sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } &&
        !attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attribution.utf8.count <= 512
    }
    public func encoded() throws -> Data {
        guard valid else { throw WatchTerrainError.invalid }
        let data = try JSONEncoder().encode(self)
        guard data.count <= 4096 else { throw WatchTerrainError.invalid }; return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4096 else { throw WatchTerrainError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.valid else { throw WatchTerrainError.invalid }; return value
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

public enum WatchTerrainError: Error { case invalid, stale, conflict, sourceMismatch }

/// Raw PNG samples, without display gamma correction or premultiplied-alpha conversion.
/// Deliberately supports only 256-square RGB/RGBA, eight-bit noninterlaced Terrarium PNG.
/// Filter reconstruction follows https://www.w3.org/TR/png-3/#9Filters.
public struct WatchTerrainRaster: Sendable {
    public static let maxBytes = 4 * 1024 * 1024
    private let heights: [Double]
    public init(png: Data) throws {
        guard png.count <= Self.maxBytes else { throw WatchTerrainError.invalid }
        let a = [UInt8](png)
        guard a.starts(with: [137,80,78,71,13,10,26,10]) else { throw WatchTerrainError.invalid }
        func uint(_ at: Int) -> Int { (0..<4).reduce(0) { ($0 << 8) | Int(a[at+$1]) } }
        var cursor = 8, chunks = 0, bpp = 0, ended = false, idatEnded = false, seenIDAT = false, seenPalette = false
        var compressed = Data()
        while cursor < a.count {
            chunks += 1
            guard chunks <= 256, cursor <= a.count-12 else { throw WatchTerrainError.invalid }
            let n = uint(cursor)
            guard n <= a.count-cursor-12 else { throw WatchTerrainError.invalid }
            let typeBytes = Array(a[cursor+4..<cursor+8])
            guard typeBytes.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }), typeBytes[2] & 32 == 0 else { throw WatchTerrainError.invalid }
            let type = String(bytes: typeBytes, encoding: .ascii)!
            let crcData = Data(a[cursor+4..<cursor+8+n])
            let crc = crcData.withUnsafeBytes { UInt32(zlib.crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(crcData.count))) }
            guard crc == UInt32(uint(cursor+8+n)), chunks != 1 || type == "IHDR" else { throw WatchTerrainError.invalid }
            let p = cursor+8
            switch type {
            case "IHDR":
                guard chunks == 1, n == 13, uint(p) == 256, uint(p+4) == 256,
                      a[p+8] == 8, [2,6].contains(a[p+9]), a[p+10] == 0, a[p+11] == 0, a[p+12] == 0 else { throw WatchTerrainError.invalid }
                bpp = a[p+9] == 2 ? 3 : 4
            case "IDAT":
                guard bpp > 0, !idatEnded else { throw WatchTerrainError.invalid }
                seenIDAT = true; compressed.append(contentsOf: a[p..<p+n])
            case "IEND":
                guard n == 0, seenIDAT, cursor+12 == a.count else { throw WatchTerrainError.invalid }; ended = true
            case "PLTE":
                guard !seenIDAT, !seenPalette, n > 0, n <= 768, n % 3 == 0 else { throw WatchTerrainError.invalid }
                seenPalette = true
            default:
                // Transparency keys and animated frames are outside this terrain contract.
                guard typeBytes[0] & 32 != 0, !["tRNS","acTL","fcTL","fdAT"].contains(type) else { throw WatchTerrainError.invalid }
            }
            if seenIDAT && type != "IDAT" { idatEnded = true }
            cursor += n+12
        }
        guard ended, !compressed.isEmpty else { throw WatchTerrainError.invalid }
        let stride = 256*bpp, expected = (stride+1)*256
        var raw = [UInt8](repeating: 0, count: expected+1), stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw WatchTerrainError.invalid }
        defer { inflateEnd(&stream) }
        let status = compressed.withUnsafeBytes { input in raw.withUnsafeMutableBytes { output -> Int32 in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(compressed.count)
            stream.next_out = output.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(output.count)
            return inflate(&stream, Z_FINISH)
        } }
        guard status == Z_STREAM_END, stream.total_out == expected, stream.avail_in == 0 else { throw WatchTerrainError.invalid }
        var pixels = [UInt8](repeating: 0, count: stride*256)
        for row in 0..<256 {
            let f = raw[row*(stride+1)]; guard f <= 4 else { throw WatchTerrainError.invalid }
            for col in 0..<stride {
                let at = row*stride+col
                let left = col >= bpp ? Int(pixels[at-bpp]) : 0
                let above = row > 0 ? Int(pixels[at-stride]) : 0
                let corner = row > 0 && col >= bpp ? Int(pixels[at-stride-bpp]) : 0
                let predictor: Int
                switch f {
                case 1: predictor = left
                case 2: predictor = above
                case 3: predictor = (left+above)/2
                case 4:
                    let p = left+above-corner, da = abs(p-left), db = abs(p-above), dc = abs(p-corner)
                    predictor = da <= db && da <= dc ? left : db <= dc ? above : corner
                default: predictor = 0
                }
                pixels[at] = raw[row*(stride+1)+1+col] &+ UInt8(predictor)
            }
        }
        heights = (0..<65536).map { i in
            let p = i*bpp
            guard bpp == 3 || pixels[p+3] == 255 else { return .nan }
            return TerrainContours.elevation(red: pixels[p], green: pixels[p+1], blue: pixels[p+2]) ?? .nan
        }
    }
    public func elevation(x: Int, y: Int) -> Double? {
        guard (0..<256).contains(x), (0..<256).contains(y) else { return nil }
        let value = heights[y*256+x]; return value.isFinite ? value : nil
    }
    public static func pixel(lat: Double, lon: Double) -> (x: Int, y: Int, px: Int, py: Int)? {
        guard lat.isFinite, lon.isFinite, abs(lat) <= 85, (-180...180).contains(lon) else { return nil }
        let longitude = lon == 180 ? -180 : lon
        let tx = (longitude+180)/360*8192, radians = lat * .pi/180
        let ty = (1-log(tan(radians)+1/cos(radians)) / .pi)/2*8192
        let x = Int(floor(tx)), y = Int(floor(ty))
        guard (0..<8192).contains(x), (0..<8192).contains(y) else { return nil }
        return (x,y,min(255,Int((tx-Double(x))*256)),min(255,Int((ty-Double(y))*256)))
    }
}

/// One atomic record per source/tile: a failed replacement preserves the previous tile.
/// Own directory only; at most 16 tiles / 32 MiB. No network or phone-coordinate fallback.
public final class WatchTerrainCache: @unchecked Sendable {
    private static let lock = NSRecursiveLock()
    private let directory: URL
    private var decoded: [(String, WatchTerrainRaster)] = []
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func file(source: String, x: Int, y: Int) -> URL {
        directory.appendingPathComponent(WatchTerrainManifest.hash(Data("\(source)|13|\(x)|\(y)".utf8))+".terrain")
    }
    private func record(_ url: URL) throws -> (WatchTerrainManifest, Data) {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (5...(WatchTerrainRaster.maxBytes+4100)).contains(size) else { throw WatchTerrainError.invalid }
        let data = try Data(contentsOf: url)
        guard data.count == size else { throw WatchTerrainError.invalid }
        let n = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard n > 0, n <= 4096, n+4 < data.count else { throw WatchTerrainError.invalid }
        let meta = try WatchTerrainManifest.decode(data.subdata(in: 4..<n+4)), png = data.subdata(in: n+4..<data.count)
        return (meta,png)
    }
    public func install(manifest: WatchTerrainManifest, png: Data, expectedSource: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard manifest.source == expectedSource else { throw WatchTerrainError.sourceMismatch }
        let json = try manifest.encoded()
        guard png.count == manifest.bytes, WatchTerrainManifest.hash(png) == manifest.sha256 else { throw WatchTerrainError.invalid }
        _ = try WatchTerrainRaster(png: png)
        let url = file(source: manifest.source, x: manifest.x, y: manifest.y)
        if let (old, oldPNG) = try? record(url), old.source == manifest.source, old.x == manifest.x, old.y == manifest.y {
            guard manifest.revision >= old.revision else { throw WatchTerrainError.stale }
            if manifest.revision == old.revision {
                guard manifest == old else { throw WatchTerrainError.conflict }
                if oldPNG == png { return }
            }
        }
        let n = json.count
        var data = Data([UInt8((n >> 24) & 255),UInt8((n >> 16) & 255),UInt8((n >> 8) & 255),UInt8(n & 255)])
        data.append(json); data.append(png); try data.write(to: url, options: .atomic)
        // Only this cache's content-addressed record names are eligible for eviction.
        var records = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey,.contentModificationDateKey]).filter {
            $0.pathExtension == "terrain" && $0.deletingPathExtension().lastPathComponent.count == 64 && $0.deletingPathExtension().lastPathComponent.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }.map { u in (u, try u.resourceValues(forKeys: [.fileSizeKey,.contentModificationDateKey])) }.sorted {
            ($0.1.contentModificationDate ?? .distantPast) < ($1.1.contentModificationDate ?? .distantPast)
        }
        var total = records.reduce(0) { $0 + ($1.1.fileSize ?? 0) }
        while records.count > 16 || total > 32*1024*1024 {
            let oldest = records.removeFirst(); try FileManager.default.removeItem(at: oldest.0); total -= oldest.1.fileSize ?? 0
        }
    }
    public func sample(source: String, lat: Double, lon: Double) -> (meters: Double, manifest: WatchTerrainManifest)? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard let p = WatchTerrainRaster.pixel(lat: lat, lon: lon),
              let (meta,png) = try? record(file(source: source,x: p.x,y: p.y)), meta.source == source, meta.x == p.x, meta.y == p.y,
              meta.bytes == png.count, meta.sha256 == WatchTerrainManifest.hash(png) else { return nil }
        let raster: WatchTerrainRaster
        if let index = decoded.firstIndex(where: { $0.0 == meta.sha256 }) {
            let hit = decoded.remove(at: index); decoded.append(hit); raster = hit.1
        } else {
            guard let loaded = try? WatchTerrainRaster(png: png) else { return nil }
            raster = loaded; decoded.append((meta.sha256,loaded))
            if decoded.count > 4 { decoded.removeFirst() }
        }
        guard let value = raster.elevation(x: p.px,y: p.py) else { return nil }
        return (value,meta)
    }
}
