import XCTest
@testable import GridFixCore

final class FieldWriteSourceTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:dir) }
        return dir
    }
    private func graphic(_ id: String) -> Backup.Graphic {
        .init(id:id,name:id,type:"checkpoint",points:[.init(lat:24,lon:54)])
    }
    func testOlderPreparedEditCannotOverwriteAnotherStoreCommit() throws {
        let dir = try directory(), older = FieldDataStore(directory:dir), newer = FieldDataStore(directory:dir)
        let edit = try older.restoreSnapshot().prepare(edit:.saveGraphic(graphic("older")))
        try newer.saveGraphic(graphic("newer"))
        let index = dir.appendingPathComponent(FieldDataDisk.indexName), bytes = try Data(contentsOf:index)
        XCTAssertThrowsError(try older.publishEdit(edit))
        XCTAssertEqual(try Data(contentsOf:index),bytes)
        XCTAssertTrue(older.document.graphics.isEmpty)
        XCTAssertEqual(FieldDataStore(directory:dir).document.graphics.map(\.id),["newer"])
    }
    func testStaleDirectAndPreparedRestoreKeepNewerIndexAndRemoveOnlyTheirOwnLogs() async throws {
        for prepared in [false,true] {
            let dir = try directory(), older = FieldDataStore(directory:dir), newer = FieldDataStore(directory:dir)
            let snapshot = try older.restoreSnapshot()
            let (meta,bytes) = try TrackCodec.imported(name:"Staged patrol",points:[.init(lat:24,lon:54)],now:1000)
            var incoming = Backup.Document(); incoming.hasSettings = false
            incoming.tracks = [meta]; incoming.trackFiles[meta.id] = bytes
            let staged = prepared ? try snapshot.prepare(incoming) : nil
            let (winnerMeta,winnerBytes) = try TrackCodec.imported(name:"Newer patrol",points:[.init(lat:25,lon:55)],now:2000)
            var winner = Backup.Document(); winner.hasSettings = false
            winner.graphics = [graphic("newer")]; winner.tracks = [winnerMeta]; winner.trackFiles[winnerMeta.id] = winnerBytes
            _ = try newer.restore(winner)
            let index = dir.appendingPathComponent(FieldDataDisk.indexName), saved = try Data(contentsOf:index)
            if let staged { XCTAssertThrowsError(try older.publishRestore(staged)) }
            else { XCTAssertThrowsError(try older.restore(incoming)) }
            XCTAssertEqual(try Data(contentsOf:index),saved)
            XCTAssertTrue(older.document.tracks.isEmpty)
            let logs = dir.appendingPathComponent(FieldDataDisk.logsName)
            let deadline = Date().addingTimeInterval(5)
            while ((try? FileManager.default.contentsOfDirectory(atPath:logs.path)) ?? []).count > 1,Date() < deadline { try await Task.sleep(nanoseconds:10_000_000) }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:logs.path).count,1)
            let reopened = FieldDataStore(directory:dir)
            XCTAssertNil(reopened.loadError); XCTAssertEqual(reopened.document.trackFiles[winnerMeta.id],winnerBytes)
            XCTAssertEqual(try reopened.restore(incoming).tracks,1)
            XCTAssertEqual(reopened.document.graphics.map(\.id),["newer"])
            XCTAssertEqual(FieldDataStore(directory:dir).document.trackFiles[meta.id],bytes)
            XCTAssertEqual(FieldDataStore(directory:dir).document.trackFiles[winnerMeta.id],winnerBytes)
        }
    }
    func testChangedLegacyArchiveCannotBeOverwrittenByPreparedMigration() throws {
        let dir = try directory(), legacy = dir.appendingPathComponent("field-data-v1.zip")
        var initial = Backup.Document(); initial.hasSettings = false; initial.graphics = [graphic("first")]
        try Backup.exportZip(initial).write(to:legacy)
        let older = FieldDataStore(directory:dir)
        let prepared = try older.restoreSnapshot().prepare(edit:.saveGraphic(graphic("stale edit")))
        initial.graphics = [graphic("replacement")]
        let replacement = try Backup.exportZip(initial)
        try replacement.write(to:legacy,options:.atomic)
        XCTAssertThrowsError(try older.publishEdit(prepared))
        XCTAssertEqual(try Data(contentsOf:legacy),replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath:dir.appendingPathComponent(FieldDataDisk.indexName).path))
        let reopened = FieldDataStore(directory:dir); try reopened.saveGraphic(graphic("fresh edit"))
        XCTAssertEqual(Set(FieldDataStore(directory:dir).document.graphics.map(\.id)),["replacement","fresh edit"])
    }
    func testConcurrentStorePublicationsHaveOneWinnerWithoutLostUpdate() async throws {
        let dir = try directory(), a = FieldDataStore(directory:dir), b = FieldDataStore(directory:dir)
        let first = try a.restoreSnapshot().prepare(edit:.saveGraphic(graphic("first")))
        let second = try b.restoreSnapshot().prepare(edit:.saveGraphic(graphic("second")))
        let successes = await withTaskGroup(of:Bool.self,returning:Int.self) { group in
            group.addTask { (try? a.publishEdit(first)) == true }
            group.addTask { (try? b.publishEdit(second)) == true }
            var count = 0
            for await success in group { if success { count += 1 } }
            return count
        }
        XCTAssertEqual(successes,1)
        let reopened = FieldDataStore(directory:dir)
        XCTAssertNil(reopened.loadError); XCTAssertEqual(reopened.document.graphics.count,1)
        XCTAssertTrue(["first","second"].contains(try XCTUnwrap(reopened.document.graphics.first?.id)))
    }
    func testDeletedIndexIsNotRecreatedFromAnOlderLiveStore() throws {
        let dir = try directory(), store = FieldDataStore(directory:dir)
        try store.saveGraphic(graphic("original"))
        let file = dir.appendingPathComponent(FieldDataDisk.indexName)
        try FileManager.default.removeItem(at:file)
        XCTAssertThrowsError(try store.saveGraphic(graphic("new")))
        XCTAssertEqual(store.document.graphics.map(\.id),["original"])
        XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
    }
}
