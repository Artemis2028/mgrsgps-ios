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

    static func read(_ data: Data) throws -> [Entry] {
        var entries: [Entry] = []
        let bytes = [UInt8](data)
        var i = 0
        let maxEntry = 64 * 1024 * 1024
        while i + 30 <= bytes.count {
            let sig = u32(bytes, i)
            if sig == 0x02014b50 || sig == 0x06054b50 { break }
            guard sig == 0x04034b50 else {
                throw BackupError.notABackup("not an MGRS GPS backup")
            }
            let method = Int(u16(bytes, i + 8))
            let compSize = Int(u32(bytes, i + 18))
            let uncompSize = Int(u32(bytes, i + 22))
            let nameLen = Int(u16(bytes, i + 26))
            let extraLen = Int(u16(bytes, i + 28))
            let nameStart = i + 30
            guard nameStart + nameLen + extraLen + compSize <= bytes.count else {
                throw BackupError.notABackup("zip entry truncated")
            }
            let name = String(bytes: bytes[nameStart..<(nameStart + nameLen)], encoding: .utf8) ?? ""
            let dataStart = nameStart + nameLen + extraLen
            let payload = Data(bytes[dataStart..<(dataStart + compSize)])
            i = dataStart + compSize
            if uncompSize > maxEntry || name.hasSuffix("/") { continue }
            switch method {
            case 0:
                entries.append(Entry(name: name, data: payload))
            case 8:
                if let inflated = inflateRaw(payload, expected: uncompSize),
                   inflated.count <= maxEntry {
                    entries.append(Entry(name: name, data: inflated))
                }
            default:
                continue
            }
        }
        return entries
    }

    /// Raw DEFLATE (ZIP method 8) via zlib `inflateInit2(..., -MAX_WBITS)`.
    private static func inflateRaw(_ data: Data, expected: Int) -> Data? {
        guard !data.isEmpty else { return expected == 0 ? Data() : nil }
        var stream = z_stream()
        let initRC = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int32 in
            guard let base = src.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            return inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initRC == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let chunk = max(expected > 0 ? expected : 64 * 1024, 64 * 1024)
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: chunk)
        var rc: Int32
        repeat {
            rc = buffer.withUnsafeMutableBytes { dst in
                stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(chunk)
                return inflate(&stream, Z_NO_FLUSH)
            }
            let produced = chunk - Int(stream.avail_out)
            if produced > 0 {
                out.append(buffer, count: produced)
            }
            if out.count > 64 * 1024 * 1024 { return nil }
        } while rc == Z_OK
        return rc == Z_STREAM_END ? out : nil
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
