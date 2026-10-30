import XCTest
@testable import GridFixCore

@MainActor
final class FieldEditTests: XCTestCase {
    private func fixture() throws -> (URL,FieldDataStore,Backup.Graphic) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = FieldDataStore(directory: directory)
        let graphic = Backup.Graphic(id: "g",name: "Original",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],folder: "Patrol",createdAt: 100)
        var source = Backup.Document(); source.hasSettings = false
        source.graphics = [graphic,.init(id: "h",name: "Hidden",type: "checkpoint",points: [.init(lat: 24,lon: 54)],visible: false)]
        let (track,bytes) = try TrackCodec.imported(name: "Walk",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],now: 1000,folder: "Patrol")
        source.tracks = [track]; source.trackFiles[track.id] = bytes
        source.courseHistory = [.init(name: "Course",points: 1,started: 100,total: 1000,splits: [1000])]
        _ = try store.restore(source)
        return (directory,store,graphic)
    }
    private func prepare(_ edit: FieldDataStore.Edit,in store: FieldDataStore) async throws -> FieldDataStore.PreparedEdit {
        let snapshot = try store.restoreSnapshot()
        return try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return try snapshot.prepare(edit: edit)
        }.value
    }
    private func apply(_ edit: FieldDataStore.Edit,to store: FieldDataStore) async throws {
        let prepared = try await prepare(edit,in: store)
        XCTAssertTrue(try store.publishEdit(prepared))
    }

    func testPreparedEditIsInvisibleUntilAtomicPublicationAndKeepsTrackBytes() async throws {
        let (directory,store,_) = try fixture(), file = directory.appendingPathComponent("field-data-v2.json")
        let before = store.document, disk = try Data(contentsOf: file), id = before.tracks[0].id
        let prepared = try await prepare(.setTrackVisible(id,false),in: store)
        XCTAssertEqual(store.document,before); XCTAssertEqual(try Data(contentsOf: file),disk)
        XCTAssertTrue(try store.publishEdit(prepared))
        let reopened = FieldDataStore(directory: directory)
        XCTAssertFalse(reopened.document.tracks[0].visible)
        XCTAssertEqual(reopened.document.trackFiles,before.trackFiles)
        XCTAssertEqual(reopened.document.courseHistory,before.courseHistory)
    }
    func testStaleToggleDoesNotFlipAnythingUntilRebasedAndPublishedOnce() async throws {
        let (_,store,_) = try fixture()
        let edit = FieldDataStore.Edit.libraryBatch(graphicIDs: ["g","h"],trackIDs: [],action: .swapVisibility)
        let prepared = try await prepare(edit,in: store)
        try store.setTrackVisible(store.document.tracks[0].id,visible: false)
        XCTAssertFalse(try store.publishEdit(prepared))
        XCTAssertTrue(store.document.graphics[0].visible); XCTAssertFalse(store.document.graphics[1].visible)
        try await apply(edit,to: store)
        XCTAssertFalse(store.document.graphics[0].visible); XCTAssertTrue(store.document.graphics[1].visible)
        XCTAssertFalse(store.document.tracks[0].visible)
        XCTAssertFalse(try store.publishEdit(prepared))
        XCTAssertFalse(store.document.graphics[0].visible)
    }
    func testExplicitHideStaysHiddenAfterConcurrentHideAndRename() async throws {
        let (directory,store,original) = try fixture()
        let intent = FieldDataStore.Edit.setGraphicVisible(original.id,false)
        let prepared = try await prepare(intent,in: store)
        var current = original; current.visible = false; current.name = "Renamed elsewhere"
        try store.saveGraphic(current)
        XCTAssertFalse(try store.publishEdit(prepared))
        try await apply(intent,to: store)
        let saved = try XCTUnwrap(FieldDataStore(directory: directory).document.graphics.first { $0.id == original.id })
        XCTAssertFalse(saved.visible); XCTAssertEqual(saved.name,"Renamed elsewhere")
    }
    func testRebasedGraphicPatchKeepsUnchangedCurrentFieldsAndNewRecording() async throws {
        let (directory,store,original) = try fixture()
        var edited = original; edited.name = "Edited"
        let intent = FieldDataStore.Edit.editGraphic(original: original,updated: edited)
        let prepared = try await prepare(intent,in: store)
        var current = original; current.visible = false; current.folder = "Elsewhere"; current.points[1].lon = 54.02
        try store.saveGraphic(current)
        let (track,bytes) = try TrackCodec.imported(name: "New recording",points: [.init(lat: 25,lon: 54),.init(lat: 25.01,lon: 54)],now: 2000)
        var recording = Backup.Document(); recording.hasSettings = false; recording.tracks = [track]; recording.trackFiles[track.id] = bytes
        try store.saveRecordedTrack(recording)
        XCTAssertFalse(try store.publishEdit(prepared))
        try await apply(intent,to: store)
        let reopened = FieldDataStore(directory: directory), graphic = reopened.document.graphics[0]
        XCTAssertEqual(graphic.name,"Edited"); XCTAssertEqual(graphic.points,current.points)
        XCTAssertEqual(graphic.folder,"Elsewhere"); XCTAssertFalse(graphic.visible)
        XCTAssertEqual(reopened.document.tracks.count,2); XCTAssertEqual(reopened.document.trackFiles[track.id],bytes)
        XCTAssertEqual(reopened.document.courseHistory.count,1)
    }
    func testDeletedGraphicCannotBeResurrectedByAnEditedDraft() async throws {
        let (directory,store,original) = try fixture()
        var updated = original; updated.name = "Updated"
        let intent = FieldDataStore.Edit.editGraphic(original: original,updated: updated)
        let prepared = try await prepare(intent,in: store)
        try store.deleteGraphic(original.id)
        XCTAssertFalse(try store.publishEdit(prepared))
        do { _ = try await prepare(intent,in: store); XCTFail("Deleted graphic recreated") }
        catch { XCTAssertTrue(error.localizedDescription.contains("no longer saved")) }
        XCTAssertFalse(FieldDataStore(directory: directory).document.graphics.contains { $0.id == original.id })
    }
    func testCreateRetryKeepsExistingRecordAndDoesNotRewriteArchive() async throws {
        let (directory,store,original) = try fixture(), file = directory.appendingPathComponent("field-data-v2.json")
        let before = try Data(contentsOf: file)
        var changed = original; changed.name = "Must not overwrite"
        try await apply(.createGraphic(changed),to: store)
        XCTAssertEqual(store.document.graphics[0],original); XCTAssertEqual(try Data(contentsOf: file),before)
    }
    func testEditTokenCannotBeConsumedByAnotherStoreInstance() async throws {
        let (directory,store,_) = try fixture(), other = FieldDataStore(directory: directory)
        let prepared = try await prepare(.deleteGraphic("g"),in: store)
        XCTAssertThrowsError(try other.publishEdit(prepared))
        XCTAssertTrue(try store.publishEdit(prepared))
        XCTAssertFalse(FieldDataStore(directory: directory).document.graphics.contains { $0.id == "g" })
    }
    func testFailedReplacementKeepsMemoryAndCanPrepareAgain() async throws {
        let (directory,store,_) = try fixture(), file = directory.appendingPathComponent("field-data-v2.json")
        let before = store.document, disk = try Data(contentsOf: file)
        let prepared = try await prepare(.deleteGraphic("g"),in: store)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publishEdit(prepared)); XCTAssertEqual(store.document,before)
        var directoryFlag = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path,isDirectory: &directoryFlag)); XCTAssertTrue(directoryFlag.boolValue)
        try FileManager.default.removeItem(at: file); try disk.write(to: file)
        try await apply(.deleteGraphic("g"),to: store)
        XCTAssertFalse(FieldDataStore(directory: directory).document.graphics.contains { $0.id == "g" })
    }
    func testFolderMoveBatchAndDeleteKeepIndependentFlagsAndOnlyRemoveChosenLogs() async throws {
        let (_,store,_) = try fixture(), trackID = store.document.tracks[0].id
        try await apply(.changeLibraryFolder(from: "patrol",to: "Moved",deleteContents: false),to: store)
        XCTAssertEqual(store.document.graphics[0].folder,"Moved"); XCTAssertEqual(store.document.tracks[0].folder,"Moved")
        try await apply(.libraryBatch(graphicIDs: ["g","h"],trackIDs: [trackID],action: .swapVisibility),to: store)
        XCTAssertEqual(store.document.graphics.map(\.visible),[false,true]); XCTAssertFalse(store.document.tracks[0].visible)
        try await apply(.moveTrack(trackID,"Elsewhere"),to: store)
        try await apply(.changeLibraryFolder(from: "Moved",to: nil,deleteContents: true),to: store)
        XCTAssertEqual(store.document.graphics.map(\.id),["h"]); XCTAssertEqual(store.document.tracks.count,1)
        let before = store.document
        try await apply(.changeLibraryFolder(from: "BASE",to: nil,deleteContents: true),to: store)
        XCTAssertEqual(store.document,before)
        try await apply(.deleteTrack(trackID),to: store)
        XCTAssertTrue(store.document.trackFiles.isEmpty); XCTAssertTrue(store.document.tracks.isEmpty)
        XCTAssertEqual(store.document.courseHistory,before.courseHistory)
    }
    func testExactUnicodeRenameAndCreationDateArePreserved() async throws {
        let (_,store,initial) = try fixture()
        var original = initial; original.name = "é"; try store.saveGraphic(original)
        var updated = original; updated.name = "e\u{301}"; updated.createdAt = 0
        try await apply(.editGraphic(original: original,updated: updated),to: store)
        XCTAssertEqual(Array(store.document.graphics[0].name.utf8),Array(updated.name.utf8))
        XCTAssertEqual(store.document.graphics[0].createdAt,original.createdAt)
        XCTAssertNil(GraphicDraft(type: "route").original); XCTAssertEqual(GraphicDraft(original).original,original)
    }
    func testInvalidEditAndUnreadableStoreLeaveStoredBytesUntouched() async throws {
        let (directory,store,original) = try fixture(), file = directory.appendingPathComponent("field-data-v2.json")
        let before = try Data(contentsOf: file)
        var invalid = original; invalid.points[0].lat = .nan
        do { _ = try await prepare(.saveGraphic(invalid),in: store); XCTFail("Invalid graphic staged") } catch {}
        XCTAssertEqual(try Data(contentsOf: file),before)
        let broken = Data("unreadable archive".utf8); try broken.write(to: file)
        let unreadable = FieldDataStore(directory: directory)
        XCTAssertNotNil(unreadable.loadError); XCTAssertThrowsError(try unreadable.restoreSnapshot())
        XCTAssertEqual(try Data(contentsOf: file),broken)
    }
}
