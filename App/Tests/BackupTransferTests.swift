import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class BackupTransferTests: XCTestCase {
    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "zip64-full-backup",withExtension: "zip"))
    }

    func testRealZIP64ReadAndBackupEncodingRunOffMainThread() async throws {
        let document = try await BackupPreparation.read(fixture(),reader: { url in
            XCTAssertFalse(Thread.isMainThread)
            return try InterchangeFileReader.backup(url)
        })
        let bytes = try await BackupPreparation.encode(document,writer: { document in
            XCTAssertFalse(Thread.isMainThread)
            return try Backup.exportZip(document)
        })
        let reopened = try Backup.importZip(bytes)
        XCTAssertEqual(reopened.waypoints,document.waypoints)
        XCTAssertEqual(reopened.graphics,document.graphics)
        XCTAssertEqual(reopened.trackFiles,document.trackFiles)
        XCTAssertEqual(reopened.settings,document.settings)
    }

    func testCancellationReachesProviderWorkerEvenIfProviderReturnsLate() async throws {
        let entered = expectation(description: "worker entered")
        let release = DispatchSemaphore(value: 0)
        let file = try fixture()
        let pending = Task {
            try await BackupPreparation.read(file,reader: { url in
                XCTAssertFalse(Thread.isMainThread)
                entered.fulfill()
                guard release.wait(timeout: .now()+5) == .success else { throw CocoaError(.fileReadUnknown) }
                // Model a provider that completes a coordinated read despite
                // cancellation. Its document must never escape preparation.
                return try InterchangeFileReader.backup(url)
            })
        }
        await fulfillment(of: [entered],timeout: 3)
        pending.cancel(); release.signal()
        do { _ = try await pending.value; XCTFail("Cancelled worker returned a document") }
        catch { XCTAssertTrue(error is CancellationError,"\(error)") }
    }

    func testPendingProviderReadLeavesMainActorResponsiveAndMergesLatestEdits() async throws {
        let entered = expectation(description: "provider read started"), done = expectation(description: "restored")
        let suspended = SuspendedBackupRead(entered: entered)
        let transfer = BackupTransfer(reader: { _ in await suspended.read() })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), settings = AppSettings(directory: directory)
        XCTAssertTrue(transfer.restore(try fixture(),apply: { document in
            BackupCoordinator.restore(document,waypoints: points,fieldData: field,settings: settings)
        },completion: { message in XCTAssertFalse(message.contains("stopped"),message); done.fulfill() }))
        await fulfillment(of: [entered],timeout: 3)
        XCTAssertEqual(transfer.phase,.reading)
        // This main-actor edit executes while provider work is suspended. Restore
        // must merge into this current store rather than replacing its old copy.
        let fresh = points.add(.init(name: "Added while reading",lat: 24,lon: 54))
        points.select(fresh.id)
        let document = try InterchangeFileReader.backup(fixture())
        await suspended.finish(document)
        await fulfillment(of: [done],timeout: 3)
        XCTAssertNil(transfer.phase)
        let reopened = WaypointStore(directory: directory)
        XCTAssertTrue(reopened.waypoints.contains { $0.id == fresh.id })
        XCTAssertTrue(reopened.waypoints.contains { $0.id == "contract-vertex" })
        XCTAssertEqual(reopened.selectedId,fresh.id)
        XCTAssertEqual(try FieldDataStore(directory: directory).points(for: document.tracks[0].id).count,2)
    }

    func testCancellationSuppressesLateRestoreAndDoesNotCancelNewExport() async throws {
        let entered = expectation(description: "read started"), exported = expectation(description: "new export completed")
        let suspended = SuspendedBackupRead(entered: entered)
        let transfer = BackupTransfer(reader: { _ in await suspended.read() })
        var applied = false, reported = false
        XCTAssertTrue(transfer.restore(try fixture(),apply: { _ in applied = true; return "bad" },completion: { _ in reported = true }))
        await fulfillment(of: [entered],timeout: 3)
        let canceled = transfer.cancel()
        XCTAssertNil(transfer.phase)
        let document = try InterchangeFileReader.backup(fixture())
        XCTAssertTrue(transfer.export(document) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            exported.fulfill()
        })
        await suspended.finish(document)
        await canceled?.value
        await fulfillment(of: [exported],timeout: 3)
        XCTAssertFalse(applied); XCTAssertFalse(reported); XCTAssertNil(transfer.phase)
    }

    func testSecondRequestCannotReplacePendingOperation() async throws {
        let entered = expectation(description: "read started")
        let suspended = SuspendedBackupRead(entered: entered)
        let transfer = BackupTransfer(reader: { _ in await suspended.read() })
        XCTAssertTrue(transfer.restore(try fixture(),apply: { _ in XCTFail("Cancelled restore applied"); return "bad" },completion: { _ in XCTFail("Cancelled restore reported") }))
        await fulfillment(of: [entered],timeout: 3)
        XCTAssertFalse(transfer.export(Backup.Document()) { _ in XCTFail("Busy export started") })
        XCTAssertEqual(transfer.phase,.reading)
        let canceled = transfer.cancel()
        await suspended.finish(Backup.Document())
        await canceled?.value
        XCTAssertNil(transfer.phase)
    }

    func testPreparationFailureReportsAndAllowsRetry() async throws {
        let failed = expectation(description: "read failed"), exported = expectation(description: "retry")
        let transfer = BackupTransfer(reader: { _ in throw CocoaError(.fileReadCorruptFile) })
        XCTAssertTrue(transfer.restore(try fixture(),apply: { _ in XCTFail("Invalid document applied"); return "bad" },completion: {
            XCTAssertTrue($0.hasPrefix("Import failed:")); failed.fulfill()
        }))
        await fulfillment(of: [failed],timeout: 3)
        XCTAssertNil(transfer.phase)
        XCTAssertTrue(transfer.export(Backup.Document()) { result in
            switch result {
            case .success(let bytes):
                do { _ = try Backup.importZip(bytes) } catch { XCTFail(error.localizedDescription) }
            case .failure(let error): XCTFail(error.localizedDescription)
            }
            exported.fulfill()
        })
        await fulfillment(of: [exported],timeout: 3)
        XCTAssertNil(transfer.phase)
    }
}

private actor SuspendedBackupRead {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Backup.Document,Never>?
    init(entered: XCTestExpectation) { self.entered = entered }
    func read() async -> Backup.Document {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }
    func finish(_ document: Backup.Document) {
        continuation?.resume(returning: document); continuation = nil
    }
}
