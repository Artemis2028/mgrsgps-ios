import XCTest
@testable import GridFixCore

final class WaypointEditTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private func draft(_ point: Waypoint) -> WaypointDraft {
        .init(name: point.name,lat: point.lat,lon: point.lon,folder: point.folder,symbol: point.symbol,affiliation: point.affiliation,
              echelon: point.echelon,designation: point.designation,kind: point.kind,rotation: point.rotation,metadata: point.metadata)
    }
    func testCreateStagesWithoutPublicationAndRetryKeepsIdentitySelectionAndFolderEye() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let selected = store.add(.init(name: "Selected",lat: 24,lon: 54)); store.select(selected.id)
        store.setFolderVisible("Patrol",visible: false)
        let edit = WaypointStore.Edit.create(id: "stable",createdAt: 123,draft: .init(name: "New",lat: 24.1,lon: 54.1,folder: "patrol"))
        let prepared = try store.restoreSnapshot().prepare(edit: edit)
        XCTAssertEqual(store.waypoints.count,1); XCTAssertEqual(WaypointStore(directory: root).waypoints.count,1)
        let saved = try XCTUnwrap(store.publishEdit(prepared))
        XCTAssertEqual(saved.id,"stable"); XCTAssertEqual(saved.createdAt,123); XCTAssertEqual(saved.folder,"Patrol")
        XCTAssertEqual(store.selectedId,selected.id); XCTAssertFalse(try XCTUnwrap(store.folders.first { $0.name == "Patrol" }).visible)
        let retry = try store.restoreSnapshot().prepare(edit: edit)
        XCTAssertEqual(try store.publishEdit(retry)?.id,"stable"); XCTAssertEqual(store.waypoints.count,2)
        XCTAssertEqual(WaypointStore(directory: root).waypoints,store.waypoints)
    }
    func testFailedPublicationKeepsMemoryAndRetryDoesNotDuplicate() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let original = store.add(.init(name: "Original",lat: 24,lon: 54))
        let file = root.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        let edit = WaypointStore.Edit.create(id: "retry",createdAt: 1,draft: .init(name: "Draft",lat: 24.1,lon: 54.1))
        let prepared = try store.restoreSnapshot().prepare(edit: edit)
        XCTAssertThrowsError(try store.publishEdit(prepared)); XCTAssertEqual(store.waypoints,[original])
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(try store.publishEdit(store.restoreSnapshot().prepare(edit: edit))?.id,"retry")
        XCTAssertEqual(WaypointStore(directory: root).waypoints.count,2)
    }
    func testRebasePreservesConcurrentFieldsAndDoesNotResurrectDeletedPoint() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let original = store.add(.init(name: "Original",lat: 24,lon: 54,metadata: .init(color: "red",timestampMillis: 1)))
        var rename = draft(original); rename.name = "Renamed"
        let edit = WaypointStore.Edit.update(original: original,draft: rename)
        let stale = try store.restoreSnapshot().prepare(edit: edit)
        var moved = draft(original); moved.lat = 25; moved.folder = "Moved"; moved.metadata?.timestampMillis = 2
        store.update(id: original.id,draft: moved); store.setVisible(id: original.id,visible: false)
        try store.setFavorite(id: original.id,favorite: true)
        XCTAssertNil(try store.publishEdit(stale))
        let saved = try XCTUnwrap(store.publishEdit(store.restoreSnapshot().prepare(edit: edit)))
        XCTAssertEqual(saved.name,"Renamed"); XCTAssertEqual(saved.lat,25); XCTAssertEqual(saved.folder,"Moved")
        XCTAssertFalse(saved.visible); XCTAssertTrue(saved.favorite); XCTAssertEqual(saved.metadata.timestampMillis,2)
        store.delete(ids: [original.id])
        XCTAssertThrowsError(try store.restoreSnapshot().prepare(edit: edit)); XCTAssertTrue(store.waypoints.isEmpty)
    }
    func testExactUnicodeEditInvalidDraftAndWrongStoreCannotPublish() throws {
        let a = WaypointStore(directory: try directory()), b = WaypointStore(directory: try directory())
        let original = a.add(.init(name: "CAFÉ",lat: 24,lon: 54))
        var changed = draft(original); changed.name = "CAFE\u{301}"
        let prepared = try a.restoreSnapshot().prepare(edit: .update(original: original,draft: changed))
        XCTAssertThrowsError(try b.publishEdit(prepared))
        let saved = try XCTUnwrap(a.publishEdit(prepared))
        XCTAssertTrue(saved.name.utf8.elementsEqual(changed.name.utf8))
        changed.lat = .nan
        XCTAssertThrowsError(try a.restoreSnapshot().prepare(edit: .update(original: saved,draft: changed)))
    }
    func testUnreadableLibraryIsNotOverwrittenBySaveRestoreOrLegacyMutation() throws {
        let root = try directory(), file = root.appendingPathComponent("waypoints-v1.json")
        let bytes = Data("unreadable original library".utf8); try bytes.write(to: file)
        let store = WaypointStore(directory: root)
        XCTAssertNotNil(store.loadError)
        let edit = WaypointStore.Edit.create(id: "safe",createdAt: 1,draft: .init(name: "New",lat: 24,lon: 54))
        XCTAssertThrowsError(try store.restoreSnapshot().prepare(edit: edit))
        XCTAssertThrowsError(try store.restore(waypoints: [],folders: []))
        _ = store.add(.init(name: "Legacy",lat: 24,lon: 54))
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }

    func testFirstEditorPointBecomesTargetUnlessPracticeOwnsSelection() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let first = WaypointStore.Edit.create(id: "first",createdAt: 1,draft: .init(name: "First",lat: 24,lon: 54))
        _ = try store.publishEdit(store.restoreSnapshot().prepare(edit: first))
        XCTAssertEqual(store.selectedId,"first"); XCTAssertEqual(WaypointStore(directory: root).selectedId,"first")
        let locked = WaypointStore(directory: try directory())
        try locked.setPracticeNavigationTarget(nil,locked: true)
        _ = try locked.publishEdit(locked.restoreSnapshot().prepare(edit: first))
        XCTAssertNil(locked.selectedId)
    }

}
