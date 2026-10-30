import XCTest
@testable import GridFixCore

@MainActor
final class TrackCacheUpgradeTests: XCTestCase {
    private func fixture(legacy: Bool = false) throws -> (URL,Backup.Document) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:dir) }
        let (track,bytes) = try TrackCodec.imported(name:"Patrol CAFÉ",points:[.init(lat:24,lon:54),.init(lat:24.01,lon:54.01,time:1000)],now:1)
        var doc = Backup.Document(); doc.hasSettings = false
        doc.tracks = [track]; doc.trackFiles[track.id] = bytes
        doc.graphics = [.init(id:"route",name:"Saved route",type:"route",points:[.init(lat:24,lon:54),.init(lat:25,lon:55)])]
        doc.courseHistory = [.init(name:"Drill",points:2,started:1,total:2,splits:[1,1])]
        if legacy { try Backup.exportZip(doc).write(to:dir.appendingPathComponent("field-data-v1.zip")) }
        else { _ = try FieldDataStore(directory:dir).restore(doc); try removeReceipt(dir) }
        return (dir,doc)
    }
    private func index(_ dir: URL) -> URL { dir.appendingPathComponent(FieldDataDisk.indexName) }
    private func removeReceipt(_ dir: URL) throws {
        let path = index(dir)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        var logs = try XCTUnwrap(json["logs"] as? [String:[String:Any]])
        for id in logs.keys { logs[id]?.removeValue(forKey:"summary") }
        json["logs"] = logs
        try JSONSerialization.data(withJSONObject:json).write(to:path,options:.atomic)
    }
    private func load(_ dir: URL) async -> FieldDataStore {
        let store = FieldDataStore(directory:dir,loadImmediately:false)
        await store.load { try $0.prepare(deferTrackContents:true) }
        return store
    }
    private func logBytes(_ dir: URL) throws -> [String:Data] {
        let folder = dir.appendingPathComponent(FieldDataDisk.logsName)
        guard FileManager.default.fileExists(atPath:folder.path) else { return [:] }
        return try Dictionary(uniqueKeysWithValues:FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter { $0.pathExtension == "txt" }.map { ($0.lastPathComponent,try Data(contentsOf:$0)) })
    }
    func testReceiptlessLoadAutomaticallyPersistsCacheAndReusesExactLogNamesAndBytes() async throws {
        let (dir,doc) = try fixture(), before = try logBytes(dir)
        let store = await load(dir)
        XCTAssertNil(store.loadError); XCTAssertTrue(store.ready)
        XCTAssertTrue(store.document.trackFiles.isEmpty); XCTAssertEqual(store.document.localTrackFiles.count,1)
        XCTAssertNil(try store.trackCacheUpgradeSnapshot())
        XCTAssertEqual(try logBytes(dir),before)
        XCTAssertEqual(store.document.tracks,doc.tracks); XCTAssertEqual(store.document.graphics,doc.graphics)
        XCTAssertEqual(store.document.courseHistory,doc.courseHistory)
        var reads = 0,parses = 0
        let (reopened,_) = try FieldDataDisk.read(index(dir),deferTrackContents:true,readContents:{ source in reads += 1; return try source.read() },summarize:{ bytes in parses += 1; return try TrackCodec.summarizeLocal(bytes) })
        XCTAssertEqual(reads,0); XCTAssertEqual(parses,0)
        XCTAssertEqual(reopened.tracks,doc.tracks)
        XCTAssertEqual(try reopened.trackData(doc.tracks[0].id),doc.trackFiles[doc.tracks[0].id])
    }
    func testPreparationOnlyDoesNotRewriteAndHealthySecondLaunchDoesNotRewrite() async throws {
        let (dir,_) = try fixture(), path = index(dir), original = try Data(contentsOf:path)
        let store = FieldDataStore(directory:dir,loadImmediately:false)
        XCTAssertTrue(try store.publishLoad(store.loadSnapshot().prepare(deferTrackContents:true)))
        XCTAssertEqual(try Data(contentsOf:path),original)
        let snapshot = try XCTUnwrap(store.trackCacheUpgradeSnapshot())
        let prepared = try snapshot.prepareTrackCacheUpgrade()
        XCTAssertEqual(try Data(contentsOf:path),original)
        XCTAssertTrue(try store.publishEdit(prepared))
        let upgraded = try Data(contentsOf:path),stamp = try FieldDataReadSource.Stamp.read(path)
        _ = await load(dir)
        XCTAssertEqual(try Data(contentsOf:path),upgraded)
        XCTAssertEqual(try FieldDataReadSource.Stamp.read(path),stamp)
    }
    func testLegacyArchiveMigratesAutomaticallyWithoutChangingRecoveryBytesOrRecords() async throws {
        let (dir,doc) = try fixture(legacy:true)
        let path = dir.appendingPathComponent("field-data-v1.zip"),original = try Data(contentsOf:path)
        let store = await load(dir)
        XCTAssertNil(store.loadError); XCTAssertTrue(FileManager.default.fileExists(atPath:index(dir).path))
        XCTAssertEqual(try Data(contentsOf:path),original)
        XCTAssertEqual(store.document.graphics,doc.graphics); XCTAssertEqual(store.document.courseHistory,doc.courseHistory)
        XCTAssertEqual(store.document.tracks,doc.tracks); XCTAssertTrue(store.document.trackFiles.isEmpty)
        XCTAssertEqual(try store.document.trackData(doc.tracks[0].id),doc.trackFiles[doc.tracks[0].id])
        let reopened = await load(dir)
        XCTAssertEqual(reopened.document,store.document)
    }
    func testConcurrentEditWinsOverPreparedCacheAndKeepsItsNewMetadata() throws {
        let (dir,doc) = try fixture()
        let store = FieldDataStore(directory:dir,loadImmediately:false)
        XCTAssertTrue(try store.publishLoad(store.loadSnapshot().prepare(deferTrackContents:true)))
        let pending = try XCTUnwrap(store.trackCacheUpgradeSnapshot()).prepareTrackCacheUpgrade()
        try store.moveTrack(doc.tracks[0].id,to:"Recon")
        let bytes = try Data(contentsOf:index(dir))
        XCTAssertFalse(try store.publishEdit(pending))
        XCTAssertEqual(try Data(contentsOf:index(dir)),bytes)
        XCTAssertEqual(FieldDataStore(directory:dir).document.tracks[0].folder,"Recon")
    }
    func testAnotherStorePublicationCannotBeOverwrittenByOldCache() throws {
        let (dir,doc) = try fixture()
        let store = FieldDataStore(directory:dir,loadImmediately:false)
        XCTAssertTrue(try store.publishLoad(store.loadSnapshot().prepare(deferTrackContents:true)))
        let pending = try XCTUnwrap(store.trackCacheUpgradeSnapshot()).prepareTrackCacheUpgrade()
        try FieldDataStore(directory:dir).moveTrack(doc.tracks[0].id,to:"Other")
        let bytes = try Data(contentsOf:index(dir))
        XCTAssertThrowsError(try store.publishEdit(pending))
        XCTAssertEqual(try Data(contentsOf:index(dir)),bytes)
        XCTAssertEqual(FieldDataStore(directory:dir).document.tracks[0].folder,"Other")
    }
    func testCorruptReceiptlessLogCannotBecomeWritableCacheOrOverwriteIndex() async throws {
        let (dir,_) = try fixture(), original = try Data(contentsOf:index(dir))
        let name = try XCTUnwrap(logBytes(dir).keys.first)
        let file = dir.appendingPathComponent(FieldDataDisk.logsName).appendingPathComponent(name)
        let bad = Data("24 54 0\n91 55 1\n".utf8); try bad.write(to:file,options:.atomic)
        let store = await load(dir)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.trackCacheUpgradeSnapshot())
        XCTAssertEqual(try Data(contentsOf:index(dir)),original); XCTAssertEqual(try Data(contentsOf:file),bad)
    }
    func testFailedUpgradeLeavesReadableLibraryAndCanRetryWithoutUserEdit() async throws {
        let (dir,doc) = try fixture(legacy:true)
        let store = FieldDataStore(directory:dir,loadImmediately:false)
        XCTAssertTrue(try store.publishLoad(store.loadSnapshot().prepare(deferTrackContents:true)))
        let logs = dir.appendingPathComponent(FieldDataDisk.logsName)
        try Data("blocked".utf8).write(to:logs)
        await store.upgradeTrackCacheIfNeeded()
        XCTAssertNil(store.loadError); XCTAssertEqual(store.document.trackFiles,doc.trackFiles)
        XCTAssertNotNil(try store.trackCacheUpgradeSnapshot())
        XCTAssertFalse(FileManager.default.fileExists(atPath:index(dir).path))
        try FileManager.default.removeItem(at:logs)
        await store.upgradeTrackCacheIfNeeded()
        XCTAssertTrue(store.document.trackFiles.isEmpty); XCTAssertNil(try store.trackCacheUpgradeSnapshot())
        XCTAssertEqual(try store.document.trackData(doc.tracks[0].id),doc.trackFiles[doc.tracks[0].id])
    }
    func testCancellationBeforeUpgradeCannotCreateIndexAndNextAttemptSucceeds() async throws {
        let (dir,doc) = try fixture(legacy:true)
        let store = FieldDataStore(directory:dir,loadImmediately:false)
        XCTAssertTrue(try store.publishLoad(store.loadSnapshot().prepare(deferTrackContents:true)))
        let task = Task { await store.upgradeTrackCacheIfNeeded() }; task.cancel(); await task.value
        XCTAssertFalse(FileManager.default.fileExists(atPath:index(dir).path))
        XCTAssertEqual(store.document.trackFiles,doc.trackFiles)
        await store.upgradeTrackCacheIfNeeded()
        XCTAssertTrue(store.document.trackFiles.isEmpty)
    }
}
