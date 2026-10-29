import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class ProtectedFileIntegrationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testEveryExportFormatProtectsOnlySealedBytesAndReopensByContentAfterRename() async throws {
        let root = try directory(), point = Waypoint(id: "p",name: "OP CAFÉ",lat: 35.1,lon: -79)
        for format in TextInterchangeFormat.allCases {
            let plain = try await FieldExportPreparation.prepare(.library(format,[point],.init()))
            let sealed = try await FieldExportPreparation.protect(plain,password: "Nørth 雪 🧭")
            XCTAssertTrue(sealed.protected); XCTAssertEqual(sealed.filename,plain.completeFilename+".mgrsgps")
            let file = FieldExportDocumentFile(sealed)
            XCTAssertEqual(file.contentType,.gridFixProtectedBackup); XCTAssertTrue(try BackupCrypto.isSealed(file.data))
            XCTAssertNotEqual(try file.data,try plain.data)
            let url = root.appendingPathComponent("renamed-"+format.rawValue+".zip")
            try file.data.write(to: url)
            XCTAssertThrowsError(try InterchangeFileReader.preview(url,format: nil,knownFolders: [])) { error in
                XCTAssertEqual(error as? BackupCrypto.Failure,.passwordRequired)
            }
            XCTAssertThrowsError(try InterchangeFileReader.preview(url,format: nil,knownFolders: [],password: "incorrect"))
            let result = try InterchangeFileReader.preview(url,format: nil,knownFolders: [],password: "Nørth 雪 🧭")
            XCTAssertEqual(result.format,format); XCTAssertEqual(result.document.waypoints.map(\.name),[point.name])
        }
    }
    func testBackupAndSingleFileRemainDistinctAndUnlockingDoesNotPublishRecords() async throws {
        let root = try directory(), points = WaypointStore(directory: root), field = FieldDataStore(directory: root)
        var backup = Backup.Document(); backup.hasSettings = false
        backup.waypoints = [.init(id: "p",name: "Backup point",lat: 35,lon: -79)]
        let url = root.appendingPathComponent("backup.mgrsgps")
        try BackupCrypto.seal(Backup.exportZip(backup),password: "test password").write(to: url)
        guard case let .backup(reviewed) = try InterchangeFileReader.review(url,format: nil,knownFolders: [],password: "test password") else { return XCTFail("Backup treated as interchange") }
        XCTAssertEqual(reviewed.waypoints,backup.waypoints); XCTAssertTrue(points.waypoints.isEmpty)
        XCTAssertThrowsError(try InterchangeFileReader.preview(url,format: nil,knownFolders: [],password: "test password"))
        let exported = try await FieldExportPreparation.protect(FieldExportPreparation.build(.library(.gpx,backup.waypoints,backup)),password: "test password")
        try exported.data.write(to: url)
        XCTAssertThrowsError(try InterchangeFileReader.backup(url,password: "test password")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Import file"))
        }
        let preview = try InterchangeFileReader.preview(url,format: nil,knownFolders: [],password: "test password")
        XCTAssertTrue(points.waypoints.isEmpty); XCTAssertTrue(field.document.graphics.isEmpty)
        let result = try await InterchangeCoordinator.apply(preview.document,waypoints: points,field: field)
        XCTAssertTrue(result.completed); XCTAssertEqual(points.waypoints.map(\.name),["Backup point"])
    }
    func testCancelledProtectedExportCannotPresentAndNormalRetryStillWorks() async throws {
        let entered = expectation(description: "writer entered"), gate = ProtectedExportGate()
        let request = FieldExportRequest.library(.csv,[],.init())
        let transfer = FieldExportTransfer(writer: { _ in entered.fulfill(); await gate.wait(); return .init(data: Data("plain".utf8),format: .csv,filename: "test") })
        XCTAssertTrue(transfer.start(request,password: "test password") { _ in XCTFail("Cancelled export presented") })
        await fulfillment(of: [entered],timeout: 3)
        let previous = transfer.cancel(); await gate.release(); await previous?.value
        XCTAssertNil(transfer.format)
        let retry = FieldExportTransfer(), done = expectation(description: "retry")
        XCTAssertTrue(retry.start(request,password: "test password") { result in
            guard case let .success(value) = result else { XCTFail("Retry failed"); done.fulfill(); return }
            XCTAssertTrue(value.protected)
            do { let bytes = try value.data; XCTAssertTrue(BackupCrypto.isSealed(bytes)) }
            catch { XCTFail(error.localizedDescription) }
            done.fulfill()
        })
        await fulfillment(of: [done],timeout: 5)
    }
}
private actor ProtectedExportGate {
    var continuation: CheckedContinuation<Void,Never>?
    var released = false
    func wait() async { if !released { await withCheckedContinuation { continuation = $0 } } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
