import Foundation
import zlib

/// Minimal ZIP reader/writer. Writers use STORE; readers also accept DEFLATE
/// so Android `ZipOutputStream` backups round-trip.
enum ZipArchive {

    struct Entry {
        let name: String
        let data: Data
    }

    static func write(entries: [Entry]) -> Data {
        var local = Data()
        var central = Data()
        var offset: UInt32 = 0
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            var localHeader = Data()
            localHeader.appendLE(UInt32(0x04034b50))
            localHeader.appendLE(UInt16(20))
            localHeader.appendLE(UInt16(0))
            localHeader.appendLE(UInt16(0)) // STORE
            localHeader.appendLE(UInt16(0))
            localHeader.appendLE(UInt16(0))
            localHeader.appendLE(crc)
            localHeader.appendLE(size)
            localHeader.appendLE(size)
            localHeader.appendLE(UInt16(nameData.count))
            localHeader.appendLE(UInt16(0))
            localHeader.append(nameData)
            localHeader.append(entry.data)

            var cen = Data()
            cen.appendLE(UInt32(0x02014b50))
            cen.appendLE(UInt16(20))
            cen.appendLE(UInt16(20))
            cen.appendLE(UInt16(0))
            cen.appendLE(UInt16(0))
            cen.appendLE(UInt16(0))
            cen.appendLE(UInt16(0))
            cen.appendLE(crc)
            cen.appendLE(size)
            cen.appendLE(size)
            cen.appendLE(UInt16(nameData.count))
            cen.appendLE(UInt16(0))
            cen.appendLE(UInt16(0))
            cen.appendLE(UInt16(0))
            cen.appendLE(UInt16(0))
            cen.appendLE(UInt32(0))
            cen.appendLE(offset)
            cen.append(nameData)

            offset += UInt32(localHeader.count)
            local.append(localHeader)
            central.append(cen)
        }
        var end = Data()
        end.appendLE(UInt32(0x06054b50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt32(central.count))
        end.appendLE(offset)
        end.appendLE(UInt16(0))
        return local + central + end
    }

    static let totalLimit = 32 * 1024 * 1024
    static let entryLimit = 16 * 1024 * 1024
    static let manifestLimit = 4 * 1024 * 1024

    struct Limits {
        var entryBytes: Int
        var totalBytes: Int
        var entries: Int
        var backupRules = true
        static let backup = Self(entryBytes: entryLimit,totalBytes: totalLimit,entries: 512)
        static let interchange = Self(entryBytes: 32*1024*1024,totalBytes: 128*1024*1024,entries: 2048,backupRules: false)
    }

    /// Backup callers retain their original limits and path/duplicate rules.
    static func read(_ data: Data) throws -> [Entry] {
        var entries: [Entry] = []
        try visit(data) { name,bytes in if !name.hasSuffix("/") { entries.append(.init(name: name,data: bytes)) } }
        return entries
    }

    /// Visit one decoded member at a time without copying the entire archive.
    /// Process local-header order, as Android ZipInputStream does, even when
    /// a writer has reordered its central directory. No member is extracted.
    static func visit(_ data: Data,limits: Limits = .backup,
                      beforeEntry: (String,Int) throws -> Void = { _,_ in },
                      onEntry: (String,Data) throws -> Void) throws {
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            func invalid(_ reason: String) -> BackupError { .notABackup(reason) }
            guard bytes.count >= 22 else { throw invalid("Truncated ZIP") }
            let lower = max(0,bytes.count-65_557)
            guard let end = stride(from: bytes.count-22,through: lower,by: -1).first(where: {
                u32(bytes,$0) == 0x06054b50 && $0+22+Int(u16(bytes,$0+20)) == bytes.count
            }) else { throw invalid("Missing ZIP directory") }
            func fits(_ start: Int, _ size: Int, _ boundary: Int) -> Bool {
                start >= 0 && start <= boundary && size >= 0 && size <= boundary-start
            }
            func bounded(_ value: UInt64, _ limit: Int, _ reason: String) throws -> Int {
                guard limit >= 0, value <= UInt64(limit) else { throw invalid(reason) }
                return Int(value)
            }
            guard limits.entries >= 0, limits.entryBytes >= 0, limits.totalBytes >= 0,
                  u16(bytes,end+4) == 0, u16(bytes,end+6) == 0 else { throw invalid("Unsupported split ZIP") }
            let legacyCount = u16(bytes,end+10), legacySize = u32(bytes,end+12), legacyOffset = u32(bytes,end+16)
            let locator = end-20
            // A classic entry comment can end with locator-like bytes. A
            // complete legacy directory reaching EOCD takes precedence there.
            let completeLegacy = legacyCount != .max && legacySize != .max && legacyOffset != .max
                && UInt64(legacySize)+UInt64(legacyOffset) == UInt64(end)
            let hasZip64 = !completeLegacy && locator >= 0 && u32(bytes,locator) == 0x07064b50
            var count64 = UInt64(legacyCount), size64 = UInt64(legacySize), offset64 = UInt64(legacyOffset)
            var directoryEnd = end
            if hasZip64 {
                guard u32(bytes,locator+4) == 0, u32(bytes,locator+16) == 1 else { throw invalid("Unsupported split ZIP64") }
                let record = try bounded(u64(bytes,locator+8),locator,"Invalid ZIP64 directory offset")
                guard fits(record,56,locator), u32(bytes,record) == 0x06064b50,
                      u64(bytes,record+4) >= 44, u64(bytes,record+4) == UInt64(locator-record-12),
                      u32(bytes,record+16) == 0, u32(bytes,record+20) == 0,
                      u64(bytes,record+24) == u64(bytes,record+32) else { throw invalid("Invalid ZIP64 directory") }
                count64 = u64(bytes,record+32); size64 = u64(bytes,record+40); offset64 = u64(bytes,record+48)
                guard (legacyCount == .max || UInt64(legacyCount) == count64),
                      (u16(bytes,end+8) == .max || UInt64(u16(bytes,end+8)) == count64),
                      (legacySize == .max || UInt64(legacySize) == size64),
                      (legacyOffset == .max || UInt64(legacyOffset) == offset64) else { throw invalid("Conflicting ZIP64 directory") }
                directoryEnd = record
            } else {
                guard legacyCount != .max, legacySize != .max, legacyOffset != .max,
                      u16(bytes,end+8) == legacyCount else { throw invalid("Missing ZIP64 directory") }
            }
            let count = try bounded(count64,limits.entries,"Too many ZIP entries")
            let directorySize = try bounded(size64,directoryEnd,"Invalid ZIP directory size")
            var cursor = try bounded(offset64,directoryEnd,"Invalid ZIP directory offset")
            guard fits(cursor,directorySize,directoryEnd), cursor+directorySize == directoryEnd else { throw invalid("Invalid ZIP directory length") }
            let directoryStart = cursor

            // Extra-field values are conditional in the central directory: only
            // sentinel fields consume values, in size/compressed/offset/disk order.
            func zip64Extra(_ start: Int, _ length: Int) throws -> Range<Int>? {
                let finish = start+length
                var position = start, found: Range<Int>?
                while position < finish {
                    guard fits(position,4,finish) else { throw invalid("Truncated ZIP extra field") }
                    let tag = u16(bytes,position), size = Int(u16(bytes,position+2))
                    position += 4
                    guard fits(position,size,finish) else { throw invalid("Invalid ZIP extra field length") }
                    if tag == 1 {
                        guard found == nil else { throw invalid("Duplicate ZIP64 extra field") }
                        found = position..<(position+size)
                    }
                    position += size
                }
                return found
            }
            func expanded(_ raw: UInt32, _ extra: Range<Int>?, _ position: inout Int) throws -> UInt64 {
                guard raw == .max else { return UInt64(raw) }
                guard let extra, fits(position,8,extra.upperBound) else { throw invalid("Missing ZIP64 entry value") }
                defer { position += 8 }
                return u64(bytes,position)
            }
            struct Member { var name: String; var start: Int; var end: Int; var compressed: Int; var size: Int; var method: UInt16; var checksum: UInt32; var local: Int }
            var members: [Member] = [], names = Set<String>(), offsets = Set<Int>(), total = 0
            for _ in 0..<count {
                try Task.checkCancellation()
                guard fits(cursor,46,directoryEnd), u32(bytes,cursor) == 0x02014b50 else { throw invalid("Truncated ZIP directory") }
                let flags = u16(bytes,cursor+8), method = u16(bytes,cursor+10), checksum = u32(bytes,cursor+16)
                let rawCompressed = u32(bytes,cursor+20), rawSize = u32(bytes,cursor+24), rawLocal = u32(bytes,cursor+42)
                let nameLength = Int(u16(bytes,cursor+28)), extraLength = Int(u16(bytes,cursor+30)), comment = Int(u16(bytes,cursor+32))
                let length = 46+nameLength+extraLength+comment
                guard fits(cursor,length,directoryEnd), flags & 0x2041 == 0, method == 0 || method == 8 else { throw invalid("Unsupported ZIP entry") }
                let extra = try zip64Extra(cursor+46+nameLength,extraLength)
                var extraPosition = extra?.lowerBound ?? 0
                let size = try bounded(expanded(rawSize,extra,&extraPosition),limits.entryBytes,"Oversized ZIP entry")
                let compressed = try bounded(expanded(rawCompressed,extra,&extraPosition),limits.backupRules ? totalLimit : data.count,"Oversized compressed ZIP entry")
                guard method != 0 || compressed == size else { throw invalid("Invalid stored ZIP sizes") }
                let local = try bounded(expanded(rawLocal,extra,&extraPosition),directoryStart,"Invalid ZIP local offset")
                var disk = UInt32(u16(bytes,cursor+34))
                if disk == UInt32(UInt16.max) {
                    guard let extra, fits(extraPosition,4,extra.upperBound) else { throw invalid("Missing ZIP64 disk value") }
                    disk = u32(bytes,extraPosition)
                }
                guard disk == 0,
                      let name = String(bytes: bytes[(cursor+46)..<(cursor+46+nameLength)],encoding: .utf8),
                      !name.isEmpty, offsets.insert(local).inserted else { throw invalid("Invalid ZIP entry") }
                if limits.backupRules {
                    guard !name.hasPrefix("/"), !name.contains("\\"),
                          !name.split(separator: "/",omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }),
                          names.insert(name).inserted else { throw invalid("Invalid or duplicate ZIP path") }
                }
                guard size <= limits.totalBytes-total else { throw invalid("ZIP total size limit exceeded") }
                total += size
                guard !limits.backupRules || name != Backup.manifestName || size <= manifestLimit,
                      fits(local,30,directoryStart), u32(bytes,local) == 0x04034b50,
                      u16(bytes,local+8) == method, u16(bytes,local+6) == flags else { throw invalid("Invalid ZIP entry header or size") }
                let localName = Int(u16(bytes,local+26)), localExtra = Int(u16(bytes,local+28))
                let headerLength = 30+localName+localExtra
                guard fits(local,headerLength,directoryStart) else { throw invalid("Truncated ZIP local header") }
                let start = local+headerLength
                guard fits(start,compressed,directoryStart),
                      String(bytes: bytes[(local+30)..<(local+30+localName)],encoding: .utf8) == name else { throw invalid("Truncated ZIP entry") }
                let localExtension = try zip64Extra(local+30+localName,localExtra)
                let rawLocalSize = u32(bytes,local+22), rawLocalCompressed = u32(bytes,local+18)
                let localSize: UInt64, localCompressed: UInt64
                if let localExtension {
                    // Local ZIP64 fields always contain both sizes. Central
                    // directory fields above are conditional on each sentinel.
                    guard localExtension.count >= 16 else { throw invalid("Truncated local ZIP64 sizes") }
                    localSize = rawLocalSize == .max ? u64(bytes,localExtension.lowerBound) : UInt64(rawLocalSize)
                    localCompressed = rawLocalCompressed == .max ? u64(bytes,localExtension.lowerBound+8) : UInt64(rawLocalCompressed)
                } else {
                    guard rawLocalSize != .max, rawLocalCompressed != .max else { throw invalid("Missing local ZIP64 sizes") }
                    localSize = UInt64(rawLocalSize); localCompressed = UInt64(rawLocalCompressed)
                }
                var memberEnd = start+compressed
                if flags & 8 == 0 {
                    guard u32(bytes,local+14) == checksum, localSize == UInt64(size), localCompressed == UInt64(compressed) else { throw invalid("Conflicting ZIP local sizes or checksum") }
                } else {
                    guard (u32(bytes,local+14) == 0 || u32(bytes,local+14) == checksum),
                          (localSize == 0 || localSize == UInt64(size)),
                          (localCompressed == 0 || localCompressed == UInt64(compressed)) else { throw invalid("Conflicting streamed ZIP header") }
                    let wide = localExtension != nil || rawSize == .max || rawCompressed == .max
                    let descriptorSize = wide ? 20 : 12
                    // A checksum may itself equal the optional signature. Try
                    // both forms, validating every value before accepting either.
                    let signed = fits(memberEnd,4,directoryStart) && u32(bytes,memberEnd) == 0x08074b50
                    let candidates = signed ? [memberEnd+4,memberEnd] : [memberEnd]
                    guard let descriptor = candidates.first(where: { position in
                        guard fits(position,descriptorSize,directoryStart), u32(bytes,position) == checksum else { return false }
                        return wide
                            ? u64(bytes,position+4) == UInt64(compressed) && u64(bytes,position+12) == UInt64(size)
                            : u32(bytes,position+4) == UInt32(compressed) && u32(bytes,position+8) == UInt32(size)
                    }) else { throw invalid("Invalid ZIP data descriptor") }
                    memberEnd = descriptor+descriptorSize
                }
                members.append(.init(name: name,start: start,end: memberEnd,compressed: compressed,size: size,method: method,checksum: checksum,local: local))
                cursor += length
            }
            guard cursor == directoryEnd else { throw invalid("Invalid ZIP directory length") }
            var previousEnd = 0
            for member in members.sorted(by: { $0.local < $1.local }) {
                try Task.checkCancellation()
                guard member.local >= previousEnd else { throw invalid("Overlapping ZIP entries") }
                previousEnd = member.end
                try beforeEntry(member.name,member.size)
                try Task.checkCancellation()
                let payload = UnsafeRawBufferPointer(rebasing: bytes[member.start..<(member.start+member.compressed)])
                let decoded = try member.method == 0 ? Data(payload) : inflateRaw(payload,expected: member.size)
                guard decoded.count == member.size, crc32(decoded) == member.checksum else { throw invalid("ZIP checksum or size mismatch") }
                try Task.checkCancellation()
                try onEntry(member.name,decoded)
            }
        }
    }

    private static func inflateRaw(_ input: UnsafeRawBufferPointer, expected: Int) throws -> Data {
        var stream = z_stream()
        stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
        stream.avail_in = uInt(input.count)
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw BackupError.notABackup("Cannot read compressed ZIP entry")
        }
        defer { inflateEnd(&stream) }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            try Task.checkCancellation()
            let status = buffer.withUnsafeMutableBytes { output -> Int32 in
                stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = 16 * 1024
                return inflate(&stream, Z_NO_FLUSH)
            }
            let written = buffer.count - Int(stream.avail_out)
            guard result.count + written <= expected else { throw BackupError.notABackup("ZIP expands beyond its declared size") }
            result.append(contentsOf: buffer.prefix(written))
            if status == Z_STREAM_END {
                guard stream.avail_in == 0 else { throw BackupError.notABackup("Trailing compressed ZIP data") }
                return result
            }
            guard status == Z_OK, written > 0 || stream.avail_in > 0 else { throw BackupError.notABackup("Damaged compressed ZIP entry") }
        }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { bytes in
            UInt32(zlib.crc32(0,bytes.bindMemory(to: Bytef.self).baseAddress,uInt(data.count)))
        }
    }

}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

private func u16(_ b: UnsafeRawBufferPointer, _ i: Int) -> UInt16 {
    UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
}
private func u32(_ b: UnsafeRawBufferPointer, _ i: Int) -> UInt32 {
    UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
}

private func u64(_ b: UnsafeRawBufferPointer, _ i: Int) -> UInt64 {
    UInt64(u32(b,i)) | (UInt64(u32(b,i+4)) << 32)
}

public enum BackupError: Error, LocalizedError, Equatable {
    case notABackup(String)
    case unsupportedVersion(Int)
    case missingField(String)

    public var errorDescription: String? {
        switch self {
        case .notABackup(let s): return s
        case .unsupportedVersion(let v): return "Backup version \(v) needs a newer app"
        case .missingField(let f): return "Missing required field: \(f)"
        }
    }
}
