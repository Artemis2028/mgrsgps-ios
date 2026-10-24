import XCTest
@testable import GridFixCore

final class LibraryWorkflowTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func field(_ directory: URL) throws -> FieldDataStore {
        let store = FieldDataStore(directory: directory)
        var doc = Backup.Document(); doc.hasSettings = false
        doc.graphics = [.init(id: "g1",name: "Route",type: "route",points: [.init(lat: 1,lon: 1),.init(lat: 1.01,lon: 1)],folder: "Recon"),.init(id: "g2",name: "Hidden",type: "checkpoint",points: [.init(lat: 1,lon: 1)],folder: "Base",visible: false)]
        let (meta,bytes) = try TrackCodec.imported(name: "Patrol",points: [.init(lat: 1,lon: 1),.init(lat: 1.01,lon: 1)],now: 1000,folder: "Recon")
        doc.tracks = [meta]; doc.trackFiles[meta.id] = bytes
        _ = try store.restore(doc); return store
    }
    func testDistanceBucketsUseNameTiesAcrossFoldersAndKeepInsertionWithoutGPS() {
        let z = Waypoint(id: "z",name: "Zulu",lat: 0,lon: 0.00009,folder: "Recon")
        let a = Waypoint(id: "a",name: "Alpha",lat: 0,lon: 0.00018,folder: "Base")
        let near = Waypoint(id: "n",name: "Near",lat: 0,lon: 0.00027,folder: "Base")
        XCTAssertEqual(LibraryListing.waypoints([z,near,a],folder: nil,origin: nil).map(\.id),["z","n","a"])
        XCTAssertEqual(LibraryListing.waypoints([z,near,a],folder: nil,origin: .init(lat: 0,lon: 0)).map(\.id),["a","z","n"])
        XCTAssertEqual(LibraryListing.waypoints([z,near,a],folder: "BASE",origin: nil).map(\.id),["n","a"])
        XCTAssertEqual(LibraryListing.waypoints([z,near,a],folder: nil,origin: .init(lat: 0,lon: 0.000001)).map(\.id),["a","z","n"])
    }
    func testMixedWaypointVisibilitySwapsEachStateAndDeletionClearsOnlySelectedTarget() throws {
        let dir = try directory(), store = WaypointStore(directory: dir)
        let a = store.add(.init(name: "A",lat: 1,lon: 1)), b = store.add(.init(name: "B",lat: 1,lon: 2))
        store.setVisible(id: b.id,visible: false); store.select(a.id)
        try store.applyLibraryBatch(ids: [a.id,b.id],action: .swapVisibility)
        XCTAssertEqual(store.waypoints.map(\.visible),[false,true])
        try store.applyLibraryBatch(ids: [b.id],action: .delete); XCTAssertEqual(store.selectedId,a.id)
        try store.applyLibraryBatch(ids: [a.id],action: .delete); XCTAssertNil(store.selectedId)
        XCTAssertTrue(WaypointStore(directory: dir).waypoints.isEmpty)
    }
    func testFolderRenameMergesVisibilityAndPreservesOwnershipAndMetadata() throws {
        let dir = try directory(), store = WaypointStore(directory: dir)
        _ = try store.createLibraryFolder("Recon"); _ = try store.createLibraryFolder("Destination")
        store.setFolderVisible("Destination",visible: false)
        try store.replaceRouteWaypoints(routeID: "route",name: "Route",points: [.init(lat: 1,lon: 1),.init(lat: 2,lon: 2)],folder: "Recon")
        let ids = store.waypoints.map(\.id)
        XCTAssertEqual(try store.renameLibraryFolder(from: "Recon",to: "destination"),"Destination")
        XCTAssertEqual(store.waypoints.map(\.id),ids); XCTAssertTrue(store.waypoints.allSatisfy { $0.sourceRouteId == "route" && $0.folder == "Destination" })
        XCTAssertEqual(store.folders.first { $0.name == "Destination" }?.visible,true)
        XCTAssertFalse(store.folders.contains { $0.name == "Recon" })
        XCTAssertEqual(WaypointStore(directory: dir).waypoints,store.waypoints)
    }
    func testFolderKeepContentsAndDeleteContentsProtectBaseAndPersistEmptyFolders() throws {
        let dir = try directory(), store = WaypointStore(directory: dir)
        _ = try store.createLibraryFolder("Empty")
        XCTAssertTrue(WaypointStore(directory: dir).folders.contains { $0.name == "Empty" })
        let point = store.add(.init(name: "P",lat: 1,lon: 1,folder: "Recon")); store.select(point.id)
        try store.removeLibraryFolder("Recon",deleteContents: false)
        XCTAssertEqual(store.waypoints.first?.folder,"Base"); XCTAssertEqual(store.selectedId,point.id)
        try store.removeLibraryFolder("Base",deleteContents: true); XCTAssertEqual(store.waypoints.count,1)
        XCTAssertEqual(try store.renameLibraryFolder(from: "Base",to: "No"),"Base")
        _ = store.add(.init(name: "Q",lat: 1,lon: 1,folder: "Empty"))
        try store.removeLibraryFolder("Empty",deleteContents: true)
        XCTAssertEqual(store.waypoints.map(\.id),[point.id]); XCTAssertFalse(store.folders.contains { $0.name == "Empty" })
    }
    func testFailedWaypointBatchNeverPublishesAnUnsavedDeletion() throws {
        let dir = try directory(), store = WaypointStore(directory: dir)
        let point = store.add(.init(name: "P",lat: 1,lon: 1)); store.select(point.id)
        let path = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.applyLibraryBatch(ids: [point.id],action: .delete))
        XCTAssertEqual(store.waypoints.map(\.id),[point.id]); XCTAssertEqual(store.selectedId,point.id)
        XCTAssertThrowsError(try store.createLibraryFolder("Failed")); XCTAssertFalse(store.folders.contains { $0.name == "Failed" })
        XCTAssertThrowsError(try store.setLibraryFolderVisible("Base",visible: false))
        XCTAssertEqual(store.folders.first { $0.name == "Base" }?.visible,true)
    }
    func testFieldBatchSwapAndDeleteIncludeTrackLogsAndPersist() throws {
        let dir = try directory(), store = try field(dir), track = store.document.tracks[0]
        let bytes = store.document.trackFiles[track.id]
        try store.applyLibraryBatch(graphicIDs: ["g1","g2"],trackIDs: [track.id],action: .swapVisibility)
        XCTAssertEqual(store.document.graphics.map(\.visible),[false,true]); XCTAssertFalse(store.document.tracks[0].visible)
        XCTAssertEqual(store.document.trackFiles[track.id],bytes)
        try store.applyLibraryBatch(graphicIDs: ["g1"],trackIDs: [track.id],action: .delete)
        let reopened = FieldDataStore(directory: dir)
        XCTAssertEqual(reopened.document.graphics.map(\.id),["g2"]); XCTAssertTrue(reopened.document.tracks.isEmpty); XCTAssertNil(reopened.document.trackFiles[track.id])
    }
    func testFieldFolderMovesKeepLogsAndDeleteRemovesOnlyItsContents() throws {
        let dir = try directory(), store = try field(dir), track = store.document.tracks[0]
        let bytes = store.document.trackFiles[track.id]
        try store.changeLibraryFolder(from: "Recon",to: "Patrol")
        XCTAssertEqual(store.document.graphics[0].folder,"Patrol"); XCTAssertEqual(store.document.tracks[0].folder,"Patrol")
        try store.moveTrack(track.id,to: "Base"); XCTAssertEqual(store.document.trackFiles[track.id],bytes)
        try store.changeLibraryFolder(from: "Patrol",to: nil,deleteContents: true)
        XCTAssertEqual(store.document.graphics.map(\.id),["g2"]); XCTAssertEqual(store.document.tracks.count,1)
        try store.changeLibraryFolder(from: "Base",to: nil,deleteContents: true); XCTAssertEqual(store.document.tracks.count,1)
    }
    func testFailedFieldBatchDoesNotPublishOrLosePointBytes() throws {
        let dir = try directory(), store = try field(dir), before = store.document
        let path = dir.appendingPathComponent("field-data-v1.zip")
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.applyLibraryBatch(graphicIDs: ["g1"],trackIDs: Set(before.tracks.map(\.id)),action: .delete))
        XCTAssertEqual(store.document,before)
    }
    func testSelectionNamespacesDoNotCollideAndStaleIDsArePruned() {
        var selection = LibrarySelection(); selection.waypoints = ["same","gone"]; selection.graphics = ["same"]; selection.tracks = ["same"]
        XCTAssertEqual(selection.count,4)
        selection.retain(waypoints: ["same"],graphics: [],tracks: ["same"])
        XCTAssertEqual(selection.count,2); XCTAssertTrue(selection.graphics.isEmpty); XCTAssertEqual(selection.tracks,["same"])
    }
    func testPartialBatchRetryNeverSwapsCompletedWaypointsTwice() throws {
        let dir = try directory(), field = try field(dir), waypoints = WaypointStore(directory: dir)
        let point = waypoints.add(.init(name: "P",lat: 1,lon: 1))
        var selection = LibrarySelection(); selection.waypoints = [point.id]; selection.graphics = ["g1"]
        let path = dir.appendingPathComponent("field-data-v1.zip")
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        let partial = LibraryBatches.apply(selection,action: .swapVisibility,waypoints: waypoints,field: field)
        XCTAssertEqual(partial.completed,1); XCTAssertNotNil(partial.failure); XCTAssertTrue(partial.remaining.waypoints.isEmpty)
        XCTAssertEqual(partial.remaining.graphics,["g1"]); XCTAssertFalse(waypoints.waypoints[0].visible); XCTAssertTrue(field.document.graphics[0].visible)
        try FileManager.default.removeItem(at: path)
        let retried = LibraryBatches.apply(partial.remaining,action: .swapVisibility,waypoints: waypoints,field: field)
        XCTAssertNil(retried.failure); XCTAssertEqual(retried.completed,1)
        XCTAssertFalse(waypoints.waypoints[0].visible); XCTAssertFalse(field.document.graphics[0].visible)
    }
    func testFirstRepositoryFailureLeavesTheWholeSelectionRetryable() throws {
        let dir = try directory(), field = try field(dir), waypoints = WaypointStore(directory: dir)
        let point = waypoints.add(.init(name: "P",lat: 1,lon: 1))
        var selection = LibrarySelection(); selection.waypoints = [point.id]; selection.graphics = ["g1"]
        let path = dir.appendingPathComponent("waypoints-v1.json"), original = field.document
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        let result = LibraryBatches.apply(selection,action: .delete,waypoints: waypoints,field: field)
        XCTAssertEqual(result.completed,0); XCTAssertEqual(result.remaining,selection); XCTAssertNotNil(result.failure)
        XCTAssertEqual(field.document,original); XCTAssertEqual(waypoints.waypoints.map(\.id),[point.id])
    }
}
