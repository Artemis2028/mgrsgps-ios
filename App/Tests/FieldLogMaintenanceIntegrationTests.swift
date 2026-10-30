import Combine
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class FieldLogMaintenanceIntegrationTests: XCTestCase {
    private func fixture() throws -> (URL,URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        let store = FieldDataStore(directory:root)
        let (meta,bytes) = try TrackCodec.imported(name:"Retained CAFÉ patrol",points:[.init(lat:24,lon:54)],now:1000)
        var doc = Backup.Document(); doc.hasSettings = false; doc.tracks = [meta]; doc.trackFiles[meta.id] = bytes
        _ = try store.restore(doc)
        let orphan = root.appendingPathComponent("field-track-logs-v2/"+UUID().uuidString.lowercased()+".txt")
        try Data("SYNTHETIC abandoned save".utf8).write(to:orphan)
        try FileManager.default.setAttributes([.modificationDate:Date.distantPast],ofItemAtPath:orphan.path)
        return (root,orphan)
    }
    func testReadRemainsReadOnlyAndMaintenanceDoesNotRepublishOrChangeLibrary() async throws {
        let (root,orphan) = try fixture(), store = FieldDataStore(directory:root,loadImmediately:false)
        await store.maintainTrackStorage()
        XCTAssertTrue(FileManager.default.fileExists(atPath:orphan.path))
        await store.load()
        XCTAssertTrue(store.ready); XCTAssertNil(store.loadError)
        XCTAssertTrue(FileManager.default.fileExists(atPath:orphan.path),"The worker read itself cannot delete files")
        let document = store.document, index = root.appendingPathComponent("field-data-v2.json"), bytes = try Data(contentsOf:index)
        var publications = 0
        let subscription = store.$document.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        await store.maintainTrackStorage()
        XCTAssertFalse(FileManager.default.fileExists(atPath:orphan.path))
        XCTAssertEqual(publications,0); XCTAssertEqual(store.document,document)
        XCTAssertEqual(try Data(contentsOf:index),bytes)
        XCTAssertEqual(FieldDataStore(directory:root).document.trackFiles,document.trackFiles)
    }
    func testUnreadableAndCancelledStartupMaintenancePreserveFilesThenHealthyRetryCanClean() async throws {
        let (root,orphan) = try fixture(), index = root.appendingPathComponent("field-data-v2.json")
        let bytes = try Data(contentsOf:index)
        try Data("damaged".utf8).write(to:index,options:.atomic)
        let damaged = FieldDataStore(directory:root,loadImmediately:false)
        await damaged.load(); XCTAssertNotNil(damaged.loadError)
        await damaged.maintainTrackStorage()
        XCTAssertTrue(FileManager.default.fileExists(atPath:orphan.path))
        try bytes.write(to:index,options:.atomic)
        let healthy = FieldDataStore(directory:root,loadImmediately:false)
        await healthy.load(); XCTAssertNil(healthy.loadError)
        let cancelled = Task { await healthy.maintainTrackStorage() }
        cancelled.cancel(); await cancelled.value
        XCTAssertTrue(FileManager.default.fileExists(atPath:orphan.path))
        await healthy.maintainTrackStorage()
        XCTAssertFalse(FileManager.default.fileExists(atPath:orphan.path))
        XCTAssertEqual(try Data(contentsOf:index),bytes)
    }
}
