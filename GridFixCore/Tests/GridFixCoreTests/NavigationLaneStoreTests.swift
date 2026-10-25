import XCTest
@testable import GridFixCore

@MainActor
final class NavigationLaneStoreTests: XCTestCase {
    private func fixture() throws -> (URL,NavigationLaneStore,NavLane) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let plane = LaneLocalPlane(origin: .init(lat: 35,lon: -79))
        func p(_ x: Double,_ y: Double) -> GeoPoint { plane.unproject(.init(x: x,y: y)) }
        let lane = NavLane(id: "lane",name: "Creek",left: .init(points: [p(-50,0),p(-50,500)]),right: .init(points: [p(50,0),p(50,500)]),backstop: .init(points: [p(-100,520),p(100,520)]),scope: .checkpoint,targetId: "cp",createdAt: 1)
        return (directory,NavigationLaneStore(directory: directory),lane)
    }
    func testSaveNormalizesAndReopensWithHiddenState() async throws {
        let (directory,store,lane) = try fixture()
        await store.waitUntilLoaded(); XCTAssertTrue(store.ready)
        var reversed = lane; reversed.left = lane.right; reversed.right = lane.left
        let saved = try await store.save(reversed,graphics: [])
        XCTAssertEqual(saved.left,lane.left)
        try await store.setVisible(saved.id,false)
        let reopened = NavigationLaneStore(directory: directory); await reopened.waitUntilLoaded()
        XCTAssertTrue(reopened.ready); XCTAssertNil(reopened.error)
        XCTAssertEqual(reopened.lanes.count,1); XCTAssertFalse(reopened.lanes[0].visible)
        XCTAssertEqual(reopened.lanes[0].left,lane.left)
    }
    func testConcurrentCommandsPreserveBothChangesAndCreateRetriesDoNotOverwrite() async throws {
        let (_,store,lane) = try fixture()
        _ = try await store.save(lane,graphics: [])
        var edited = lane; edited.name = "Renamed"
        async let rename = store.save(edited,original: lane,graphics: [])
        async let hide: Void = store.setVisible(lane.id,false)
        _ = try await (rename,hide)
        XCTAssertEqual(store.lanes[0].name,"Renamed"); XCTAssertFalse(store.lanes[0].visible)
        _ = try await store.save(lane,graphics: [])
        XCTAssertEqual(store.lanes[0].name,"Renamed"); XCTAssertFalse(store.lanes[0].visible)
        var second = lane; second.id = "second"
        var third = lane; third.id = "third"
        async let a = store.save(second,graphics: [])
        async let b = store.save(third,graphics: [])
        _ = try await (a,b)
        XCTAssertEqual(Set(store.lanes.map(\.id)),["lane","second","third"])
    }
    func testAnEditCannotResurrectDeletedOriginal() async throws {
        let (_,store,lane) = try fixture()
        _ = try await store.save(lane,graphics: [])
        try await store.delete(lane.id)
        do { _ = try await store.save(lane,original: lane,graphics: []); XCTFail("Deleted original recreated") } catch {}
        XCTAssertTrue(store.lanes.isEmpty)
    }
    func testCorruptOrDuplicateLibraryIsKeptAndCannotBeOverwritten() async throws {
        let (directory,_,lane) = try fixture(), file = directory.appendingPathComponent("nav-lanes-v1.json")
        for bytes in [Data("broken".utf8),try JSONEncoder().encode([lane,lane])] {
            try bytes.write(to: file)
            let store = NavigationLaneStore(directory: directory); await store.waitUntilLoaded()
            XCTAssertFalse(store.ready); XCTAssertNotNil(store.error)
            do { _ = try await store.save(lane,graphics: []); XCTFail("Damaged library replaced") } catch {}
            XCTAssertEqual(try Data(contentsOf: file),bytes)
        }
    }
    func testFailedAtomicRenameDoesNotPublishAndRetryWorks() async throws {
        let (directory,store,lane) = try fixture(), file = directory.appendingPathComponent("nav-lanes-v1.json")
        await store.waitUntilLoaded()
        try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        do { _ = try await store.save(lane,graphics: []); XCTFail("Directory replaced by file") } catch {}
        XCTAssertTrue(store.lanes.isEmpty); XCTAssertNotNil(store.error)
        try FileManager.default.removeItem(at: file)
        _ = try await store.save(lane,graphics: [])
        XCTAssertEqual(store.lanes,[lane]); XCTAssertNil(store.error)
    }
    func testInvalidGeometryAndLinkedLinesAreRejectedBeforeWrite() async throws {
        let (directory,store,lane) = try fixture()
        var invalid = lane; invalid.left.points = [.init(lat: 91,lon: 0),.init(lat: 35,lon: 0)]
        do { _ = try await store.save(invalid,graphics: []); XCTFail("Bad coordinate saved") } catch {}
        invalid = lane; invalid.left.graphicId = "deleted"
        do { _ = try await store.save(invalid,graphics: []); XCTFail("Missing link saved") } catch {}
        XCTAssertTrue(store.lanes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("nav-lanes-v1.json").path))
    }
}
