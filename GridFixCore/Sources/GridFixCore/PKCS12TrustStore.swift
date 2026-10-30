import CommonCrypto
import CryptoKit
import Foundation

/// Certificate-only PKCS #12 import for iOS, whose SecPKCS12Import returns no
/// items for these bags. RFC 7292 (MAC/legacy KDF) and RFC 8018 (PBES2).
/// This never imports keys, installs trust, or substitutes a client-chain CA.
public enum PKCS12TrustStore {
    public enum Failure: LocalizedError, Equatable {
        case malformed, authentication, unsupported, limits, decryption
        public var errorDescription: String? {
            switch self {
            case .malformed: return "Invalid PKCS #12 server trust store"
            case .authentication: return "Wrong trust-store password, or the file has been changed"
            case .unsupported: return "This trust-store encryption or integrity format is not supported"
            case .limits: return "The trust store exceeds supported size or cryptographic work limits"
            case .decryption: return "Unable to decrypt the server trust store"
            }
        }
    }
    private static let dataOID = "1.2.840.113549.1.7.1"
    public static func certificates(_ bytes: Data, password: String) throws -> [Data] {
        guard bytes.count <= 2 * 1024 * 1024, password.utf16.count <= 1024 else { throw Failure.limits }
        var reader = Reader(password: password)
        let pfx = try Node.root(bytes).sequence()
        guard pfx.count == 3, try pfx[0].integer() == 3 else { throw Failure.malformed }
        let safe = try contentData(pfx[1])
        try reader.verifyMAC(safe, mac: pfx[2])
        let contents = try Node.root(safe).sequence()
        guard contents.count <= 32 else { throw Failure.limits }
        for content in contents {
            try Task.checkCancellation()
            let fields = try content.sequence()
            guard fields.count == 2 else { throw Failure.malformed }
            let oid = try fields[0].oid()
            if oid == dataOID { try reader.collect(try contentData(content), depth: 0) }
            else if oid == "1.2.840.113549.1.7.6" {
                let encrypted = try fields[1].explicit().sequence()
                guard (2...3).contains(encrypted.count), try encrypted[0].integer() == 0 else { throw Failure.malformed }
                let info = try encrypted[1].sequence()
                guard info.count == 3, try info[0].oid() == dataOID, info[2].tag == 0x80 else { throw Failure.unsupported }
                try reader.collect(try reader.decrypt(info[2].value, algorithm: info[1]), depth: 0)
            } else { throw Failure.unsupported }
        }
        guard !reader.certificates.isEmpty else { throw Failure.malformed }
        return reader.certificates
    }
    private static func contentData(_ node: Node) throws -> Data {
        let fields = try node.sequence()
        guard fields.count == 2, try fields[0].oid() == dataOID else { throw Failure.unsupported }
        return try fields[1].explicit().octets()
    }
    private enum Digest {
        case sha1, sha256, sha384, sha512
        init(oid: String, hmac: Bool = false) throws {
            switch oid {
            case hmac ? "1.2.840.113549.2.7" : "1.3.14.3.2.26": self = .sha1
            case hmac ? "1.2.840.113549.2.9" : "2.16.840.1.101.3.4.2.1": self = .sha256
            case hmac ? "1.2.840.113549.2.10" : "2.16.840.1.101.3.4.2.2": self = .sha384
            case hmac ? "1.2.840.113549.2.11" : "2.16.840.1.101.3.4.2.3": self = .sha512
            default: throw Failure.unsupported
            }
        }
        var length: Int { switch self { case .sha1: return 20; case .sha256: return 32; case .sha384: return 48; case .sha512: return 64 } }
        var block: Int { switch self { case .sha1, .sha256: return 64; case .sha384, .sha512: return 128 } }
        var prf: CCPseudoRandomAlgorithm {
            switch self {
            case .sha1: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            case .sha256: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            case .sha384: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
            case .sha512: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
            }
        }
        func hash(_ data: Data) -> Data {
            switch self {
            case .sha1: return Data(Insecure.SHA1.hash(data: data))
            case .sha256: return Data(SHA256.hash(data: data))
            case .sha384: return Data(SHA384.hash(data: data))
            case .sha512: return Data(SHA512.hash(data: data))
            }
        }
        func isValidMAC(_ expected: Data, authenticating data: Data, key: Data) -> Bool {
            let key = SymmetricKey(data: key)
            switch self {
            case .sha1: return HMAC<Insecure.SHA1>.isValidAuthenticationCode(expected, authenticating: data, using: key)
            case .sha256: return HMAC<SHA256>.isValidAuthenticationCode(expected, authenticating: data, using: key)
            case .sha384: return HMAC<SHA384>.isValidAuthenticationCode(expected, authenticating: data, using: key)
            case .sha512: return HMAC<SHA512>.isValidAuthenticationCode(expected, authenticating: data, using: key)
            }
        }
    }
    private struct Reader {
        let password: String
        var certificates: [Data] = []
        var bags = 0
        var legacyPassword: Data?
        var remainingWork = 2_000_000
        mutating func charge(_ iterations: Int, blocks: Int = 1) throws {
            guard (1...1_000_000).contains(iterations), blocks > 0, iterations <= remainingWork / blocks else { throw Failure.limits }
            remainingWork -= iterations * blocks
            try Task.checkCancellation()
        }
        func bmpPassword() -> Data {
            var bytes = Data()
            for unit in password.utf16 { bytes.append(UInt8(unit >> 8)); bytes.append(UInt8(unit & 255)) }
            bytes.append(contentsOf: [0, 0]); return bytes
        }
        mutating func verifyMAC(_ safe: Data, mac: Node) throws {
            let fields = try mac.sequence()
            guard (2...3).contains(fields.count) else { throw Failure.malformed }
            let info = try fields[0].sequence()
            guard info.count == 2 else { throw Failure.malformed }
            let algorithm = try info[0].sequence()
            guard (1...2).contains(algorithm.count), algorithm.count == 1 || algorithm[1].tag == 0x05 && algorithm[1].value.isEmpty else { throw Failure.malformed }
            let digest = try Digest(oid: algorithm[0].oid()), expected = try info[1].octets(), salt = try fields[1].octets()
            let iterations = try fields.count == 3 ? fields[2].integer() : 1
            guard expected.count == digest.length, !salt.isEmpty, salt.count <= 1024 else { throw Failure.malformed }
            let key = try derive(digest: digest, password: bmpPassword(), salt: salt, iterations: iterations, id: 3, count: digest.length)
            if digest.isValidMAC(expected, authenticating: safe, key: key) { legacyPassword = bmpPassword(); return }
            // Historical PKCS #12 implementations distinguish empty from null
            // passwords. Only try the alternate representation for an empty one.
            if password.isEmpty {
                let alternate = try derive(digest: digest, password: Data(), salt: salt, iterations: iterations, id: 3, count: digest.length)
                if digest.isValidMAC(expected, authenticating: safe, key: alternate) { legacyPassword = Data(); return }
            }
            throw Failure.authentication
        }
        /// RFC 7292 Appendix B. Diversifier 1=key, 2=IV, 3=MAC key.
        mutating func derive(digest: Digest, password: Data, salt: Data, iterations: Int, id: UInt8, count: Int) throws -> Data {
            let v = digest.block, blocks = (count + digest.length - 1) / digest.length
            try charge(iterations, blocks: blocks)
            func repeatToBlock(_ data: Data) -> [UInt8] {
                guard !data.isEmpty else { return [] }
                let bytes = [UInt8](data), length = v * ((bytes.count + v - 1) / v)
                return (0..<length).map { bytes[$0 % bytes.count] }
            }
            let d = Data(repeating: id, count: v)
            var input = repeatToBlock(salt) + repeatToBlock(password), output = Data()
            for _ in 0..<blocks {
                var a = digest.hash(d + Data(input))
                if iterations > 1 {
                    for round in 1..<iterations {
                        if round % 1024 == 0 { try Task.checkCancellation() }
                        a = digest.hash(a)
                    }
                }
                output.append(a)
                let bytes = [UInt8](a), b = (0..<v).map { bytes[$0 % bytes.count] }
                for start in stride(from: 0, to: input.count, by: v) {
                    var carry = 1
                    for index in (0..<v).reversed() {
                        let sum = Int(input[start + index]) + Int(b[index]) + carry
                        input[start + index] = UInt8(sum & 255); carry = sum >> 8
                    }
                }
            }
            return output.prefix(count)
        }
        mutating func decrypt(_ encrypted: Data, algorithm: Node) throws -> Data {
            let fields = try algorithm.sequence()
            guard fields.count == 2 else { throw Failure.malformed }
            let oid = try fields[0].oid()
            let key: Data, iv: Data, cipher: CCAlgorithm
            if oid == "1.2.840.113549.1.5.13" {
                let pbes = try fields[1].sequence()
                guard pbes.count == 2 else { throw Failure.malformed }
                let kdf = try pbes[0].sequence(), encryption = try pbes[1].sequence()
                guard kdf.count == 2, try kdf[0].oid() == "1.2.840.113549.1.5.12", encryption.count == 2 else { throw Failure.unsupported }
                let parameters = try kdf[1].sequence()
                guard (2...4).contains(parameters.count) else { throw Failure.malformed }
                let salt = try parameters[0].octets(), iterations = try parameters[1].integer()
                guard !salt.isEmpty, salt.count <= 1024 else { throw Failure.malformed }
                let cipherOID = try encryption[0].oid(), length: Int
                switch cipherOID {
                case "2.16.840.1.101.3.4.1.2": cipher = CCAlgorithm(kCCAlgorithmAES); length = 16
                case "2.16.840.1.101.3.4.1.22": cipher = CCAlgorithm(kCCAlgorithmAES); length = 24
                case "2.16.840.1.101.3.4.1.42": cipher = CCAlgorithm(kCCAlgorithmAES); length = 32
                case "1.2.840.113549.3.7": cipher = CCAlgorithm(kCCAlgorithm3DES); length = 24
                default: throw Failure.unsupported
                }
                iv = try encryption[1].octets()
                guard iv.count == (cipher == CCAlgorithm(kCCAlgorithmAES) ? 16 : 8) else { throw Failure.malformed }
                var index = 2
                if parameters.count > index, parameters[index].tag == 0x02 {
                    guard try parameters[index].integer() == length else { throw Failure.malformed }; index += 1
                }
                var digest = Digest.sha1
                if parameters.count > index {
                    let prf = try parameters[index].sequence()
                    guard (1...2).contains(prf.count), prf.count == 1 || prf[1].tag == 0x05 && prf[1].value.isEmpty else { throw Failure.malformed }
                    digest = try Digest(oid: prf[0].oid(), hmac: true); index += 1
                }
                guard parameters.count == index else { throw Failure.malformed }
                try charge(iterations, blocks: (length + digest.length - 1) / digest.length)
                let passwordBytes = Data(password.utf8)
                var derived = Data(count: length)
                let status = derived.withUnsafeMutableBytes { out in
                    passwordBytes.withUnsafeBytes { pass in salt.withUnsafeBytes { salt in
                        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress?.assumingMemoryBound(to: Int8.self), passwordBytes.count,
                                             salt.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, digest.prf, UInt32(iterations),
                                             out.baseAddress?.assumingMemoryBound(to: UInt8.self), length)
                    } }
                }
                guard status == kCCSuccess else { throw Failure.decryption }; key = derived
            } else {
                let parameters = try fields[1].sequence()
                guard parameters.count == 2 else { throw Failure.malformed }
                let salt = try parameters[0].octets(), iterations = try parameters[1].integer()
                guard !salt.isEmpty, salt.count <= 1024 else { throw Failure.malformed }
                let length: Int
                switch oid {
                case "1.2.840.113549.1.12.1.3": cipher = CCAlgorithm(kCCAlgorithm3DES); length = 24
                case "1.2.840.113549.1.12.1.5": cipher = CCAlgorithm(kCCAlgorithmRC2); length = 16
                case "1.2.840.113549.1.12.1.6": cipher = CCAlgorithm(kCCAlgorithmRC2); length = 5
                default: throw Failure.unsupported
                }
                let password = legacyPassword ?? bmpPassword()
                key = try derive(digest: .sha1, password: password, salt: salt, iterations: iterations, id: 1, count: length)
                iv = try derive(digest: .sha1, password: password, salt: salt, iterations: iterations, id: 2, count: 8)
            }
            var output = Data(count: encrypted.count + 16), written = 0
            let capacity = output.count
            let status = output.withUnsafeMutableBytes { out in key.withUnsafeBytes { key in iv.withUnsafeBytes { iv in encrypted.withUnsafeBytes { input in
                CCCrypt(CCOperation(kCCDecrypt), cipher, CCOptions(kCCOptionPKCS7Padding), key.baseAddress, key.count, iv.baseAddress,
                        input.baseAddress, input.count, out.baseAddress, capacity, &written)
            } } } }
            guard status == kCCSuccess else { throw Failure.decryption }
            return output.prefix(written)
        }
        mutating func collect(_ contents: Data, depth: Int) throws {
            guard depth <= 6 else { throw Failure.limits }
            for bag in try Node.root(contents).sequence() {
                bags += 1; guard bags <= 128 else { throw Failure.limits }
                let fields = try bag.sequence()
                guard (2...3).contains(fields.count) else { throw Failure.malformed }
                let oid = try fields[0].oid()
                if oid == "1.2.840.113549.1.12.10.1.3" {
                    let certificate = try fields[1].explicit().sequence()
                    guard certificate.count == 2, try certificate[0].oid() == "1.2.840.113549.1.9.22.1" else { throw Failure.unsupported }
                    let bytes = try certificate[1].explicit().octets()
                    guard bytes.count <= 128 * 1024, certificates.count < 32 else { throw Failure.limits }
                    guard try Node.root(bytes).tag == 0x30 else { throw Failure.malformed }
                    if !certificates.contains(bytes) { certificates.append(bytes) }
                } else if oid == "1.2.840.113549.1.12.10.1.6" {
                    let nested = try fields[1].explicit()
                    try collect(nested.encoded, depth: depth + 1)
                } else { throw Failure.unsupported }
            }
        }
    }
    /// Definite-length DER only. All slices and child counts are bounded before
    /// allocating or indexing; unknown BER/crypto forms fail explicitly.
    private struct Node {
        let tag: UInt8
        let value: Data
        let encoded: Data
        static func root(_ data: Data) throws -> Node {
            var cursor = 0
            let node = try read(data, cursor: &cursor)
            guard cursor == data.count else { throw Failure.malformed }; return node
        }
        static func read(_ data: Data, cursor: inout Int) throws -> Node {
            let bytes = [UInt8](data), start = cursor
            guard cursor + 2 <= bytes.count else { throw Failure.malformed }
            let tag = bytes[cursor], initial = Int(bytes[cursor + 1]); cursor += 2
            var length = initial
            if initial & 0x80 != 0 {
                let count = initial & 0x7F
                guard (1...4).contains(count), cursor + count <= bytes.count, bytes[cursor] != 0 else { throw Failure.malformed }
                length = 0
                for _ in 0..<count { length = (length << 8) | Int(bytes[cursor]); cursor += 1 }
                guard length >= 128 else { throw Failure.malformed }
            }
            guard length <= bytes.count - cursor else { throw Failure.malformed }
            let end = cursor + length
            let node = Node(tag: tag, value: Data(bytes[cursor..<end]), encoded: Data(bytes[start..<end]))
            cursor = end; return node
        }
        func children() throws -> [Node] {
            var cursor = 0, nodes: [Node] = []
            while cursor < value.count {
                guard nodes.count < 256 else { throw Failure.limits }
                nodes.append(try Self.read(value, cursor: &cursor))
            }
            return nodes
        }
        func sequence() throws -> [Node] { guard tag == 0x30 else { throw Failure.malformed }; return try children() }
        func explicit() throws -> Node { guard tag == 0xA0 else { throw Failure.malformed }; return try Self.root(value) }
        func octets() throws -> Data { guard tag == 0x04 else { throw Failure.malformed }; return value }
        func integer() throws -> Int {
            guard tag == 0x02, !value.isEmpty, value.count <= 4, value.first! < 128 else { throw Failure.malformed }
            if value.count > 1, value.first == 0, value[value.index(after: value.startIndex)] < 128 { throw Failure.malformed }
            return value.reduce(0) { ($0 << 8) | Int($1) }
        }
        func oid() throws -> String {
            guard tag == 0x06, let first = value.first, value.count <= 64 else { throw Failure.malformed }
            var atoms = [Int(min(first / 40, 2)), Int(first) - Int(min(first / 40, 2)) * 40], current = 0
            for byte in value.dropFirst() {
                guard current <= Int.max >> 7 else { throw Failure.malformed }
                current = (current << 7) | Int(byte & 127)
                if byte & 128 == 0 { atoms.append(current); current = 0 }
            }
            guard value.last! & 128 == 0 else { throw Failure.malformed }
            return atoms.map(String.init).joined(separator: ".")
        }
    }
}
