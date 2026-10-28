import XCTest
@testable import GridFixCore

final class SavedTrackLoadingTests: XCTestCase {
    private func fixture() throws -> (URL,Backup.Document,[String:URL]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        var doc = Backup.Document(); doc.hasSettings = false
        for n in 0..<2 {
            let (meta,bytes) = try TrackCodec.imported(name:"CAFÉ patrol \(n)",points:[.init(lat:24,lon:54+Double(n)),.init(lat:24.001,lon:54+Double(n),time:2000)],now:1000,folder:"Base")
            doc.tracks.append(meta); doc.trackFiles[meta.id] = bytes
        }
        _ = try FieldDataStore(directory:root).restore(doc)
        let index = root.appendingPathComponent(FieldDataDisk.indexName)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:index)) as? [String:Any])
        let logs = try XCTUnwrap(json["logs"] as? [String:[String:Any]])
        var files: [String:URL] = [:]
        for (id,ref) in logs { files[id] = root.appendingPathComponent(FieldDataDisk.logsName).appendingPathComponent(try XCTUnwrap(ref["name"] as? String)) }
        return (index,doc,files)
    }
    private func lazyStore(_ index: URL) throws -> FieldDataStore {
        let store = FieldDataStore(directory:index.deletingLastPathComponent(),loadImmediately:false)
        XCTAssertTrue(try store.publishLoad(store.loadSnapshot().prepare(deferTrackContents:true)))
        return store
    }
    func testMetadataLoadReadsNoPointBytesAndRequestedTrackKeepsExactContents() throws {
        let (index,original,_) = try fixture(), before = try Data(contentsOf:index)
        var reads = 0, parses = 0
        let (doc,_) = try FieldDataDisk.read(index,deferTrackContents:true,readContents:{ source in reads += 1; return try source.read() },summarize:{ bytes in parses += 1; return try TrackCodec.summarizeLocal(bytes) })
        XCTAssertEqual(reads,0); XCTAssertEqual(parses,0)
        XCTAssertTrue(doc.trackFiles.isEmpty); XCTAssertEqual(doc.localTrackFiles.count,2)
        XCTAssertEqual(doc.tracks,original.tracks)
        let id = original.tracks[0].id
        XCTAssertEqual(try doc.trackData(id),original.trackFiles[id])
        let deferredMap = try FieldMapGeometry.prepareOverlay(document:doc,folders:[])
        let eagerMap = try FieldMapGeometry.prepareOverlay(document:original,folders:[])
        XCTAssertEqual(deferredMap.tracks,2); XCTAssertEqual(deferredMap.points,eagerMap.points)
        XCTAssertEqual(try JSONSerialization.jsonObject(with:deferredMap.data) as? NSDictionary,
                       try JSONSerialization.jsonObject(with:eagerMap.data) as? NSDictionary)
        XCTAssertEqual(try Data(contentsOf:index),before)
    }
    func testLegacyReferenceAloneIsStrictlyReadWithoutRewritingIndex() throws {
        let (index,original,_) = try fixture(), id = original.tracks[0].id
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:index)) as? [String:Any])
        var logs = try XCTUnwrap(json["logs"] as? [String:[String:Any]])
        logs[id]?.removeValue(forKey:"summary"); json["logs"] = logs
        let before = try JSONSerialization.data(withJSONObject:json); try before.write(to:index)
        var reads = 0
        let (doc,refs) = try FieldDataDisk.read(index,deferTrackContents:true,readContents:{ source in reads += 1; return try source.read() })
        XCTAssertEqual(reads,1); XCTAssertEqual(doc.trackFiles[id],original.trackFiles[id])
        XCTAssertEqual(doc.localTrackFiles.count,1); XCTAssertNotNil(refs[id]?.summary)
        XCTAssertEqual(try Data(contentsOf:index),before)
    }
    func testMissingFileBeforeStartupStillRefusesWritesAndKeepsIndex() throws {
        let (index,original,files) = try fixture(), before = try Data(contentsOf:index)
        try FileManager.default.removeItem(at:try XCTUnwrap(files[original.tracks[0].id]))
        let store = try lazyStore(index)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.setTrackVisible(original.tracks[0].id,visible:false))
        XCTAssertThrowsError(try store.backup(waypoints:[],folders:[],settings:.init()))
        XCTAssertEqual(try Data(contentsOf:index),before)
    }
    func testDeletedSourceAfterStartupCannotBecomeEmptyTrackOrBackup() throws {
        let (index,original,files) = try fixture(), store = try lazyStore(index), id = original.tracks[0].id
        let before = try Data(contentsOf:index)
        try FileManager.default.removeItem(at:try XCTUnwrap(files[id]))
        // Snapshot capture itself is metadata-only; the worker detects the loss.
        let read = try store.trackReadSnapshot(id)
        XCTAssertThrowsError(try read.readBytes()); XCTAssertThrowsError(try store.points(for:id))
        XCTAssertThrowsError(try Backup.exportZip(store.document))
        XCTAssertEqual(try Data(contentsOf:index),before)
    }
    func testFirstUseVerifiesChecksumEvenWhenMetadataStartupSucceeds() throws {
        let (index,original,files) = try fixture(), id = original.tracks[0].id
        let file = try XCTUnwrap(files[id]), before = try Data(contentsOf:index)
        let changed = Data("25 55 0\n25.001 55 2000\n".utf8)
        try changed.write(to:file,options:.atomic)
        let store = try lazyStore(index)
        XCTAssertNil(store.loadError); XCTAssertTrue(store.document.trackFiles.isEmpty)
        XCTAssertThrowsError(try store.trackReadSnapshot(id).readBytes()) { XCTAssertTrue($0.localizedDescription.contains("checksum")) }
        XCTAssertThrowsError(try Backup.exportZip(store.document))
        XCTAssertEqual(try Data(contentsOf:index),before); XCTAssertEqual(try Data(contentsOf:file),changed)
    }
    func testMetadataEditRetainsImmutableSourcesAndRejectsChangedSourceBeforeStaging() throws {
        let (index,original,files) = try fixture(), store = try lazyStore(index), id = original.tracks[0].id
        let file = try XCTUnwrap(files[id]), bytes = try Data(contentsOf:file)
        let stamp = try FieldDataReadSource.Stamp.read(file)
        try store.moveTrack(id,to:"Patrols")
        XCTAssertTrue(store.document.trackFiles.isEmpty); XCTAssertEqual(store.document.localTrackFiles.count,2)
        XCTAssertEqual(try FieldDataReadSource.Stamp.read(file),stamp); XCTAssertEqual(try Data(contentsOf:file),bytes)
        let saved = try Data(contentsOf:index), snapshot = try store.restoreSnapshot()
        try Data("changed".utf8).write(to:file,options:.atomic)
        XCTAssertThrowsError(try snapshot.prepare(edit:.setTrackVisible(id,false)))
        XCTAssertEqual(try Data(contentsOf:index),saved)
    }
    func testDeferredBackupMaterializesEveryTrackAndContainsNoLocalSourcePaths() throws {
        let (index,original,_) = try fixture(), store = try lazyStore(index)
        let bytes = try Backup.exportZip(store.backup(waypoints:[],folders:[],settings:.init()))
        let restored = try Backup.importZip(bytes)
        XCTAssertEqual(restored.tracks,original.tracks); XCTAssertEqual(restored.trackFiles,original.trackFiles)
        XCTAssertTrue(restored.localTrackFiles.isEmpty)
        let manifest = try Backup.encodeManifest(store.document)
        XCTAssertFalse(String(decoding:manifest,as:UTF8.self).contains(index.deletingLastPathComponent().path))
        XCTAssertFalse(String(decoding:manifest,as:UTF8.self).contains("localTrackFiles"))
    }
    func testHiddenTrackDoesNotReadBrokenBytesAndWatchCountsOmissionOnVisibleFailure() throws {
        let (index,_,files) = try fixture(), store = try lazyStore(index)
        for file in files.values { try Data("broken".utf8).write(to:file,options:.atomic) }
        let folders = [FolderInfo(name:"Base",visible:false)]
        XCTAssertEqual(try FieldMapGeometry.prepareOverlay(document:store.document,folders:folders).tracks,0)
        XCTAssertThrowsError(try FieldMapGeometry.prepareOverlay(document:store.document,folders:[]))
        let watch = WatchMapSnapshot.build(waypoints:[],folders:[],document:store.document)
        XCTAssertTrue(watch.features.isEmpty); XCTAssertEqual(watch.omittedItems,2)
    }
    func testVerifiedReadOwnsBytesAfterAnInPlaceFileMutationAndSizeLimitPreflights() throws {
        let (index,original,files) = try fixture(), store = try lazyStore(index), id = original.tracks[0].id
        let source = try XCTUnwrap(store.document.localTrackFiles[id]), file = try XCTUnwrap(files[id])
        XCTAssertThrowsError(try source.read(maximumBytes:-1))
        XCTAssertThrowsError(try source.read(maximumBytes:0))
        let snapshot = try source.read()
        var changed = snapshot; changed[0] = 51
        let handle = try FileHandle(forWritingTo:file); try handle.write(contentsOf:changed); try handle.synchronize(); try handle.close()
        XCTAssertEqual(snapshot,original.trackFiles[id])
        XCTAssertThrowsError(try source.read())
    }
    func testDeletingDeferredTrackRemovesItsReferenceAndRetainsOtherTrack() throws {
        let (index,original,_) = try fixture(), store = try lazyStore(index), id = original.tracks[0].id
        try store.deleteTrack(id)
        XCTAssertNil(store.document.localTrackFiles[id]); XCTAssertEqual(store.document.tracks.count,1)
        let remaining = original.tracks[1].id
        XCTAssertEqual(try store.trackReadSnapshot(remaining).readBytes(),original.trackFiles[remaining])
        let reopened = try lazyStore(index)
        XCTAssertNil(reopened.loadError); XCTAssertEqual(reopened.document.tracks.map(\.id),[remaining])
    }
    private func orphan(_ index: URL) throws -> URL {
        let file = index.deletingLastPathComponent().appendingPathComponent(FieldDataDisk.logsName).appendingPathComponent(UUID().uuidString.lowercased()+".txt")
        try Data("recoverable abandoned bytes".utf8).write(to:file)
        try FileManager.default.setAttributes([.modificationDate:Date.distantPast],ofItemAtPath:file.path)
        return file
    }
    func testUnreadAndPartiallyReadLibrariesGrantNoCleanupAuthorityUntilAllSourcesVerify() throws {
        let (index,original,_) = try fixture(), store = try lazyStore(index), old = try orphan(index)
        let maintenance = try XCTUnwrap(store.trackMaintenanceSnapshot())
        XCTAssertEqual(try maintenance.prune(),0); XCTAssertTrue(FileManager.default.fileExists(atPath:old.path))
        _ = try store.trackReadSnapshot(original.tracks[0].id).readBytes()
        XCTAssertEqual(try maintenance.prune(),0); XCTAssertTrue(FileManager.default.fileExists(atPath:old.path))
        _ = try store.trackReadSnapshot(original.tracks[1].id).readBytes()
        XCTAssertEqual(try maintenance.prune(),1); XCTAssertFalse(FileManager.default.fileExists(atPath:old.path))
        XCTAssertEqual(store.document.tracks,original.tracks)
    }
    func testCorruptDeferredLogPreservesUnreferencedRecoveryFiles() throws {
        let (index,original,files) = try fixture(), old = try orphan(index), id = original.tracks[0].id
        try Data("corrupt indexed bytes".utf8).write(to:try XCTUnwrap(files[id]),options:.atomic)
        let store = try lazyStore(index), before = try Data(contentsOf:index)
        XCTAssertNil(store.loadError)
        XCTAssertThrowsError(try store.trackReadSnapshot(id).readBytes())
        XCTAssertEqual(try XCTUnwrap(store.trackMaintenanceSnapshot()).prune(),0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:old.path)); XCTAssertEqual(try Data(contentsOf:index),before)
    }
    func testPreviouslyVerifiedSourceChangeCannotAuthorizeCleanup() throws {
        let (index,original,files) = try fixture(), store = try lazyStore(index), old = try orphan(index)
        for track in original.tracks { _ = try store.trackReadSnapshot(track.id).readBytes() }
        let maintenance = try XCTUnwrap(store.trackMaintenanceSnapshot()), id = original.tracks[0].id
        try Data("changed indexed bytes".utf8).write(to:try XCTUnwrap(files[id]),options:.atomic)
        XCTAssertThrowsError(try maintenance.prune())
        XCTAssertTrue(FileManager.default.fileExists(atPath:old.path))
        XCTAssertThrowsError(try store.trackReadSnapshot(id).readBytes())
        XCTAssertEqual(try maintenance.prune(),0,"A failed read revokes its shared verification receipt")
        XCTAssertTrue(FileManager.default.fileExists(atPath:old.path))
    }
}
