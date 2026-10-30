import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class WatchMapBridgeIntegrationTests: XCTestCase {
    private func stores() throws -> (WaypointStore,FieldDataStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (WaypointStore(directory: directory),FieldDataStore(directory: directory))
    }
    private func snapshot(_ waypoints: WaypointStore,_ field: FieldDataStore) throws -> WatchMapSnapshot {
        let result = WatchMapSnapshot.build(waypoints: waypoints.waypoints,folders: waypoints.folders,document: field.document)
        return try XCTUnwrap(WatchMapSnapshot.decode(XCTUnwrap(result.encoded())))
    }
    func testHiddenSelectedTargetDoesNotBypassMapVisibilityAndFolderChangesReachEveryKind() throws {
        let (waypoints,field) = try stores()
        let target = waypoints.add(.init(name: "Selected",lat: 24,lon: 54,folder: "Recon"))
        waypoints.select(target.id)
        try field.saveGraphic(.init(id: "route",name: "Route",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],folder: "Recon"))
        let (track,bytes) = try TrackCodec.imported(name: "Track",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],now: 1000,folder: "Recon")
        var imported = Backup.Document(); imported.hasSettings = false
        imported.tracks = [track]; imported.trackFiles[track.id] = bytes
        _ = try field.restore(imported)
        XCTAssertEqual(try snapshot(waypoints,field).features.count,2)
        try waypoints.setLibraryFolderVisible("Recon",visible: false)
        let hidden = try snapshot(waypoints,field)
        XCTAssertTrue(hidden.waypoints.isEmpty); XCTAssertTrue(hidden.features.isEmpty)
        XCTAssertEqual(waypoints.selectedId,target.id)
        try waypoints.setLibraryFolderVisible("Recon",visible: true)
        waypoints.setVisible(id: target.id,visible: false)
        XCTAssertTrue(try snapshot(waypoints,field).waypoints.isEmpty)
        XCTAssertEqual(try snapshot(waypoints,field).features.count,2)
    }
    func testBatchHideAndDeleteProduceCompleteEmptyReplacementWithoutChangingSelection() throws {
        let (waypoints,field) = try stores()
        let target = waypoints.add(.init(name: "Point",lat: 24,lon: 54)); waypoints.select(target.id)
        try field.saveGraphic(.init(id: "area",name: "Area",type: "area",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54),.init(lat: 24,lon: 54.01)]))
        let old = try snapshot(waypoints,field)
        XCTAssertEqual(old.waypoints.count,1); XCTAssertEqual(old.features.count,1)
        try waypoints.applyLibraryBatch(ids: [target.id],action: .swapVisibility)
        try field.applyLibraryBatch(graphicIDs: ["area"],trackIDs: [],action: .swapVisibility)
        let empty = try snapshot(waypoints,field)
        XCTAssertTrue(empty.waypoints.isEmpty); XCTAssertTrue(empty.features.isEmpty)
        XCTAssertEqual(empty.omittedItems,0); XCTAssertEqual(waypoints.selectedId,target.id)
        try field.deleteGraphic("area"); waypoints.delete(ids: [target.id])
        XCTAssertTrue(try snapshot(waypoints,field).features.isEmpty)
        XCTAssertTrue(try snapshot(waypoints,field).waypoints.isEmpty)
    }
    func testPersistentLaneVisibilityLinkedEditsAndDeletionReplaceWatchGeometry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let points=WaypointStore(directory:directory),field=FieldDataStore(directory:directory),lanes=NavigationLaneStore(directory:directory)
        var left=Backup.Graphic(id:"left",name:"Creek",type:"phase_line",points:[.init(lat:24,lon:54),.init(lat:24.003,lon:54)])
        try field.saveGraphic(left)
        let value=NavLane(id:"lane",name:"Patrol",left:.init(graphicId:"left"),right:.init(points:[.init(lat:24,lon:54.001),.init(lat:24.003,lon:54.001)]),backstop:.init(points:[.init(lat:24.0032,lon:53.999),.init(lat:24.0032,lon:54.002)]),scope:.checkpoint,targetId:"cp")
        _ = try await lanes.save(value,graphics:field.document.graphics)
        func scene()->WatchMapSnapshot { WatchMapSnapshot.build(waypoints:points.waypoints,folders:points.folders,document:field.document,lanes:lanes.lanes) }
        let original=scene();XCTAssertEqual(original.laneOverlays.count,1)
        left.name="Renamed creek";left.points[0].lon-=0.0001;try field.saveGraphic(left)
        let edited=scene();XCTAssertEqual(edited.laneOverlays[0].leftLabel,"Renamed creek");XCTAssertNotEqual(edited.laneOverlays[0].left,original.laneOverlays[0].left)
        try await lanes.setVisible("lane",false);XCTAssertTrue(scene().laneOverlays.isEmpty)
        try await lanes.setVisible("lane",true);try points.setLibraryFolderVisible("Base",visible:false)
        XCTAssertTrue(scene().laneOverlays.isEmpty)
        try points.setLibraryFolderVisible("Base",visible:true);try field.deleteGraphic("left")
        let orphan=scene();XCTAssertTrue(orphan.laneOverlays.isEmpty);XCTAssertEqual(orphan.omittedItems,1)
    }

}
