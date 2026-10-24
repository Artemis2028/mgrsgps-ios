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

    /// Read the central directory, where ZipOutputStream puts authoritative
    /// sizes/CRCs when the local headers use streaming data descriptors.
    static func read(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        func invalid(_ reason: String) -> BackupError { .notABackup(reason) }
        guard bytes.count >= 22 else { throw invalid("Truncated ZIP") }
        let lower = max(0, bytes.count - 65_557)
        guard let end = stride(from: bytes.count - 22, through: lower, by: -1).first(where: {
            u32(bytes, $0) == 0x06054b50 && $0 + 22 + Int(u16(bytes, $0 + 20)) == bytes.count
        }) else { throw invalid("Missing ZIP directory") }
        let count = Int(u16(bytes, end + 10))
        let directorySize = Int(u32(bytes, end + 12))
        var cursor = Int(u32(bytes, end + 16))
        guard u16(bytes, end + 4) == 0, u16(bytes, end + 6) == 0,
              u16(bytes, end + 8) == UInt16(count), count <= 512,
              cursor + directorySize == end else { throw invalid("Unsupported ZIP directory") }
        let directoryEnd = end
        var total = 0
        var names = Set<String>()
        var entries: [Entry] = []
        for _ in 0..<count {
            guard cursor + 46 <= directoryEnd, u32(bytes, cursor) == 0x02014b50 else { throw invalid("Truncated ZIP directory") }
            let flags = u16(bytes, cursor + 8), method = u16(bytes, cursor + 10)
            let checksum = u32(bytes, cursor + 16)
            let compressed = Int(u32(bytes, cursor + 20)), size = Int(u32(bytes, cursor + 24))
            let nameLength = Int(u16(bytes, cursor + 28)), extra = Int(u16(bytes, cursor + 30)), comment = Int(u16(bytes, cursor + 32))
            let local = Int(u32(bytes, cursor + 42))
            let next = cursor + 46 + nameLength + extra + comment
            guard next <= directoryEnd, flags & 1 == 0, method == 0 || method == 8,
                  size <= entryLimit, compressed <= totalLimit,
                  let name = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8),
                  !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
                  !name.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }),
                  names.insert(name).inserted else { throw invalid("Invalid, duplicate, or oversized ZIP entry") }
            total += size
            guard total <= totalLimit, name != Backup.manifestName || size <= manifestLimit,
                  local + 30 <= end, u32(bytes, local) == 0x04034b50,
                  u16(bytes, local + 8) == method, u16(bytes, local + 6) == flags else { throw invalid("Invalid ZIP entry header or size") }
            let localName = Int(u16(bytes, local + 26)), localExtra = Int(u16(bytes, local + 28))
            let start = local + 30 + localName + localExtra
            guard start + compressed <= end,
                  String(bytes: bytes[(local + 30)..<(local + 30 + localName)], encoding: .utf8) == name else { throw invalid("Truncated ZIP entry") }
            let payload = Data(bytes[start..<(start + compressed)])
            let decoded: Data
            if method == 0 { decoded = payload }
            else { decoded = try inflateRaw(payload, expected: size) }
            guard decoded.count == size, crc32(decoded) == checksum else { throw invalid("ZIP checksum or size mismatch") }
            if !name.hasSuffix("/") { entries.append(Entry(name: name, data: decoded)) }
            cursor = next
        }
        guard cursor == directoryEnd else { throw invalid("Invalid ZIP directory length") }
        return entries
    }

    private static func inflateRaw(_ data: Data, expected: Int) throws -> Data {
        try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Data in
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw BackupError.notABackup("Cannot read compressed ZIP entry")
            }
            defer { inflateEnd(&stream) }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
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
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1
            }
        }
        return crc ^ 0xffff_ffff
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

private func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
    UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
}
private func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
    UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
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
