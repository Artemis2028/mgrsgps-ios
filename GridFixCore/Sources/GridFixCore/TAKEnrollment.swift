import Foundation

/// The public, bounded parts of TAK certificate enrollment. Credentials and
/// private keys belong to the native client and are never represented here.
public enum TAKEnrollment {
    public struct Target: Equatable, Sendable {
        public let host: String
        public let enrollmentPort: Int
        public let streamPort: Int
        public init(host: String, enrollmentPort: Int = 8446, streamPort: Int = 8089) throws {
            let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.count <= 253,
                  value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:").contains($0) }),
                  (1...65535).contains(enrollmentPort), (1...65535).contains(streamPort) else {
                throw TAKCoT.Failure(message: "Enter a server hostname or IP address and valid ports")
            }
            var parts = URLComponents()
            parts.scheme = "https"; parts.host = value.contains(":") ? "[\(value)]" : value
            parts.port = enrollmentPort
            guard parts.url?.host != nil else { throw TAKCoT.Failure(message: "Invalid enrollment server address") }
            self.host = value; self.enrollmentPort = enrollmentPort; self.streamPort = streamPort
        }
        public func url(path: String, deviceUID: String? = nil) -> URL {
            var parts = URLComponents()
            parts.scheme = "https"; parts.host = host.contains(":") ? "[\(host)]" : host
            parts.port = enrollmentPort; parts.path = path
            if let deviceUID { parts.queryItems = [.init(name: "clientUid", value: deviceUID), .init(name: "version", value: "1")] }
            // The initializer validates the host and ports; callers supply fixed paths.
            return parts.url!
        }
    }
    public struct Link: Equatable, Sendable {
        public let target: Target
        public let username: String
        /// Ephemeral password/token. Never include this link in diagnostics.
        public let token: String
    }
    public static func link(_ text: String) throws -> Link {
        guard text.utf8.count <= 16_384, let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "tak", parts.host?.lowercased() == "com.atakmap.app",
              parts.path == "/enroll", parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else {
            throw TAKCoT.Failure(message: "Use a TAK enrollment link")
        }
        let items = parts.queryItems ?? []
        func one(_ name: String) throws -> String {
            let matches = items.filter { $0.name == name }
            guard matches.count == 1, let value = matches[0].value, !value.isEmpty else {
                throw TAKCoT.Failure(message: "The enrollment link is missing or repeats a required field")
            }
            return value
        }
        let address = try one("host"), username = try one("username"), token = try one("token")
        guard username.utf8.count <= 1024, !username.contains(":"),
              !username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), token.utf8.count <= 8192 else {
            throw TAKCoT.Failure(message: "The enrollment link contains invalid sign-in fields")
        }
        // ATAK links may supply host:streamPort; brackets disambiguate IPv6.
        guard let authority = URLComponents(string: "https://" + address), authority.user == nil,
              authority.password == nil, authority.path.isEmpty, authority.query == nil,
              authority.fragment == nil, let rawHost = authority.host else {
            throw TAKCoT.Failure(message: "The enrollment link contains an invalid server address")
        }
        let host = rawHost.hasPrefix("[") ? String(rawHost.dropFirst().dropLast()) : rawHost
        return try .init(target: .init(host: host, streamPort: authority.port ?? 8089), username: username, token: token)
    }

    public struct SubjectEntry: Equatable, Sendable {
        public let name: String
        public let value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }
    public static func configuration(_ bytes: Data) throws -> [SubjectEntry] {
        guard bytes.count <= 64 * 1024, let text = String(data: bytes, encoding: .utf8),
              text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw TAKCoT.Failure(message: "Invalid or oversized enrollment configuration")
        }
        let reader = ConfigurationReader(), parser = XMLParser(data: bytes)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), reader.hasRoot, !reader.invalid else { throw TAKCoT.Failure(message: "Invalid enrollment configuration") }
        return reader.entries
    }

    public struct Certificates: Equatable, Sendable {
        public let client: Data
        public let authorities: [Data]
    }
    public static func certificates(_ bytes: Data) throws -> Certificates {
        guard bytes.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], object.count <= 64 else {
            throw TAKCoT.Failure(message: "Invalid or oversized enrollment certificate reply")
        }
        func certificate(_ key: String) throws -> Data {
            guard var value = object[key] as? String, value.utf8.count <= 128 * 1024 else {
                throw TAKCoT.Failure(message: "Missing enrollment certificate")
            }
            if value.contains("-----BEGIN CERTIFICATE-----") {
                value = value.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                    .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            }
            guard let data = Data(base64Encoded: value.filter { !$0.isWhitespace }), !data.isEmpty, data.count <= 96 * 1024 else {
                throw TAKCoT.Failure(message: "Invalid enrollment certificate encoding")
            }
            return data // Native Security.framework validates X.509 and key ownership.
        }
        let keys = object.keys.filter { $0.hasPrefix("ca") && !$0.dropFirst(2).isEmpty && $0.dropFirst(2).allSatisfy(\.isNumber) }.sorted()
        guard !keys.isEmpty, keys.count <= 16 else { throw TAKCoT.Failure(message: "Enrollment returned no usable server CA chain") }
        var authorities: [Data] = []
        for key in keys { let value = try certificate(key); if !authorities.contains(value) { authorities.append(value) } }
        return try .init(client: certificate("signedCert"), authorities: authorities)
    }

    /// PKCS#10 as used by Android: UTF-8 subject, RSA SPKI, no attributes,
    /// SHA256-with-RSA PKCS#1 v1.5. The signer retains the private key.
    public enum CSR {
        public static func info(rsaPublicKeyPKCS1: Data, subject: [SubjectEntry], username: String) throws -> Data {
            guard !username.isEmpty, username.utf8.count <= 1024,
                  !username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  subject.count <= 16, !rsaPublicKeyPKCS1.isEmpty, rsaPublicKeyPKCS1.count <= 8192 else {
                throw TAKCoT.Failure(message: "Invalid enrollment certificate request")
            }
            let oids: [String: Data] = ["O": Data([0x55, 0x04, 0x0A]), "OU": Data([0x55, 0x04, 0x0B]), "CN": Data([0x55, 0x04, 0x03])]
            guard subject.allSatisfy({ ["O", "OU"].contains($0.name) }) else { throw TAKCoT.Failure(message: "The enrollment server cannot override the username") }
            var rdns = Data()
            for entry in subject + [.init(name: "CN", value: username)] {
                guard let oid = oids[entry.name], entry.value.utf8.count <= 4096,
                      !entry.value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw TAKCoT.Failure(message: "Unsupported enrollment subject field")
                }
                if entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                rdns += tlv(0x31, tlv(0x30, tlv(0x06, oid) + tlv(0x0C, Data(entry.value.utf8))))
            }
            let rsa = tlv(0x30, tlv(0x06, Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])) + Data([0x05, 0x00]))
            let spki = tlv(0x30, rsa + tlv(0x03, Data([0]) + rsaPublicKeyPKCS1))
            return tlv(0x30, Data([0x02, 0x01, 0]) + tlv(0x30, rdns) + spki + Data([0xA0, 0]))
        }
        public static func request(info: Data, signature: Data) -> Data {
            let algorithm = tlv(0x30, tlv(0x06, Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])) + Data([0x05, 0x00]))
            return tlv(0x30, info + algorithm + tlv(0x03, Data([0]) + signature))
        }
        public static func body(_ der: Data) -> Data {
            let bytes = Array(der.base64EncodedString().utf8)
            var lines = Data()
            for start in stride(from: 0, to: bytes.count, by: 64) { lines.append(contentsOf: bytes[start..<min(start + 64, bytes.count)]); lines.append(10) }
            return lines
        }
        private static func tlv(_ tag: UInt8, _ contents: Data) -> Data {
            var length = contents.count, octets: [UInt8] = []
            repeat { octets.insert(UInt8(length & 255), at: 0); length >>= 8 } while length != 0
            let prefix = contents.count < 128 ? [UInt8(contents.count)] : [0x80 | UInt8(octets.count)] + octets
            return Data([tag] + prefix) + contents
        }
    }
}

private final class ConfigurationReader: NSObject, XMLParserDelegate {
    var entries: [TAKEnrollment.SubjectEntry] = []
    var invalid = false
    var hasRoot = false
    private var depth = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        guard depth <= 32 else { invalid = true; parser.abortParsing(); return }
        if depth == 1 {
            guard name == "certificateConfig" else { invalid = true; parser.abortParsing(); return }
            hasRoot = true
        }
        guard name == "nameEntry", let field = attributes["name"], ["O", "OU"].contains(field), let value = attributes["value"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard entries.count < 16, value.utf8.count <= 4096,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            invalid = true; parser.abortParsing(); return
        }
        entries.append(.init(name: field, value: value))
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
}
