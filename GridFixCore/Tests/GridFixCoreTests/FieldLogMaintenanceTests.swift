import XCTest
@testable import GridFixCore

final class FieldLogMaintenanceTests: XCTestCase {
    private func fixture() throws -> (URL,FieldDataStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        let store = FieldDataStore(directory:root)
        let (track,bytes) = try TrackCodec.imported(name:"Indexed patrol",points:[.init(lat:24,lon:54)],now:1000)
        var doc = Backup.Document(); doc.hasSettings = false; doc.tracks = [track]; doc.trackFiles[track.id] = bytes
        _ = try store.restore(doc)
        return (root,store)
    }
    private func logs(_ root: URL) -> URL { root.appendingPathComponent(FieldDataDisk.logsName) }
    private func file(_ root: URL,name: String = UUID().uuidString.lowercased()+".txt",age: TimeInterval = 2*24*60*60) throws -> URL {
        let path = logs(root).appendingPathComponent(name)
        try Data("SYNTHETIC abandoned preparation".utf8).write(to:path)
        try FileManager.default.setAttributes([.modificationDate:Date().addingTimeInterval(-age)],ofItemAtPath:path.path)
        return path
    }
    func testOnlyOldUnreferencedOwnedLogsAreRemovedWithoutChangingSavedData() throws {
        let (root,store) = try fixture(), before = store.document
        let index = root.appendingPathComponent(FieldDataDisk.indexName), indexBytes = try Data(contentsOf:index)
        let indexed = try XCTUnwrap(FileManager.default.contentsOfDirectory(at:logs(root),includingPropertiesForKeys:nil).first)
        try FileManager.default.setAttributes([.modificationDate:Date.distantPast],ofItemAtPath:indexed.path)
        let orphan = try file(root), recent = try file(root,age:60), foreign = try file(root,name:"keep.txt")
        let nested = logs(root).appendingPathComponent(UUID().uuidString.lowercased()+".txt")
        try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:false)
        let outside = root.appendingPathComponent("outside.txt"), legacy = root.appendingPathComponent("field-data-v1.zip")
        try Data("keep outside".utf8).write(to:outside); try Data("keep legacy".utf8).write(to:legacy)
        let link = logs(root).appendingPathComponent(UUID().uuidString.lowercased()+".txt")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:outside)
        let live = root.appendingPathComponent("LiveRecording/points.txt")
        try FileManager.default.createDirectory(at:live.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("keep live".utf8).write(to:live)
        XCTAssertEqual(try XCTUnwrap(store.trackMaintenanceSnapshot()).prune(),1)
        XCTAssertFalse(FileManager.default.fileExists(atPath:orphan.path))
        for kept in [indexed,recent,foreign,nested,link,outside,legacy,live] { XCTAssertTrue(FileManager.default.fileExists(atPath:kept.path),kept.lastPathComponent) }
        XCTAssertEqual(try Data(contentsOf:index),indexBytes); XCTAssertEqual(store.document,before)
        let reopened = FieldDataStore(directory:root)
        XCTAssertNil(reopened.loadError); XCTAssertEqual(reopened.document.trackFiles,before.trackFiles)
    }
    func testPendingSaveLeaseSurvivesAgeThresholdThenIndexedPublication() throws {
        let (root,store) = try fixture()
        let existing = Set(try FileManager.default.contentsOfDirectory(at:logs(root),includingPropertiesForKeys:nil))
        let (meta,bytes) = try TrackCodec.imported(name:"Pending patrol",points:[.init(lat:25,lon:55)],now:2000)
        var doc = Backup.Document(); doc.hasSettings = false; doc.tracks = [meta]; doc.trackFiles[meta.id] = bytes
        let pending = try store.restoreSnapshot().prepare(doc)
        let staged = try XCTUnwrap(Set(FileManager.default.contentsOfDirectory(at:logs(root),includingPropertiesForKeys:nil)).subtracting(existing).first)
        try FileManager.default.setAttributes([.modificationDate:Date.distantPast],ofItemAtPath:staged.path)
        XCTAssertEqual(try XCTUnwrap(store.trackMaintenanceSnapshot()).prune(),0)
        XCTAssertEqual(try Data(contentsOf:staged),bytes)
        XCTAssertEqual(try store.publishRestore(pending)?.tracks,1)
        XCTAssertEqual(try XCTUnwrap(store.trackMaintenanceSnapshot()).prune(),0)
        let reopened = FieldDataStore(directory:root)
        XCTAssertNil(reopened.loadError); XCTAssertEqual(reopened.document.trackFiles[meta.id],bytes)
    }
    func testCorruptMissingAndChangedIndexesNeverAuthorizeCleanup() throws {
        let (root,store) = try fixture(), orphan = try file(root)
        let snapshot = try XCTUnwrap(store.trackMaintenanceSnapshot())
        let index = root.appendingPathComponent(FieldDataDisk.indexName), original = try Data(contentsOf:index)
        try Data("damaged index".utf8).write(to:index,options:.atomic)
        XCTAssertThrowsError(try snapshot.prune()); XCTAssertTrue(FileManager.default.fileExists(atPath:orphan.path))
        XCTAssertThrowsError(try FieldDataStore(directory:root).trackMaintenanceSnapshot())
        try FileManager.default.removeItem(at:index)
        XCTAssertNil(try FieldDataStore(directory:root).trackMaintenanceSnapshot())
        XCTAssertThrowsError(try snapshot.prune()); XCTAssertTrue(FileManager.default.fileExists(atPath:orphan.path))
        try original.write(to:index,options:.atomic)
        let current = FieldDataStore(directory:root), stale = try XCTUnwrap(current.trackMaintenanceSnapshot())
        try current.saveGraphic(.init(id:"new",name:"new",type:"checkpoint",points:[.init(lat:24,lon:54)]))
        XCTAssertThrowsError(try stale.prune()); XCTAssertTrue(FileManager.default.fileExists(atPath:orphan.path))
    }
    func testCleanupIsBoundedAndCanContinueWithoutRewritingIndex() throws {
        let (root,store) = try fixture()
        for _ in 0..<70 { _ = try file(root) }
        let snapshot = try XCTUnwrap(store.trackMaintenanceSnapshot())
        let before = try Data(contentsOf:root.appendingPathComponent(FieldDataDisk.indexName))
        XCTAssertEqual(try snapshot.prune(),64); XCTAssertEqual(try snapshot.prune(),6); XCTAssertEqual(try snapshot.prune(),0)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(FieldDataDisk.indexName)),before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:logs(root).path).count,1)
    }
    func testCancelledWorkerLeavesOrphansUntouched() async throws {
        let (root,store) = try fixture(), orphan = try file(root), snapshot = try XCTUnwrap(store.trackMaintenanceSnapshot())
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try snapshot.prune()
        }
        do { _ = try await worker.value; XCTFail("Cancelled cleanup must stop") }
        catch is CancellationError { }
        XCTAssertTrue(FileManager.default.fileExists(atPath:orphan.path))
    }
    func testSymlinkedLogDirectoryIsNeverCleaned() throws {
        let (root,store) = try fixture(), orphan = try file(root)
        let moved = root.appendingPathComponent("retained-files")
        try FileManager.default.moveItem(at:logs(root),to:moved)
        try FileManager.default.createSymbolicLink(at:logs(root),withDestinationURL:moved)
        XCTAssertEqual(try XCTUnwrap(store.trackMaintenanceSnapshot()).prune(),0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:moved.appendingPathComponent(orphan.lastPathComponent).path))
    }
}
