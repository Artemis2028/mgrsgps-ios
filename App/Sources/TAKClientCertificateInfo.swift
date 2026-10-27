import Foundation
import Security

/// Public certificate metadata. Never stores or exports a private key/password.
struct TAKClientCertificateInfo: Equatable, Sendable {
    let subject: String
    let sha256: String
    let validity: TAKServerTrust.Validity?
    enum State: Equatable { case unknown, notYetActive, expired, expiresSoon, withinDates }
    func state(at now: Date) -> State {
        guard let validity else { return .unknown }
        if now < validity.notBefore { return .notYetActive }
        if now > validity.notAfter { return .expired }
        return validity.notAfter.timeIntervalSince(now) <= 30*86400 ? .expiresSoon : .withinDates
    }
    func status(at now: Date) -> String {
        switch state(at: now) {
        case .unknown: return "Certificate dates unavailable"
        case .notYetActive: return "Not active yet · check the device clock or certificate"
        case .expired: return "Expired · sign in to renew"
        case .expiresSoon: return "Expires within 30 days · renew before expiry"
        case .withinDates: return "Within certificate dates"
        }
    }
    static func certificate(_ certificate: SecCertificate) -> Self {
        let description = TAKServerTrust.describe(certificate)
        return .init(subject: String(description.subject.prefix(256)),sha256: description.sha256,
                     validity: TAKServerTrust.validity(SecCertificateCopyData(certificate) as Data))
    }
    static func credentials(_ value: TAKImportedCredentials) -> Self? {
        guard let identity = value.identity else { return nil }
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity,&certificate) == errSecSuccess,let certificate else { return nil }
        return Self.certificate(certificate)
    }
    static func read(store: TAKLocalStore,id: String) throws -> Self? {
        guard let archive = try store.credentials(id) else { return nil }
        // The public enrolled certificate remains readable even if its device
        // key is gone or the certificate has expired; do not load that key here.
        if let bytes = archive.enrollmentCertificate {
            guard let certificate = SecCertificateCreateWithData(nil,bytes as CFData) else { throw CocoaError(.fileReadCorruptFile) }
            return Self.certificate(certificate)
        }
        guard archive.client != nil else { return nil }
        return credentials(try TAKImportedCredentials.read(archive.package(TAKProfile())))
    }
    static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }
}
