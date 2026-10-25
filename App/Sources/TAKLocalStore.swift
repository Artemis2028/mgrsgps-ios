import CryptoKit
import Foundation
import GridFixCore
import Security

/// Local identity and preferences are excluded from backup. Restoring a backup
/// onto a second device must not clone its outbound TAK UIDs or trust decisions.
struct TAKProfile: Codable {
    var uid = "MGRSGPS-" + UUID().uuidString
    var callsign = "MGRS-" + String(UUID().uuidString.prefix(4))
    var host = ""
    var port = 8089
    var tls = true
    var title = ""
    var pin: String?
    var showRemote = true
    var sharedFolders: Set<String>?
}
struct TAKCredentialArchive: Codable {
    let ca: Data?
    let caPassword: String?
    let client: Data?
    let clientPassword: String?
    init(_ package: TAKServerPackage) {
        ca = package.caPKCS12; caPassword = package.caPassword
        client = package.clientPKCS12; clientPassword = package.clientPassword
    }
    func package(_ profile: TAKProfile) -> TAKServerPackage {
        .init(description: profile.title, host: profile.host, port: profile.port, usesTLS: profile.tls,
              caPKCS12: ca, caPassword: caPassword, clientPKCS12: client, clientPassword: clientPassword)
    }
}
struct TAKLocalStore {
    let directory: URL
    init(root: URL) throws {
        directory = root.appendingPathComponent("TAKLocal", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var url = directory, values = URLResourceValues()
        values.isExcludedFromBackup = true; try url.setResourceValues(values)
    }
    func readProfile() throws -> TAKProfile {
        let url = directory.appendingPathComponent("profile.json")
        if !FileManager.default.fileExists(atPath: url.path) { let profile = TAKProfile(); try write(profile); return profile }
        return try JSONDecoder().decode(TAKProfile.self, from: Data(contentsOf: url))
    }
    func write(_ profile: TAKProfile) throws {
        try JSONEncoder().encode(profile).write(to: directory.appendingPathComponent("profile.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func readSent(profile: TAKProfile) throws -> [String: String] {
        let url = sentURL(profile)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }
    func writeSent(_ sent: [String: String], profile: TAKProfile) throws {
        try JSONEncoder().encode(sent).write(to: sentURL(profile), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func sentURL(_ profile: TAKProfile) -> URL {
        let endpoint = "\(profile.tls)|\(profile.host.lowercased())|\(profile.port)"
        let hash = SHA256.hash(data: Data(endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("sent-" + hash + ".json")
    }
    private func query(_ uid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.gridfix.tak.credentials", kSecAttrAccount as String: uid,
         kSecAttrSynchronizable as String: false]
    }
    func credentials(_ uid: String) throws -> TAKCredentialArchive? {
        var query = query(uid)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return try JSONDecoder().decode(TAKCredentialArchive.self, from: data)
    }
    func saveCredentials(_ credentials: TAKCredentialArchive, uid: String) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let existing = query(uid)
        var status = SecItemUpdate(existing as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(existing.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    func deleteCredentials(_ uid: String) throws {
        let status = SecItemDelete(query(uid) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private func failure(_ status: OSStatus) -> TAKCoT.Failure {
        .init(message: "TAK credentials are unavailable in the device Keychain (\(status))")
    }
}
