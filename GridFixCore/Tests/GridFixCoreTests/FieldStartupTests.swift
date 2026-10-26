import Combine
import XCTest
@testable import GridFixCore

@MainActor
final class FieldStartupTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func saved() throws -> Backup.Document {
        var doc = Backup.Document(); doc.hasSettings = false
        doc.graphics = [.init(id: "route",name: "Saved CAFÉ route",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)])]
        let (track,bytes) = try TrackCodec.imported(name: "Patrol",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],now: 1000)
        doc.tracks = [track]; doc.trackFiles[track.id] = bytes
        doc.courseHistory = [.init(name: "Drill",points: 2,started: 100,total: 200,splits: [100,100])]
        return doc
    }
    private func wait(_ condition: () -> Bool,file: StaticString = #filePath,line: UInt = #line) async throws {
        let end = Date().addingTimeInterval(5)
        while !condition(), Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(),file: file,line: line)
    }
    func testDeferredLoadKeepsSavedBytesAndRefusesWritesExportsAndFalseEmptyReadsUntilPublication() async throws {
        let dir = try directory(), original = try saved()
        try FieldDataStore(directory: dir).restore(original)
        let index = dir.appendingPathComponent(FieldDataDisk.indexName), before = try Data(contentsOf: index)
        let store = FieldDataStore(directory: dir,loadImmediately: false), gate = FieldReadGate()
        var publishedOnMain = false
        let observation = store.$ready.dropFirst().sink { value in if value { publishedOnMain = Thread.isMainThread } }
        defer { gate.release(); observation.cancel() }
        let task = Task { await store.load { try gate.prepare($0) } }
        try await wait { gate.entered }
        XCTAssertFalse(store.ready); XCTAssertNil(store.loadError)
        XCTAssertThrowsError(try store.restoreSnapshot())
        XCTAssertThrowsError(try store.restore(Backup.Document()))
        XCTAssertThrowsError(try store.saveGraphic(original.graphics[0]))
        XCTAssertThrowsError(try store.points(for: original.tracks[0].id))
        XCTAssertThrowsError(try store.backup(waypoints: [],folders: [],settings: .init()))
        XCTAssertEqual(try Data(contentsOf: index),before)
        gate.release(); await task.value
        XCTAssertTrue(store.ready); XCTAssertNil(store.loadError); XCTAssertTrue(publishedOnMain)
        XCTAssertEqual(store.document.graphics,original.graphics)
        XCTAssertEqual(store.document.trackFiles,original.trackFiles)
        XCTAssertEqual(store.document.courseHistory,original.courseHistory)
        XCTAssertEqual(try Data(contentsOf: index),before,"Loading must not rewrite saved files")
    }
    func testConcurrentClientsShareReadAndCancelledWaiterCannotCancelOtherClientOrPublishEarly() async throws {
        let dir = try directory(), doc = try saved()
        try FieldDataStore(directory: dir).restore(doc)
        let store = FieldDataStore(directory: dir,loadImmediately: false), gate = FieldReadGate()
        defer { gate.release() }
        let first = Task { await store.load { try gate.prepare($0) } }
        try await wait { gate.entered }
        first.cancel()
        let second = Task { await store.load { try gate.prepare($0) } }
        await Task.yield(); XCTAssertFalse(store.ready)
        gate.release(); await first.value; await second.value
        XCTAssertTrue(store.ready); XCTAssertEqual(store.document.graphics,doc.graphics)
        XCTAssertEqual(gate.count,1)
        await store.load { _ in XCTFail("A loaded store must not be read again"); throw CancellationError() }
    }
    func testCancelledOnlyWaiterLeavesCompletedReadForNextClient() async throws {
        let dir = try directory(), doc = try saved()
        try FieldDataStore(directory: dir).restore(doc)
        let store = FieldDataStore(directory: dir,loadImmediately: false), gate = FieldReadGate()
        defer { gate.release() }
        let first = Task { await store.load { try gate.prepare($0) } }
        try await wait { gate.entered }; first.cancel(); gate.release(); await first.value
        XCTAssertFalse(store.ready); XCTAssertNil(store.loadError)
        await store.load { _ in XCTFail("Reuse the completed read"); throw CancellationError() }
        XCTAssertTrue(store.ready); XCTAssertEqual(gate.count,1)
        XCTAssertEqual(store.document.trackFiles,doc.trackFiles)
    }
    func testCorruptIndexDoesNotFallbackToLegacyOrPermitEmptyBackupAndEdits() async throws {
        let dir = try directory(), doc = try saved()
        let legacy = try Backup.exportZip(doc), bad = Data("unreadable index".utf8)
        try legacy.write(to: dir.appendingPathComponent("field-data-v1.zip"))
        let index = dir.appendingPathComponent(FieldDataDisk.indexName); try bad.write(to: index)
        let store = FieldDataStore(directory: dir,loadImmediately: false)
        await store.load()
        XCTAssertTrue(store.ready); XCTAssertNotNil(store.loadError)
        XCTAssertTrue(store.document.graphics.isEmpty)
        XCTAssertThrowsError(try store.restoreSnapshot())
        XCTAssertThrowsError(try store.backup(waypoints: [],folders: [],settings: .init()))
        XCTAssertThrowsError(try store.saveGraphic(doc.graphics[0]))
        XCTAssertEqual(try Data(contentsOf: index),bad)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("field-data-v1.zip")),legacy)
    }
    func testLegacyWorkerReadPreservesArchiveAndMigratesOnlyAfterExplicitEdit() async throws {
        let dir = try directory(), doc = try saved(), archive = try Backup.exportZip(doc)
        let legacy = dir.appendingPathComponent("field-data-v1.zip"); try archive.write(to: legacy)
        let store = FieldDataStore(directory: dir,loadImmediately: false)
        await store.load { snapshot in XCTAssertFalse(Thread.isMainThread); return try snapshot.prepare() }
        XCTAssertTrue(store.ready); XCTAssertNil(store.loadError)
        XCTAssertEqual(store.document.trackFiles,doc.trackFiles)
        let index = dir.appendingPathComponent(FieldDataDisk.indexName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))
        var changed = doc.graphics[0]; changed.name = "Changed"
        try store.saveGraphic(changed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.path))
        XCTAssertEqual(try Data(contentsOf: legacy),archive)
    }
    func testPreparedReadCannotReplaceLoadedEditsOrAnotherStore() async throws {
        let dir = try directory(), doc = try saved()
        try FieldDataStore(directory: dir).restore(doc)
        let store = FieldDataStore(directory: dir,loadImmediately: false), snapshot = store.loadSnapshot()
        let prepared = try await Task.detached { try snapshot.prepare() }.value
        XCTAssertTrue(try store.publishLoad(prepared))
        var changed = doc.graphics[0]; changed.name = "Newer edit"; try store.saveGraphic(changed)
        XCTAssertFalse(try store.publishLoad(prepared))
        XCTAssertEqual(store.document.graphics[0].name,"Newer edit")
        let other = FieldDataStore(directory: dir,loadImmediately: false)
        XCTAssertThrowsError(try other.publishLoad(prepared)); XCTAssertFalse(other.ready)
    }
}

private final class FieldReadGate: @unchecked Sendable {
    private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
    private var didEnter = false, reads = 0
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return didEnter }
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func release() { semaphore.signal() }
    func prepare(_ snapshot: FieldDataStore.LoadSnapshot) throws -> FieldDataStore.PreparedLoad {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); didEnter = true; reads += 1; lock.unlock()
        guard semaphore.wait(timeout: .now()+10) == .success else { throw CancellationError() }
        return try snapshot.prepare()
    }
}
