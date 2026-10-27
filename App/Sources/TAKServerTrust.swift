import CryptoKit
import Foundation
import Security

/// A pin can excuse a name mismatch, never an untrusted chain, expiry or a
/// changed certificate. No socket is allowed to send until this returns trusted.
enum TAKServerTrust {
    struct Certificate: Equatable {
        let subject: String
        let names: [String]
        let sha256: String
    }
    enum Decision: Equatable {
        case trusted
        case nameMismatch(Certificate)
        case certificateChanged(Certificate)
        case refused(String)
    }
    static func evaluate(_ trust: SecTrust, host: String, anchors: [SecCertificate], pinnedSHA256: String?) -> Decision {
        guard !host.isEmpty, let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = certificates.first else { return .refused("The server did not provide a certificate") }
        let metadata = describe(leaf)
        if let pin = pinnedSHA256, pin != metadata.sha256 { return .certificateChanged(metadata) }
        // Offline validation deliberately prevents a certificate from inducing
        // requests to arbitrary AIA/OCSP endpoints during a local TAK connection.
        guard SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil)) == errSecSuccess else {
            return .refused("Unable to configure server certificate validation")
        }
        if !anchors.isEmpty {
            guard SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else {
                return .refused("Unable to validate against the imported server CA")
            }
        }
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            return .refused("Server certificate validation failed: " + String((error.map { CFErrorCopyDescription($0) as String } ?? "Untrusted, expired or invalid certificate").prefix(600)))
        }
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            return .refused("Unable to verify the server name")
        }
        if SecTrustEvaluateWithError(trust, &error) { return .trusted }
        // Re-evaluate the chain after the hostname failure, including on a
        // reconnect with an approved pin. The pin must not bypass validity.
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil)) == errSecSuccess,
              SecTrustEvaluateWithError(trust, &error) else {
            return .refused("The server certificate is no longer valid")
        }
        return pinnedSHA256 == metadata.sha256 ? .trusted : .nameMismatch(metadata)
    }
    static func describe(_ certificate: SecCertificate) -> Certificate {
        let data = SecCertificateCopyData(certificate) as Data
        return .init(subject: SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown subject",
                     names: subjectAlternativeNames(data),
                     sha256: SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined(separator: ":"))
    }

    /// Read only the X.509 subjectAltName extension. This is display metadata;
    /// Security.framework remains the sole authority for name matching.
    static func subjectAlternativeNames(_ data: Data) -> [String] {
        let bytes = [UInt8](data)
        guard bytes.count <= 1024 * 1024, let root = DER.read(bytes, at: 0, end: bytes.count), root.tag == 0x30,
              root.next == bytes.count, let tbs = DER.children(bytes, in: root)?.first, tbs.tag == 0x30,
              let fields = DER.children(bytes, in: tbs), let wrapper = fields.first(where: { $0.tag == 0xA3 }),
              let extensions = DER.children(bytes, in: wrapper), extensions.count == 1, extensions[0].tag == 0x30,
              let entries = DER.children(bytes, in: extensions[0]) else { return [] }
        var names: [String] = []
        for entry in entries where entry.tag == 0x30 {
            guard let parts = DER.children(bytes, in: entry), let oid = parts.first, oid.tag == 0x06,
                  Array(bytes[oid.body]) == [0x55, 0x1D, 0x11], let value = parts.last, value.tag == 0x04,
                  let sequence = DER.read(bytes, at: value.body.lowerBound, end: value.body.upperBound), sequence.tag == 0x30,
                  sequence.next == value.body.upperBound, let generalNames = DER.children(bytes, in: sequence) else { continue }
            for name in generalNames {
                let octets = Array(bytes[name.body])
                if name.tag == 0x82, !octets.isEmpty, octets.count <= 253,
                   octets.allSatisfy({ $0 >= 33 && $0 <= 126 }), let dns = String(bytes: octets, encoding: .ascii) {
                    names.append(dns)
                } else if name.tag == 0x87, octets.count == 4 {
                    names.append(octets.map(String.init).joined(separator: "."))
                } else if name.tag == 0x87, octets.count == 16 {
                    names.append(stride(from: 0, to: 16, by: 2).map { String(format: "%x", UInt16(octets[$0]) << 8 | UInt16(octets[$0 + 1])) }.joined(separator: ":"))
                }
                if names.count >= 100 { return names }
            }
        }
        return names
    }
    struct Validity: Equatable, Sendable {
        let notBefore: Date
        let notAfter: Date
    }
    /// RFC 5280 section 4.1.2.5 display metadata only. This never authorizes a
    /// connection; Security.framework still validates the complete chain.
    static func validity(_ data: Data) -> Validity? {
        guard data.count <= 1024 * 1024 else { return nil }
        let bytes = [UInt8](data)
        guard let root = DER.read(bytes,at: 0,end: bytes.count),root.tag == 0x30,root.next == bytes.count,
              let certificate = DER.children(bytes,in: root),certificate.count == 3,
              certificate[0].tag == 0x30,let fields = DER.children(bytes,in: certificate[0]) else { return nil }
        let offset = fields.first?.tag == 0xA0 ? 1 : 0
        guard fields.count >= offset+6, fields[offset].tag == 0x02,
              fields[offset+1].tag == 0x30, fields[offset+2].tag == 0x30,
              fields[offset+3].tag == 0x30,let times = DER.children(bytes,in: fields[offset+3]),times.count == 2,
              let start = certificateTime(bytes,times[0]),let end = certificateTime(bytes,times[1]),start <= end else { return nil }
        return .init(notBefore: start,notAfter: end)
    }
    private static func certificateTime(_ bytes: [UInt8],_ node: DER) -> Date? {
        let text = Array(bytes[node.body]),yearDigits: Int
        switch node.tag {
        case 0x17: yearDigits = 2
        case 0x18: yearDigits = 4
        default: return nil
        }
        guard text.count == yearDigits+11,text.last == 90,text.dropLast().allSatisfy({ (48...57).contains($0) }) else { return nil }
        func number(_ offset: Int,_ count: Int = 2) -> Int { text[offset..<(offset+count)].reduce(0) { $0*10+Int($1-48) } }
        var year = number(0,yearDigits)
        if yearDigits == 2 { year += year >= 50 ? 1900 : 2000 }
        let month = number(yearDigits),day = number(yearDigits+2),hour = number(yearDigits+4),minute = number(yearDigits+6),second = number(yearDigits+8)
        guard (1...9999).contains(year),(1...12).contains(month),(1...31).contains(day),
              (0...23).contains(hour),(0...59).contains(minute),(0...59).contains(second) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year,month: month,day: day,hour: hour,minute: minute,second: second)
        guard let date = calendar.date(from: components) else { return nil }
        let actual = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from: date)
        guard actual.year == year,actual.month == month,actual.day == day,actual.hour == hour,actual.minute == minute,actual.second == second else { return nil }
        return date
    }

    private struct DER {
        let tag: UInt8
        let body: Range<Int>
        var next: Int { body.upperBound }
        static func read(_ bytes: [UInt8], at start: Int, end: Int) -> DER? {
            guard start >= 0, end <= bytes.count, start + 2 <= end else { return nil }
            let tag = bytes[start], initial = Int(bytes[start + 1])
            var cursor = start + 2, length = initial
            if initial & 0x80 != 0 {
                let count = initial & 0x7F
                guard count > 0, count <= 4, cursor + count <= end, bytes[cursor] != 0 else { return nil }
                length = 0
                for index in cursor..<(cursor + count) { length = (length << 8) | Int(bytes[index]) }
                guard length >= 128 else { return nil }
                cursor += count
            }
            guard length <= end - cursor else { return nil }
            return .init(tag: tag, body: cursor..<(cursor + length))
        }
        static func children(_ bytes: [UInt8], in parent: DER) -> [DER]? {
            var cursor = parent.body.lowerBound, values: [DER] = []
            while cursor < parent.body.upperBound {
                guard values.count < 2048, let value = read(bytes, at: cursor, end: parent.body.upperBound) else { return nil }
                values.append(value); cursor = value.next
            }
            return values
        }
    }
}
