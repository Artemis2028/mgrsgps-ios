import XCTest
@testable import GridFixCore

final class BackupCryptoTests: XCTestCase {
    private struct Vector: Decodable { var file: String; var passwordBase64: String; var iterations: Int
        var password: String { String(data: Data(base64Encoded: passwordBase64)!,encoding: .utf8)! }
    }
    private func bytes(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name,withExtension: nil)))
    }
    private func vectors() throws -> [Vector] { try JSONDecoder().decode([Vector].self,from: bytes("backup-crypto-vectors.json")) }
    func testIndependentJCAFixturesAuthenticateDecodeAndMatchDeterministicSwiftCiphertext() throws {
        let zip = try bytes("android-backup-contract.zip")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("gridfix-crypto-interop")
        try FileManager.default.createDirectory(at: output,withIntermediateDirectories: true)
        for (i,vector) in try vectors().enumerated() {
            let android = try bytes(vector.file)
            XCTAssertTrue(BackupCrypto.isSealed(android))
            XCTAssertEqual(try BackupCrypto.open(android,password: vector.password),zip)
            let document = try Backup.importZip(BackupCrypto.open(android,password: vector.password))
            XCTAssertEqual(document.waypoints.first?.name,"Contract route WP 2")
            let swift = try BackupCrypto.seal(zip,password: vector.password,salt: Data(1...16),nonce: Data(32...43),rounds: vector.iterations)
            XCTAssertEqual(swift,android,"JCA parity vector \(i)")
            // Independently opened by GenerateBackupCryptoFixtures.java too.
            try BackupCrypto.seal(zip,password: vector.password).write(to: output.appendingPathComponent("swift-protected-\(i).mgrsgps"))
        }
    }
    func testWrongPasswordsTamperingAndUnauthenticatedHeadersNeverProducePlaintext() throws {
        let vector = try XCTUnwrap(vectors().first), original = try bytes(vector.file)
        for password in ["wrong password","",vector.password+" "] {
            XCTAssertThrowsError(try BackupCrypto.open(original,password: password)) { XCTAssertEqual($0 as? BackupCrypto.Failure,.authentication) }
        }
        for index in [15,16,31,32,43,44,original.count/2,original.count-1] {
            var changed = original; changed[index] ^= 1
            XCTAssertThrowsError(try BackupCrypto.open(changed,password: vector.password)) { XCTAssertEqual($0 as? BackupCrypto.Failure,.authentication) }
        }
    }
    func testWorkFactorBoundsRejectBeforeDerivationAndMalformedContainersFail() throws {
        let vector = try XCTUnwrap(vectors().first), original = try bytes(vector.file)
        for rounds: UInt32 in [0,99_999,5_000_001,UInt32.max] {
            var bytes = original
            bytes.replaceSubrange(12..<16,with: [UInt8((rounds >> 24)&255),UInt8((rounds >> 16)&255),UInt8((rounds >> 8)&255),UInt8(rounds&255)])
            XCTAssertThrowsError(try BackupCrypto.open(bytes,password: vector.password)) { XCTAssertEqual($0 as? BackupCrypto.Failure,.authentication) }
        }
        for length in [0,11,12,43,44,59,60] {
            XCTAssertThrowsError(try BackupCrypto.open(Data(original.prefix(length)),password: vector.password)) { XCTAssertEqual($0 as? BackupCrypto.Failure,.invalidEnvelope) }
        }
        XCTAssertFalse(BackupCrypto.isSealed(try bytes("android-backup-contract.zip")))
    }
    func testFreshRandomnessAndAndroidUTF16MinimumWithoutNormalization() throws {
        let zip = try bytes("android-backup-contract.zip")
        let first = try BackupCrypto.seal(zip,password: "correct horse"), second = try BackupCrypto.seal(zip,password: "correct horse")
        XCTAssertNotEqual(first,second); XCTAssertNotEqual(first[16..<32],second[16..<32]); XCTAssertNotEqual(first[32..<44],second[32..<44])
        XCTAssertThrowsError(try BackupCrypto.seal(zip,password: "short")) { XCTAssertEqual($0 as? BackupCrypto.Failure,.passwordTooShort) }
        let compass = "🧭🧭🧭🧭"
        XCTAssertEqual(compass.count,4); XCTAssertEqual(compass.utf16.count,8)
        XCTAssertEqual(try BackupCrypto.open(BackupCrypto.seal(zip,password: compass),password: compass),zip)
        let decomposed = try XCTUnwrap(vectors().first { $0.password.contains("route") })
        XCTAssertThrowsError(try BackupCrypto.open(bytes(decomposed.file),password: decomposed.password.precomposedStringWithCanonicalMapping))
    }
    func testSizeLimitsAndDataSlices() throws {
        let vector = try XCTUnwrap(vectors().first), encrypted = try bytes(vector.file)
        let padded = Data([0,1,2])+encrypted
        XCTAssertEqual(try BackupCrypto.open(padded.dropFirst(3),password: vector.password),try bytes("android-backup-contract.zip"))
        XCTAssertThrowsError(try BackupCrypto.open(Data(count: BackupCrypto.maximumSealedBytes+1),password: vector.password)) { XCTAssertEqual($0 as? BackupCrypto.Failure,.oversized) }
        XCTAssertThrowsError(try BackupCrypto.seal(Data(count: BackupCrypto.maximumSealedBytes),password: vector.password)) { XCTAssertEqual($0 as? BackupCrypto.Failure,.oversized) }
    }
    func testAlreadyCancelledOperationsStopBeforeKeyDerivation() async throws {
        let zip = try bytes("android-backup-contract.zip"), sealed = try bytes("jca-protected-0.mgrsgps")
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try BackupCrypto.seal(zip,password: "correct horse")) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertThrowsError(try BackupCrypto.open(sealed,password: "correct horse")) { XCTAssertTrue($0 is CancellationError) }
        }
        try await task.value
    }
}
