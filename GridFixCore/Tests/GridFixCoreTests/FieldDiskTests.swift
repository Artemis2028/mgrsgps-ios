import XCTest
@testable import GridFixCore

final class FieldDiskTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    private func track() throws -> Backup.Document {
        let (meta,bytes) = try TrackCodec.imported(name: "Saved patrol",points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54,time: 2000)],now: 1000)
        var document = Backup.Document(); document.hasSettings = false
        document.tracks = [meta]; document.trackFiles[meta.id] = bytes
        return document
    }
    private func reference(_ dir: URL,_ id: String) throws -> URL {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(FieldDataDisk.indexName))) as? [String: Any])
        let logs = try XCTUnwrap(json["logs"] as? [String: [String: String]])
        return dir.appendingPathComponent(FieldDataDisk.logsName).appendingPathComponent(try XCTUnwrap(logs[id]?["name"]))
    }
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(5)
        while !condition(), Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition())
    }
    func testLegacyMigrationKeepsOriginalUntilWholeIndexCommitsAndReopensEverything() async throws {
        let dir = try directory(), old = dir.appendingPathComponent("field-data-v1.zip")
        var original = try track()
        let graphic = Backup.Graphic(id: "route",name: "Patrol",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 25,lon: 54)])
        original.graphics = [graphic]; original.courseHistory = [.init(name: "Drill",points: 2,started: 100,total: 200,splits: [100,100])]
        let bytes = try Backup.exportZip(original); try bytes.write(to: old)
        let store = FieldDataStore(directory: dir), snapshot = try store.restoreSnapshot()
        var changed = graphic; changed.name = "Changed patrol"
        let edit = FieldDataStore.Edit.saveGraphic(changed)
        let prepared = try await Task.detached { XCTAssertFalse(Thread.isMainThread); return try snapshot.prepare(edit: edit) }.value
        XCTAssertEqual(try Data(contentsOf: old),bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(FieldDataDisk.indexName).path))
        XCTAssertEqual(FieldDataStore(directory: dir).document.graphics[0].name,"Patrol")
        XCTAssertTrue(try store.publishEdit(prepared))
        let loaded = FieldDataStore(directory: dir)
        XCTAssertNil(loaded.loadError); XCTAssertEqual(loaded.document.graphics[0].name,"Changed patrol")
        XCTAssertEqual(loaded.document.trackFiles,original.trackFiles); XCTAssertEqual(loaded.document.courseHistory,original.courseHistory)
        XCTAssertEqual(try Data(contentsOf: old),bytes)
    }
    func testFailedMigrationDoesNotPublishPartialRecordsAndCanRetry() async throws {
        let dir = try directory(), old = dir.appendingPathComponent("field-data-v1.zip"), original = try track()
        let bytes = try Backup.exportZip(original); try bytes.write(to: old)
        let store = FieldDataStore(directory: dir), marker = dir.appendingPathComponent(FieldDataDisk.indexName)
        try FileManager.default.createDirectory(at: marker,withIntermediateDirectories: false)
        let edit = FieldDataStore.Edit.saveGraphic(.init(id: "new",name: "New",type: "checkpoint",points: [.init(lat: 24,lon: 54)]))
        let prepared = try store.restoreSnapshot().prepare(edit: edit)
        XCTAssertThrowsError(try store.publishEdit(prepared))
        XCTAssertTrue(store.document.graphics.isEmpty); XCTAssertEqual(try Data(contentsOf: old),bytes)
        let logs = dir.appendingPathComponent(FieldDataDisk.logsName)
        try await wait { ((try? FileManager.default.contentsOfDirectory(atPath: logs.path)) ?? []).isEmpty }
        try FileManager.default.removeItem(at: marker)
        XCTAssertTrue(try store.publishEdit(store.restoreSnapshot().prepare(edit: edit)))
        XCTAssertEqual(FieldDataStore(directory: dir).document.tracks.map(\.id),original.tracks.map(\.id))
        XCTAssertEqual(FieldDataStore(directory: dir).document.graphics.map(\.id),["new"])
    }
    func testCorruptIndexNeverFallsBackToLegacyAndCannotBeOverwritten() throws {
        let dir = try directory(), input = try track()
        try Backup.exportZip(input).write(to: dir.appendingPathComponent("field-data-v1.zip"))
        let store = FieldDataStore(directory: dir)
        try store.setTrackVisible(input.tracks[0].id,visible: false)
        let marker = dir.appendingPathComponent(FieldDataDisk.indexName), broken = Data("SYNTHETIC damaged new index".utf8)
        try broken.write(to: marker)
        let damaged = FieldDataStore(directory: dir)
        XCTAssertNotNil(damaged.loadError); XCTAssertTrue(damaged.document.tracks.isEmpty)
        XCTAssertThrowsError(try damaged.restore(input)); XCTAssertEqual(try Data(contentsOf: marker),broken)
    }
    func testChecksumFailureAndMissingLogPreserveIndexAndRefuseWrites() throws {
        let dir = try directory(), input = try track(), store = FieldDataStore(directory: dir)
        _ = try store.restore(input)
        let path = try reference(dir,input.tracks[0].id), original = try Data(contentsOf: path)
        let marker = dir.appendingPathComponent(FieldDataDisk.indexName), index = try Data(contentsOf: marker)
        try Data("25 55 1000 -32768\n".utf8).write(to: path)
        var broken = FieldDataStore(directory: dir)
        XCTAssertNotNil(broken.loadError); XCTAssertThrowsError(try broken.restore(input))
        XCTAssertEqual(try Data(contentsOf: marker),index)
        try original.write(to: path); try FileManager.default.removeItem(at: path)
        broken = FieldDataStore(directory: dir)
        XCTAssertNotNil(broken.loadError); XCTAssertThrowsError(try broken.restoreSnapshot())
        XCTAssertEqual(try Data(contentsOf: marker),index)
    }
    func testMetadataChangesReuseLogAndDeleteRestoreGetsNewImmutableFilename() async throws {
        let dir = try directory(), input = try track(), store = FieldDataStore(directory: dir), id = input.tracks[0].id
        _ = try store.restore(input); let old = try reference(dir,id), before = try Data(contentsOf: old)
        let inode = try FileManager.default.attributesOfItem(atPath: old.path)[.systemFileNumber] as? NSNumber
        try store.setTrackVisible(id,visible: false); try store.moveTrack(id,to: "Patrol")
        XCTAssertEqual(try reference(dir,id),old)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: old.path)[.systemFileNumber] as? NSNumber,inode)
        XCTAssertEqual(try Data(contentsOf: old),before)
        try store.deleteTrack(id); _ = try store.restore(input)
        let replacement = try reference(dir,id); XCTAssertNotEqual(replacement,old)
        try await wait { !FileManager.default.fileExists(atPath: old.path) }
        XCTAssertEqual(try Data(contentsOf: replacement),before)
        XCTAssertEqual(FieldDataStore(directory: dir).document.trackFiles[id],before)
    }
    func testLocalLibraryCanExceedZipEntryCountWhileBackupRemainsBounded() throws {
        let dir = try directory(), store = FieldDataStore(directory: dir), bytes = try TrackCodec.encode([.init(lat: 24,lon: 54)])
        var input = Backup.Document(); input.hasSettings = false
        for i in 0..<513 {
            let id = UUID().uuidString.lowercased()
            input.tracks.append(.init(id: id,name: "T\(i)",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: 1)); input.trackFiles[id] = bytes
        }
        XCTAssertEqual(try store.restore(input).tracks,513)
        let loaded = FieldDataStore(directory: dir)
        XCTAssertNil(loaded.loadError); XCTAssertEqual(loaded.document.tracks.count,513)
        XCTAssertThrowsError(try Backup.exportZip(loaded.document))
        try store.setTrackVisible(input.tracks[0].id,visible: false)
        XCTAssertFalse(FieldDataStore(directory: dir).document.tracks[0].visible)
    }
    func testFinishedLogsCanExceedCombinedPointAndByteCapsThenStillEditAndReopen() throws {
        let dir = try directory(), store = FieldDataStore(directory: dir)
        let bytes = Data(String(repeating: "24.4539000 54.3773000 1700000000000 12345.678901\n",count: 250_000).utf8)
        XCTAssertLessThan(bytes.count,ZipArchive.entryLimit); XCTAssertGreaterThan(bytes.count*3,ZipArchive.totalLimit)
        for i in 0..<3 {
            let id = UUID().uuidString.lowercased()
            var recording = Backup.Document(); recording.hasSettings = false
            recording.tracks = [.init(id: id,name: "Long patrol \(i)",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: 250_000)]
            recording.trackFiles[id] = bytes
            try store.saveRecordedTrack(recording)
        }
        XCTAssertEqual(store.document.tracks.count,3)
        let id = store.document.tracks[0].id; try store.moveTrack(id,to: "Long patrols")
        let loaded = FieldDataStore(directory: dir)
        XCTAssertNil(loaded.loadError); XCTAssertEqual(loaded.document.tracks.reduce(0) { $0+$1.pointCount },750_000)
        XCTAssertEqual(loaded.document.tracks[0].folder,"Long patrols")
        XCTAssertThrowsError(try Backup.exportZip(loaded.document),"Local storage does not silently enlarge the external backup contract")
        var selected = loaded.document; selected.tracks = [loaded.document.tracks[0]]; selected.trackFiles = [id: bytes]
        XCTAssertFalse(try Backup.exportZip(selected).isEmpty)
    }
    func testExclusivePreparedFileNeverOverwritesExistingLog() throws {
        let dir = try directory(), path = dir.appendingPathComponent("log.txt"), old = Data("original".utf8)
        try old.write(to: path)
        let file = try PreparedAtomicFile(data: Data("replacement".utf8),destination: path,synchronize: true)
        XCTAssertThrowsError(try file.publish(replacing: false)); XCTAssertEqual(try Data(contentsOf: path),old)
    }
    func testMalformedFinishedRecordingCannotPublishThroughDirectOrPreparedSaveAndCanRetry() throws {
        for prepared in [false,true] {
            let dir = try directory(), original = try track(), store = FieldDataStore(directory:dir)
            _ = try store.restore(original)
            let marker = dir.appendingPathComponent(FieldDataDisk.indexName)
            let index = try Data(contentsOf:marker), existing = try reference(dir,original.tracks[0].id)
            let existingBytes = try Data(contentsOf:existing)
            let id = UUID().uuidString.lowercased()
            let valid = Data(String(repeating:"24 54 0\n",count:250_001).utf8)
            var recording = Backup.Document(); recording.hasSettings = false
            recording.tracks = [.init(id:id,name:"Recovered",startedAt:0,endedAt:1,distanceM:0,pointCount:250_001)]
            recording.trackFiles[id] = valid + Data("91 54 0\n".utf8)
            if prepared { XCTAssertThrowsError(try store.restoreSnapshot().prepare(edit:.saveRecordedTrack(recording))) }
            else { XCTAssertThrowsError(try store.saveRecordedTrack(recording)) }
            XCTAssertEqual(try Data(contentsOf:marker),index)
            XCTAssertEqual(try Data(contentsOf:existing),existingBytes)
            XCTAssertEqual(store.document.tracks.map(\.id),original.tracks.map(\.id))
            recording.trackFiles[id] = valid
            if prepared { XCTAssertTrue(try store.publishEdit(store.restoreSnapshot().prepare(edit:.saveRecordedTrack(recording)))) }
            else { try store.saveRecordedTrack(recording) }
            // A durable save retried after journal-cleanup interruption is a no-op.
            try store.saveRecordedTrack(recording)
            let reopened = FieldDataStore(directory:dir)
            XCTAssertNil(reopened.loadError)
            XCTAssertEqual(reopened.document.tracks.filter { $0.id == id }.count,1)
            XCTAssertEqual(reopened.document.trackFiles[id],valid)
            XCTAssertEqual(reopened.document.tracks.first { $0.id == id }?.pointCount,250_001)
        }
    }
}
