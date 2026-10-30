import Foundation
import GridFixCore
import Security

/// Imported only within the iOS app sandbox. No host Keychain import and no
/// passwords copied into UserDefaults, backups, diagnostics or error messages.
struct TAKImportedCredentials {
    let identity: SecIdentity?
    let anchors: [SecCertificate]
    static func read(_ package: TAKServerPackage) throws -> Self {
        func contents(_ data: Data, password: String?, label: String) throws -> [[String: Any]] {
            var items: CFArray?
            let options = [kSecImportExportPassphrase as String: password ?? ""] as CFDictionary
            let status = SecPKCS12Import(data as CFData, options, &items)
            if status == errSecSuccess, (items as? [Any])?.isEmpty != false {
                throw TAKCoT.Failure(message: "The client PKCS #12 file contains no usable identity. Include the client certificate and its private key.")
            }
            guard status == errSecSuccess,
                  let values = items as? [[String: Any]], !values.isEmpty else {
                throw TAKCoT.Failure(message: "Unable to read \(label) (Security status \(status)). Check its password and PKCS #12 format.")
            }
            return values
        }
        var anchors: [SecCertificate] = []
        if let data = package.caPKCS12 {
            if let certificate = SecCertificateCreateWithData(nil, data as CFData) {
                anchors = [certificate]
            } else if let pem = String(data: data, encoding: .utf8), pem.contains("-----BEGIN CERTIFICATE-----") {
                let blocks = pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst()
                for block in blocks {
                    guard let end = block.range(of: "-----END CERTIFICATE-----"),
                          let der = Data(base64Encoded: block[..<end.lowerBound].filter { !$0.isWhitespace }),
                          let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
                        throw TAKCoT.Failure(message: "Invalid PEM server CA")
                    }
                    anchors.append(certificate)
                }
            } else {
                anchors = try PKCS12TrustStore.certificates(data, password: package.caPassword ?? "").map { bytes in
                    guard let certificate = SecCertificateCreateWithData(nil, bytes as CFData) else {
                        throw TAKCoT.Failure(message: "The server trust store contains an invalid X.509 certificate")
                    }
                    return certificate
                }
            }
            guard !anchors.isEmpty else { throw TAKCoT.Failure(message: "The server trust store contains no certificates") }
        }
        var identity: SecIdentity?
        if let data = package.clientPKCS12 {
            let entries = try contents(data, password: package.clientPassword, label: "client identity")
            let identities = entries.compactMap { $0[kSecImportItemIdentity as String] }
            guard identities.count == 1, CFGetTypeID(identities[0] as CFTypeRef) == SecIdentityGetTypeID() else {
                throw TAKCoT.Failure(message: "The client file must contain one certificate and its private key")
            }
            identity = (identities[0] as! SecIdentity)
        }
        return .init(identity: identity, anchors: anchors)
    }
}
