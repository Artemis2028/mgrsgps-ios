import Combine
import GridFixCore
import XCTest
@testable import MGRSGPS

private actor BacktrackWorkGate {
    private var continuation: CheckedContinuation<Void,Never>?
    private var open = false
    func wait() async { if open { return }; await withCheckedContinuation { continuation = $0 } }
    func release() { open = true; continuation?.resume(); continuation = nil }
}

@MainActor
final class BacktrackIntegrationTests: XCTestCase {
    private func fixture() throws -> (URL,FieldDataStore,WaypointStore,Backup.TrackMeta) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let field = FieldDataStore(directory: dir), waypoints = WaypointStore(directory: dir)
        let point = waypoints.add(.init(name: "Existing target",lat: 24,lon: 54)); waypoints.select(point.id)
        let (track,bytes) = try TrackCodec.imported(name: "Patrol",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54),.init(lat: 24.01,lon: 54.01)],now: 1000,folder: "Recon")
        var doc = Backup.Document(); doc.hasSettings = false; doc.tracks = [track]; doc.trackFiles[track.id] = bytes
        _ = try field.restore(doc); _ = try waypoints.createLibraryFolder("Recon"); try waypoints.setLibraryFolderVisible("Recon",visible: false)
        return (dir,field,waypoints,track)
    }
    func testBacktrackPublishesReverseRouteKeepsLogAndDoesNotSelectNavigationTarget() async throws {
        let (dir,field,waypoints,track) = try fixture(), before = field.document.trackFiles[track.id], selected = waypoints.selectedId
        let route = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints)
        XCTAssertEqual(route.points.first,.init(lat: 24.01,lon: 54.01)); XCTAssertEqual(route.points.last,.init(lat: 24,lon: 54))
        XCTAssertEqual(route.folder,"Recon"); XCTAssertEqual(route.name,"Back Patrol")
        XCTAssertEqual(field.document.trackFiles[track.id],before); XCTAssertEqual(waypoints.selectedId,selected); XCTAssertEqual(waypoints.waypoints.count,1)
        XCTAssertEqual(waypoints.folders.first { $0.name == "Recon" }?.visible,true)
        XCTAssertEqual(FieldDataStore(directory: dir).document.graphics,[route])
    }
    func testCancelledBacktrackCannotPublishLateRoute() async throws {
        let (_,field,waypoints,track) = try fixture()
        let task = Task { try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled work must not publish") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(field.document.graphics.isEmpty); XCTAssertEqual(field.document.tracks.count,1)
    }
    func testDeferredBacktrackPublishesSameRouteWithoutMaterializingLogBytes() async throws {
        let (dir,original,waypoints,track) = try fixture()
        let expected = try TrackBacktrack.route(track: track,data: original.document.trackData(track.id))
        let field = FieldDataStore(directory: dir,loadImmediately: false)
        XCTAssertTrue(try field.publishLoad(field.loadSnapshot().prepare(deferTrackContents: true)))
        XCTAssertTrue(field.document.trackFiles.isEmpty)
        XCTAssertNotNil(field.document.localTrackFiles[track.id])
        let selected = waypoints.selectedId
        let result = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints)
        XCTAssertEqual(result.points,expected.points); XCTAssertEqual(result.name,expected.name)
        XCTAssertEqual(result.folder,expected.folder); XCTAssertEqual(waypoints.selectedId,selected)
        XCTAssertTrue(field.document.trackFiles.isEmpty)
        XCTAssertEqual(FieldDataStore(directory: dir).document.graphics,[result])
    }
    func testDeletedTrackCannotProduceRouteFromOldSelection() async throws {
        let (_,field,waypoints,track) = try fixture(); try field.deleteTrack(track.id)
        do { _ = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints); XCTFail("Deleted track") } catch {}
        XCTAssertTrue(field.document.graphics.isEmpty)
    }
    func testFailedBacktrackSaveKeepsOriginalTrackAndNoPublishedRoute() async throws {
        let (dir,field,waypoints,track) = try fixture(), before = field.document
        let path = dir.appendingPathComponent("field-data-v2.json")
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        do { _ = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints); XCTFail("Unwritable archive") } catch {}
        XCTAssertEqual(field.document,before)
    }
    func testSourceRemovedDuringFolderPublicationCannotCreateLateRoute() async throws {
        let (_,field,waypoints,track) = try fixture()
        var removed = false
        let subscription = waypoints.$folders.dropFirst().sink { folders in
            guard !removed, folders.contains(where: { $0.name == "Recon" && $0.visible }) else { return }
            removed = true
            do { try field.deleteTrack(track.id) }
            catch { XCTFail(error.localizedDescription) }
        }
        defer { subscription.cancel() }
        do { _ = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints); XCTFail("Removed source produced route") } catch {}
        XCTAssertTrue(removed); XCTAssertTrue(field.document.tracks.isEmpty)
        XCTAssertTrue(field.document.graphics.isEmpty)
    }

    private func replace(_ track: Backup.TrackMeta,in field: FieldDataStore) throws -> Data {
        try field.deleteTrack(track.id)
        var changed = track; changed.name = "New patrol"; changed.folder = "New folder"
        let bytes = try TrackCodec.encode([.init(lat: -10,lon: 170),.init(lat: -9,lon: -179)])
        var document = Backup.Document(tracks: [changed],trackFiles: [track.id: bytes]); document.hasSettings = false
        _ = try field.restore(document)
        return bytes
    }
    func testReplacedSourceDuringBuildRetriesCurrentBytesNameAndFolder() async throws {
        let (_,field,waypoints,track) = try fixture(), gate = BacktrackWorkGate()
        let entered = expectation(description: "captured log"); entered.assertForOverFulfill = false
        let work = Task {
            try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints,build: { meta,bytes in
                entered.fulfill(); await gate.wait(); return try TrackBacktrack.route(track: meta,data: bytes)
            })
        }
        await fulfillment(of: [entered],timeout: 5)
        let bytes = try replace(track,in: field); await gate.release()
        let result = try await work.value
        XCTAssertEqual(result.name,"Back New patrol"); XCTAssertEqual(result.folder,"New folder")
        XCTAssertEqual(result.points,[.init(lat: -9,lon: -179),.init(lat: -10,lon: 170)])
        XCTAssertEqual(field.document.trackFiles[track.id],bytes)
        XCTAssertEqual(waypoints.folders.first { $0.name == "Recon" }?.visible,false)
    }
    func testDeletedSourceDuringBuildCannotRevealFolderOrPublish() async throws {
        let (_,field,waypoints,track) = try fixture(), gate = BacktrackWorkGate()
        let entered = expectation(description: "building source")
        let work = Task {
            try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints,build: { meta,bytes in
                entered.fulfill(); await gate.wait(); return try TrackBacktrack.route(track: meta,data: bytes)
            })
        }
        await fulfillment(of: [entered],timeout: 5); try field.deleteTrack(track.id); await gate.release()
        do { _ = try await work.value; XCTFail("Deleted source produced backtrack") } catch {}
        XCTAssertTrue(field.document.graphics.isEmpty)
        XCTAssertEqual(waypoints.folders.first { $0.name == "Recon" }?.visible,false)
    }
    func testCancelledBuildPropagatesToWorkerAndCannotRevealFolder() async throws {
        let (_,field,waypoints,track) = try fixture(), gate = BacktrackWorkGate()
        let entered = expectation(description: "worker running"), cancelled = expectation(description: "worker received cancellation")
        let work = Task {
            try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints,build: { meta,bytes in
                entered.fulfill(); await gate.wait()
                if Task.isCancelled { cancelled.fulfill() }
                return try TrackBacktrack.route(track: meta,data: bytes)
            })
        }
        await fulfillment(of: [entered],timeout: 5); work.cancel(); await gate.release()
        do { _ = try await work.value; XCTFail("Cancelled worker published") } catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [cancelled],timeout: 5)
        XCTAssertTrue(field.document.graphics.isEmpty)
        XCTAssertEqual(waypoints.folders.first { $0.name == "Recon" }?.visible,false)
    }
    func testSameIDReplacementDuringFolderPublicationCannotPublishOldGeometry() async throws {
        let (_,field,waypoints,track) = try fixture()
        var replaced = false
        let subscription = waypoints.$folders.dropFirst().sink { folders in
            if !replaced,folders.contains(where: { $0.name == "Recon" && $0.visible }) {
                replaced = true
                do { _ = try self.replace(track,in: field) } catch { XCTFail(error.localizedDescription) }
            }
        }
        defer { subscription.cancel() }
        do { _ = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints); XCTFail("Old log produced route") } catch {}
        XCTAssertTrue(replaced); XCTAssertEqual(field.document.tracks.first?.name,"New patrol"); XCTAssertTrue(field.document.graphics.isEmpty)
    }
    func testReplacementDuringRouteStagingCannotPublishOldGeometry() async throws {
        let (dir,field,waypoints,track) = try fixture(), gate = BacktrackWorkGate()
        let entered = expectation(description: "route staged")
        let work = Task {
            try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints,prepare: { snapshot,route in
                let prepared = try snapshot.prepare(edit: .createGraphic(route)); entered.fulfill(); await gate.wait(); return prepared
            })
        }
        await fulfillment(of: [entered],timeout: 5); let bytes = try replace(track,in: field); await gate.release()
        do { _ = try await work.value; XCTFail("Staged old route published") } catch {}
        XCTAssertTrue(field.document.graphics.isEmpty); XCTAssertEqual(field.document.trackFiles[track.id],bytes)
        XCTAssertTrue(FieldDataStore(directory: dir).document.graphics.isEmpty)
    }
    func testCancellationDuringRouteStagingDiscardsPreparedOutput() async throws {
        let (dir,field,waypoints,track) = try fixture(), gate = BacktrackWorkGate(), before = field.document
        let entered = expectation(description: "prepared route awaiting publication")
        let work = Task {
            try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints,prepare: { snapshot,route in
                let prepared = try snapshot.prepare(edit: .createGraphic(route)); entered.fulfill(); await gate.wait(); return prepared
            })
        }
        await fulfillment(of: [entered],timeout: 5); work.cancel(); await gate.release()
        do { _ = try await work.value; XCTFail("Cancelled stage published") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(field.document,before); XCTAssertTrue(FieldDataStore(directory: dir).document.graphics.isEmpty)
    }
    func testLongBacktrackBuildKeepsMainResponsiveAndOriginalLogAndTarget() async throws {
        let (_,field,waypoints,_) = try fixture(), id = UUID().uuidString.lowercased()
        let document = await Task.detached {
            let bytes = Data(("0 0 0 -32768\n"+String(repeating: "0 0.001 0 -32768\n",count: 300_001)+"0.01 0.001 0 -32768\n").utf8)
            var value = Backup.Document(tracks: [.init(id: id,name: "Long patrol",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: 300_003)],trackFiles: [id: bytes]); value.hasSettings = false
            return value
        }.value
        try await FieldEditAction.apply(.saveRecordedTrack(document),to: field)
        let selected = waypoints.selectedId, bytes = field.document.trackFiles[id], track = try XCTUnwrap(field.document.tracks.first { $0.id == id })
        var done = false,pulses = 0
        let pulse = Task { while !done && !Task.isCancelled { pulses += 1; try? await Task.sleep(nanoseconds: 1_000_000) } }
        defer { done = true; pulse.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        let route = try await TrackBacktrackAction.create(track: track,field: field,waypoints: waypoints)
        done = true; await pulse.value
        XCTAssertGreaterThan(pulses,2); XCTAssertLessThanOrEqual(route.points.count,64)
        XCTAssertEqual(route.points.first,.init(lat: 0.01,lon: 0.001)); XCTAssertEqual(route.points.last,.init(lat: 0,lon: 0))
        XCTAssertEqual(field.document.trackFiles[id],bytes); XCTAssertEqual(waypoints.selectedId,selected)
        print("[backtrack-benchmark] 300003 points; vertices \(route.points.count); main pulses \(pulses); seconds \(ProcessInfo.processInfo.systemUptime-start)")
    }
}
