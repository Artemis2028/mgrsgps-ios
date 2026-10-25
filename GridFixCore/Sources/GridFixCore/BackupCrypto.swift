import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Android BackupCrypto.kt (`d6c971b`) envelope. This protects the ordinary ZIP;
/// it does not replace the ZIP parser's member/decompression budgets.
public enum BackupCrypto {
    public static let iterations = 310_000
    public static let minimumPasswordLength = 8
    public static let maximumSealedBytes = 33 * 1024 * 1024
    static let magic = Data("MGRSGPS-ENC1".utf8)
    static let headerBytes = magic.count+4+16+12

    public enum Failure: LocalizedError, Equatable {
        case passwordRequired, passwordTooShort, invalidEnvelope, authentication, oversized, random, derivation
        public var errorDescription: String? {
            switch self {
            case .passwordRequired: return "This backup requires its password"
            case .passwordTooShort: return "Use at least 8 characters"
            case .invalidEnvelope: return "Not a protected MGRS GPS backup"
            case .authentication: return "Wrong password, or the file has been changed. Nothing was restored."
            case .oversized: return "Backup exceeds the supported size limit"
            case .random: return "Unable to generate backup encryption randomness"
            case .derivation: return "Unable to derive the backup encryption key"
            }
        }
    }

    public static func isSealed(_ bytes: Data) -> Bool { bytes.starts(with: magic) }

    public static func seal(_ plain: Data,password: String) throws -> Data {
        try seal(plain,password: password,salt: randomBytes(16),nonce: randomBytes(12),rounds: iterations)
    }

    /// Internal deterministic entry point for independently generated interop
    /// vectors. Production always uses fresh Security-framework randomness.
    static func seal(_ plain: Data,password: String,salt: Data,nonce: Data,rounds: Int) throws -> Data {
        guard password.utf16.count >= minimumPasswordLength else { throw Failure.passwordTooShort }
        guard plain.count <= maximumSealedBytes-headerBytes-16 else { throw Failure.oversized }
        guard salt.count == 16,nonce.count == 12,(100_000...5_000_000).contains(rounds) else { throw Failure.invalidEnvelope }
        try Task.checkCancellation()
        let header = magic+Data([UInt8((rounds >> 24)&255),UInt8((rounds >> 16)&255),UInt8((rounds >> 8)&255),UInt8(rounds&255)])+salt+nonce
        let key = try key(password,salt: salt,rounds: rounds)
        try Task.checkCancellation()
        let box = try AES.GCM.seal(plain,using: key,nonce: AES.GCM.Nonce(data: nonce),authenticating: header)
        return header+box.ciphertext+box.tag
    }

    public static func open(_ bytes: Data,password: String) throws -> Data {
        guard bytes.count <= maximumSealedBytes else { throw Failure.oversized }
        guard isSealed(bytes),bytes.count > headerBytes+16 else { throw Failure.invalidEnvelope }
        // Rebase slices: DataProtocol inputs need not start at index zero.
        let data = Data(bytes), start = magic.count
        let rounds = data[start..<start+4].reduce(0) { ($0 << 8)|Int($1) }
        guard (100_000...5_000_000).contains(rounds) else { throw Failure.authentication }
        try Task.checkCancellation()
        let key = try key(password,salt: data.subdata(in: start+4..<start+20),rounds: rounds)
        try Task.checkCancellation()
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: data[start+20..<headerBytes]),ciphertext: data[headerBytes..<data.count-16],tag: data.suffix(16))
            return try AES.GCM.open(box,using: key,authenticating: data.prefix(headerBytes))
        } catch { throw Failure.authentication }
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        guard bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault,count,$0.baseAddress!) }) == errSecSuccess else { throw Failure.random }
        return bytes
    }
    private static func key(_ password: String,salt: Data,rounds: Int) throws -> SymmetricKey {
        // Java PBEKeySpec/PBKDF2WithHmacSHA256 uses unnormalized UTF-8. Explicit
        // byte length preserves embedded NULs; never trim/normalize passwords.
        var passwordBytes = Array(password.utf8), derived = [UInt8](repeating: 0,count: 32)
        defer {
            _ = passwordBytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self,repeating: 0) }
            _ = derived.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self,repeating: 0) }
        }
        let status = passwordBytes.withUnsafeBytes { pw in
            salt.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),pw.baseAddress?.assumingMemoryBound(to: CChar.self),pw.count,salt.baseAddress!.assumingMemoryBound(to: UInt8.self),salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),UInt32(rounds),&derived,derived.count)
            }
        }
        guard status == kCCSuccess else { throw Failure.derivation }
        return SymmetricKey(data: derived)
    }
}
