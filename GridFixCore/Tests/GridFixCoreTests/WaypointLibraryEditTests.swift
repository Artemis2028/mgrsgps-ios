import XCTest
@testable import GridFixCore

final class WaypointLibraryEditTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    func testStagedOperationsMatchExistingFolderMergeAndSelectionPolicy() throws {
        let root = try directory(), legacyRoot = try directory()
        let store = WaypointStore(directory: root), legacy = WaypointStore(directory: legacyRoot)
        let point = Waypoint(id: "p",name: "Point",lat: 24,lon: 54,folder: "Patrol")
        for value in [store,legacy] { try value.restore(waypoints: [point],folders: []); value.select(point.id) }
        let edits: [WaypointStore.LibraryEdit] = [.favorite("p",true),.folderVisibility("patrol",false),.createFolder("Empty"),.renameFolder("Patrol","empty"),.removeFolder("Empty",false)]
        for edit in edits {
            let before = store.waypoints
            let prepared = try store.restoreSnapshot().prepareLibrary(edit)
            XCTAssertEqual(store.waypoints,before)
            XCTAssertEqual(WaypointStore(directory: root).waypoints,before)
            switch edit {
            case let .favorite(id,value): try legacy.setFavorite(id: id,favorite: value)
            case let .folderVisibility(name,value): try legacy.setLibraryFolderVisible(name,visible: value)
            case let .createFolder(name): _ = try legacy.createLibraryFolder(name)
            case let .renameFolder(from,to): _ = try legacy.renameLibraryFolder(from: from,to: to)
            case let .removeFolder(name,remove): try legacy.removeLibraryFolder(name,deleteContents: remove)
            }
            XCTAssertTrue(try store.publishLibraryEdit(prepared))
            XCTAssertEqual(store.waypoints,legacy.waypoints); XCTAssertEqual(store.folders,legacy.folders)
            XCTAssertEqual(store.selectedId,legacy.selectedId)
            XCTAssertEqual(WaypointStore(directory: root).waypoints,store.waypoints)
        }
    }
    func testConcurrentSelectionRejectsStagingAndRebasePreservesBothChanges() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let first = store.add(.init(name: "First",lat: 24,lon: 54)), second = store.add(.init(name: "Second",lat: 25,lon: 55))
        let edit = WaypointStore.LibraryEdit.favorite(first.id,true)
        let stale = try store.restoreSnapshot().prepareLibrary(edit)
        store.select(second.id)
        XCTAssertFalse(try store.publishLibraryEdit(stale)); XCTAssertFalse(store.waypoints[0].favorite)
        XCTAssertTrue(try store.publishLibraryEdit(store.restoreSnapshot().prepareLibrary(edit)))
        XCTAssertTrue(store.waypoints[0].favorite); XCTAssertEqual(store.selectedId,second.id)
        store.delete(ids: [first.id])
        XCTAssertThrowsError(try store.restoreSnapshot().prepareLibrary(edit))
    }
    func testBlockedPublicationAndWrongStoreCannotPublishMemory() throws {
        let root = try directory(), store = WaypointStore(directory: root)
        let point = store.add(.init(name: "Point",lat: 24,lon: 54))
        let edit = WaypointStore.LibraryEdit.favorite(point.id,true)
        let foreign = WaypointStore(directory: try directory())
        XCTAssertThrowsError(try foreign.publishLibraryEdit(store.restoreSnapshot().prepareLibrary(edit)))
        let file = root.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publishLibraryEdit(store.restoreSnapshot().prepareLibrary(edit)))
        XCTAssertFalse(store.waypoints[0].favorite)
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(try store.publishLibraryEdit(store.restoreSnapshot().prepareLibrary(edit)))
        XCTAssertTrue(WaypointStore(directory: root).waypoints[0].favorite)
    }
    func testUnreadableLibraryRefusesChangesAndRemovingFolderClearsOnlyItsTarget() throws {
        let root = try directory(), file = root.appendingPathComponent("waypoints-v1.json")
        let bytes = Data("broken-original".utf8); try bytes.write(to: file)
        let damaged = WaypointStore(directory: root)
        XCTAssertThrowsError(try damaged.restoreSnapshot().prepareLibrary(.createFolder("New")))
        XCTAssertEqual(try Data(contentsOf: file),bytes)
        let store = WaypointStore(directory: try directory())
        let point = store.add(.init(name: "Point",lat: 24,lon: 54,folder: "Patrol")); store.select(point.id)
        XCTAssertThrowsError(try store.restoreSnapshot().prepareLibrary(.removeFolder("Base",true)))
        XCTAssertTrue(try store.publishLibraryEdit(store.restoreSnapshot().prepareLibrary(.removeFolder("Patrol",true))))
        XCTAssertTrue(store.waypoints.isEmpty); XCTAssertNil(store.selectedId)
    }
}
