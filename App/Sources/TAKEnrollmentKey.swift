import Foundation
import GridFixCore
import Security

/// RSA private keys are created in this app's device-only Keychain. Only the
/// public key and its signatures leave Security.framework, never key bytes.
final class TAKEnrollmentKey {
    let tag: Data
    private let key: SecKey
    private var retained = false
    init(deviceUID: String) throws {
        tag = Data(("app.gridfix.tak.enrollment." + deviceUID + "." + UUID().uuidString).utf8)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrIsExtractable as String: false,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecAttrSynchronizable as String: false
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let value = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw TAKCoT.Failure(message: "Unable to create an enrollment key in the device Keychain")
        }
        key = value
    }
    deinit { if !retained { try? Self.delete(tag) } }

    func request(subject: [TAKEnrollment.SubjectEntry], username: String) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(key),
              let publicBytes = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw TAKCoT.Failure(message: "Unable to read the enrollment public key")
        }
        let info = try TAKEnrollment.CSR.info(rsaPublicKeyPKCS1: publicBytes, subject: subject, username: username)
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, info as CFData, &error) as Data? else {
            throw TAKCoT.Failure(message: "Unable to sign the enrollment request")
        }
        return TAKEnrollment.CSR.request(info: info, signature: signature)
    }
    func identity(certificate: Data, authorities: [Data]) throws -> TAKImportedCredentials {
        try Self.identity(key: key, certificate: certificate, authorities: authorities)
    }
    /// Call only after the credential archive and profile are both durable.
    func retainForProfile() { retained = true }
    static func load(tag: Data, certificate: Data, authorities: [Data]) throws -> TAKImportedCredentials {
        var query = query(tag)
        query[kSecReturnRef as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let result,
              CFGetTypeID(result) == SecKeyGetTypeID() else {
            throw TAKCoT.Failure(message: "The enrolled device key is unavailable; sign in again")
        }
        return try identity(key: result as! SecKey, certificate: certificate, authorities: authorities)
    }
    static func delete(_ tag: Data) throws {
        let status = SecItemDelete(query(tag) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TAKCoT.Failure(message: "Unable to remove an unused enrollment key")
        }
    }
    private static func query(_ tag: Data) -> [String: Any] {
        [kSecClass as String: kSecClassKey, kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
         kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
         kSecAttrApplicationTag as String: tag, kSecAttrSynchronizable as String: false]
    }
    private static func identity(key: SecKey, certificate: Data, authorities: [Data]) throws -> TAKImportedCredentials {
        guard let client = SecCertificateCreateWithData(nil, certificate as CFData),
              let identity = SecIdentityCreate(nil, client, key) else {
            throw TAKCoT.Failure(message: "The enrolled certificate does not match this device's key")
        }
        let anchors = try authorities.map { bytes -> SecCertificate in
            guard let value = SecCertificateCreateWithData(nil, bytes as CFData) else {
                throw TAKCoT.Failure(message: "The enrollment server returned an invalid CA certificate")
            }
            return value
        }
        guard !anchors.isEmpty else { throw TAKCoT.Failure(message: "The enrollment server returned no CA certificates") }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(([client] + anchors) as CFArray, SecPolicyCreateSSL(false, nil), &trust) == errSecSuccess,
              let trust, SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            throw TAKCoT.Failure(message: "The enrolled client certificate has an invalid chain or validity period")
        }
        return .init(identity: identity, anchors: anchors)
    }
}
