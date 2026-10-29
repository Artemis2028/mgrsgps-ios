import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class BackupFileExportTests:XCTestCase {
    private func directory() throws -> URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)};return root
    }
    func testOrdinaryAndProtectedPreparationOwnFilesAndPreserveBackupProtocol() async throws {
        let fixture=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"zip64-full-backup",withExtension:"zip"))
        let doc=try Backup.importZip(Data(contentsOf:fixture)),root=try directory()
        let ordinary=try await BackupPreparation.prepareFile(doc,root:root)
        guard case .file(let file)=ordinary else {return XCTFail("Backup must retain a file payload")}
        let opened=try Backup.importZip(Data(contentsOf:file.url))
        XCTAssertEqual(opened.trackFiles,doc.trackFiles);XCTAssertEqual(opened.waypoints,doc.waypoints);XCTAssertEqual(opened.settingsKeys,doc.settingsKeys)
        let key=UUID().uuidString
        let protected=try await BackupPreparation.prepareFile(doc,password:key,root:root)
        guard case .file(let sealed)=protected else {return XCTFail("Protected backup must retain an owned file")}
        let bytes=try Data(contentsOf:sealed.url);XCTAssertTrue(BackupCrypto.isSealed(bytes))
        let restored=try Backup.importZip(BackupCrypto.open(bytes,password:key))
        XCTAssertEqual(restored.trackFiles,doc.trackFiles);XCTAssertEqual(restored.waypoints,doc.waypoints)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).count,2,"Provisional plaintext must be removed before protected presentation")
        let document=FieldExportDocumentFile(payload:ordinary,contentType:.zip,filename:"backup")
        guard case .file=document.payload else {return XCTFail("Files presenter must preserve file ownership")}
    }
    func testInvalidPreparationLeavesNoProviderFile() async throws {
        let root=try directory(),id=UUID().uuidString.lowercased()
        let doc=Backup.Document(tracks:[.init(id:id,name:"Missing",startedAt:0,endedAt:0,distanceM:0,pointCount:1)])
        do {_ = try await BackupPreparation.prepareFile(doc,root:root);XCTFail("Missing log exported")}
        catch {XCTAssertTrue(error.localizedDescription.contains("missing"))}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
    }
    func testCancelledPreparationCannotLeaveAnOwnedOutput() async throws {
        let root=try directory()
        let task=Task {withUnsafeCurrentTask {$0?.cancel()};return try await BackupPreparation.prepareFile(Backup.Document(),root:root)}
        do {_ = try await task.value;XCTFail("Cancelled preparation completed")}
        catch {XCTAssertTrue(error is CancellationError)}
        let deadline=Date().addingTimeInterval(3)
        while !(try FileManager.default.contentsOfDirectory(atPath:root.path)).isEmpty,Date()<deadline {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
    }
    func testFileTransferHonorsCancellationAndReportsSuccessfulCompletionOnMainActor() async throws {
        let transfer=BackupTransfer();var cancelledReported=false
        XCTAssertTrue(transfer.exportFile(Backup.Document()) {_ in cancelledReported=true})
        let cancelled=transfer.cancel();await cancelled?.value
        XCTAssertFalse(cancelledReported);XCTAssertNil(transfer.phase)
        let complete=expectation(description:"file prepared")
        XCTAssertTrue(transfer.exportFile(Backup.Document()) {result in
            XCTAssertTrue(Thread.isMainThread)
            if case .success(.file)=result {} else {XCTFail("Expected file result")}
            complete.fulfill()
        })
        await fulfillment(of:[complete],timeout:10);XCTAssertNil(transfer.phase)
    }
}
