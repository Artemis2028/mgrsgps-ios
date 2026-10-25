import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class ProtectedBackupIntegrationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func document() -> Backup.Document {
        .init(waypoints: [.init(id: "protected",name: "Secret OBJ",lat: 24,lon: 54,createdAt: 1)])
    }
    func testProtectedTransferRequiresPasswordBeforePublicationAndRetryRestores() async throws {
        let directory = try directory(), file = directory.appendingPathComponent("protected.mgrsgps")
        let doc = document(), transfer = BackupTransfer()
        let exported = expectation(description: "encrypted export")
        XCTAssertTrue(transfer.export(doc,password: "correct horse") { result in
            do { let bytes = try result.get(); XCTAssertTrue(BackupCrypto.isSealed(bytes)); try bytes.write(to: file) }
            catch { XCTFail(error.localizedDescription) }; exported.fulfill()
        })
        await fulfillment(of: [exported],timeout: 10)
        let points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory)
        let local = points.add(.init(name: "Keep local",lat: 25,lon: 55)); points.select(local.id)
        let needsPassword = expectation(description: "password required")
        XCTAssertTrue(transfer.restore(file,passwordRequired: { needsPassword.fulfill() },apply: { _ in XCTFail("Applied without password"); return "bad" },completion: { XCTFail($0) }))
        await fulfillment(of: [needsPassword],timeout: 5); XCTAssertNil(transfer.phase)
        let wrong = expectation(description: "wrong password")
        XCTAssertTrue(transfer.restore(file,password: "wrong password",apply: { _ in XCTFail("Applied wrong password"); return "bad" },completion: { XCTAssertTrue($0.contains("Nothing was restored"),$0); wrong.fulfill() }))
        await fulfillment(of: [wrong],timeout: 10)
        XCTAssertEqual(points.waypoints.map(\.id),[local.id]); XCTAssertEqual(points.selectedId,local.id)
        let restored = expectation(description: "restored")
        XCTAssertTrue(transfer.restore(file,password: "correct horse",apply: { document in
            await BackupCoordinator.restore(document,waypoints: points,fieldData: field,settings: settings)
        },completion: { XCTAssertTrue($0.hasPrefix("Restored"),$0); restored.fulfill() }))
        await fulfillment(of: [restored],timeout: 10)
        XCTAssertTrue(WaypointStore(directory: directory).waypoints.contains { $0.id == "protected" }); XCTAssertEqual(points.selectedId,local.id)
    }
    func testAuthenticationAndZIPValidationFinishBeforeAnyStoreMutation() async throws {
        let directory = try directory(), file = directory.appendingPathComponent("renamed.zip")
        let garbage = try await BackupPreparation.protect(Data("authenticated but not a ZIP".utf8),password: "correct horse")
        try garbage.write(to: file)
        let transfer = BackupTransfer(), failed = expectation(description: "invalid inner ZIP")
        XCTAssertTrue(transfer.restore(file,password: "correct horse",apply: { _ in XCTFail("Invalid ZIP published"); return "bad" },completion: { XCTAssertTrue($0.hasPrefix("Import failed")); failed.fulfill() }))
        await fulfillment(of: [failed],timeout: 10)
        var changed = try await BackupPreparation.protect(Backup.exportZip(document()),password: "correct horse"); changed[20] ^= 1
        try changed.write(to: file)
        do { _ = try await BackupPreparation.read(file,password: "correct horse"); XCTFail("Tampered file read") }
        catch { XCTAssertEqual(error as? BackupCrypto.Failure,.authentication) }
    }
    func testPlainBackupWithProtectedExtensionStillReadsByContentAndLimitIsPreserved() async throws {
        let directory = try directory(), file = directory.appendingPathComponent("ordinary.mgrsgps")
        try Backup.exportZip(document()).write(to: file)
        let ordinary = try await BackupPreparation.read(file)
        XCTAssertEqual(ordinary.waypoints,document().waypoints)
        let protected = try await BackupPreparation.protect(Backup.exportZip(document()),password: "correct horse")
        try protected.write(to: file)
        do { _ = try await BackupPreparation.read(file); XCTFail("Protected file parsed without password") }
        catch { XCTAssertEqual(error as? BackupCrypto.Failure,.passwordRequired) }
        let handle = try FileHandle(forWritingTo: file); try handle.truncate(atOffset: UInt64(BackupCrypto.maximumSealedBytes+1)); try handle.close()
        do { _ = try await BackupPreparation.read(file,password: "correct horse"); XCTFail("Oversized container accepted") } catch {}
    }
    func testCancelledProtectedReadDoesNotPublishOrPresentCompletion() async throws {
        let file = try directory().appendingPathComponent("protected.mgrsgps"), doc = document()
        try await BackupPreparation.protect(Backup.exportZip(doc),password: "correct horse").write(to: file)
        let transfer = BackupTransfer(); var applied = false, completed = false
        XCTAssertTrue(transfer.restore(file,password: "correct horse",apply: { _ in applied = true; return "bad" },completion: { _ in completed = true }))
        let cancelled = transfer.cancel()
        await cancelled?.value
        XCTAssertFalse(applied); XCTAssertFalse(completed); XCTAssertNil(transfer.phase)

    }
}
