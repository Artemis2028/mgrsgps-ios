import Combine
import GridFixCore
import XCTest
@testable import MGRSGPS

private actor FocusScanGate {
    private var continuation: CheckedContinuation<Void,Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { opened = true; continuation?.resume(); continuation = nil }
}

@MainActor
final class TrackMapFocusTests: XCTestCase {
    private func fixture() throws -> (URL,FieldDataStore,WaypointStore,Backup.TrackMeta) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let field = FieldDataStore(directory: dir), points = WaypointStore(directory: dir)
        let target = points.add(.init(name: "Current target",lat: 24,lon: 54)); points.select(target.id)
        let (track,bytes) = try TrackCodec.imported(name: "Hidden patrol",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54.02)],now: 1,folder: "Recon")
        var document = Backup.Document(tracks: [track],trackFiles: [track.id: bytes]); document.hasSettings = false
        _ = try field.restore(document)
        try field.setTrackVisible(track.id,visible: false)
        _ = try points.createLibraryFolder("Recon"); try points.setLibraryFolderVisible("Recon",visible: false)
        return (dir,field,points,track)
    }
    func testFocusRevealsFolderPreservesHiddenFlagTargetAndExactBounds() async throws {
        let (_,field,points,track) = try fixture(), selected = points.selectedId, before = field.document
        let result = try await TrackMapFocusAction.prepare(trackID: track.id,field: field,waypoints: points)
        XCTAssertTrue(result.isCurrent(in: field)); XCTAssertEqual(result.trackID,track.id)
        XCTAssertLessThanOrEqual(result.points.count,6)
        let bounds = try XCTUnwrap(FieldMapGeometry.bounds(result.points))
        XCTAssertEqual(bounds.south,24); XCTAssertEqual(bounds.north,24.01); XCTAssertEqual(bounds.east,54.02)
        XCTAssertEqual(points.folders.first { $0.name == "Recon" }?.visible,true)
        XCTAssertEqual(field.document,before); XCTAssertFalse(field.document.tracks[0].visible)
        XCTAssertEqual(points.selectedId,selected)
        try field.deleteTrack(track.id); XCTAssertFalse(result.isCurrent(in: field))
    }
    func testCancelledFocusDoesNotRevealFolder() async throws {
        let (_,field,points,track) = try fixture()
        let work = Task { try await TrackMapFocusAction.prepare(trackID: track.id,field: field,waypoints: points) }
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled focus") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(points.folders.first { $0.name == "Recon" }?.visible,false)
    }
    func testCancellationDuringScanCannotRevealFolderOrReturnLateFocus() async throws {
        let (_,field,points,track) = try fixture(), gate = FocusScanGate()
        let entered = expectation(description: "scan running before cancellation")
        let work = Task {
            try await TrackMapFocusAction.prepare(trackID: track.id,field: field,waypoints: points,scan: { bytes in
                entered.fulfill(); await gate.wait(); return try FieldMapGeometry.trackFitPoints(bytes)
            })
        }
        await fulfillment(of: [entered],timeout: 5)
        work.cancel(); await gate.release()
        do { _ = try await work.value; XCTFail("Cancelled scan returned focus") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(points.folders.first { $0.name == "Recon" }?.visible,false)
        XCTAssertFalse(field.document.tracks[0].visible)
    }
    func testDeletionDuringScanCannotReturnOldGeometry() async throws {
        let (_,field,points,track) = try fixture(), gate = FocusScanGate()
        let entered = expectation(description: "worker reading captured source")
        let work = Task {
            try await TrackMapFocusAction.prepare(trackID: track.id,field: field,waypoints: points,scan: { bytes in
                entered.fulfill(); await gate.wait(); return try FieldMapGeometry.trackFitPoints(bytes)
            })
        }
        await fulfillment(of: [entered],timeout: 5)
        try field.deleteTrack(track.id); await gate.release()
        do { _ = try await work.value; XCTFail("Deleted source") } catch {}
        XCTAssertEqual(points.folders.first { $0.name == "Recon" }?.visible,false)
    }
    func testReplacementDuringScanRetriesFromCurrentLog() async throws {
        let (_,field,points,track) = try fixture(), gate = FocusScanGate()
        let entered = expectation(description: "first source captured"); entered.assertForOverFulfill = false
        let work = Task {
            try await TrackMapFocusAction.prepare(trackID: track.id,field: field,waypoints: points,scan: { bytes in
                entered.fulfill(); await gate.wait(); return try FieldMapGeometry.trackFitPoints(bytes)
            })
        }
        await fulfillment(of: [entered],timeout: 5)
        try field.deleteTrack(track.id)
        let bytes = try TrackCodec.encode([.init(lat: -10,lon: 170),.init(lat: -9,lon: -179)])
        var replacement = Backup.Document(tracks: [track],trackFiles: [track.id: bytes]); replacement.hasSettings = false
        _ = try field.restore(replacement)
        await gate.release()
        let result = try await work.value, bounds = try XCTUnwrap(FieldMapGeometry.bounds(result.points))
        XCTAssertTrue(result.isCurrent(in: field)); XCTAssertEqual(bounds.south,-10); XCTAssertEqual(bounds.north,-9)
        XCTAssertEqual(bounds.west,170); XCTAssertEqual(bounds.east,181)
    }
    func testSourceRemovedDuringFolderPublicationCannotReturnLateFocus() async throws {
        let (_,field,points,track) = try fixture()
        var removed = false
        let subscription = points.$folders.dropFirst().sink { folders in
            if !removed, folders.contains(where: { $0.name == "Recon" && $0.visible }) {
                removed = true
                do { try field.deleteTrack(track.id) } catch { XCTFail(error.localizedDescription) }
            }
        }
        defer { subscription.cancel() }
        do { _ = try await TrackMapFocusAction.prepare(trackID: track.id,field: field,waypoints: points); XCTFail("Old source focus") } catch {}
        XCTAssertTrue(removed); XCTAssertTrue(field.document.tracks.isEmpty)
    }
    func testLongLocalTrackFocusKeepsMainActorResponsiveAndSourceUnchanged() async throws {
        let (_,field,points,_) = try fixture()
        let id = UUID().uuidString.lowercased()
        let document = await Task.detached {
            var data = Data("10 179.9 0 -32768\n70 -178.7 0 -32768\n".utf8)
            data.append(Data(String(repeating: "10 -179.9 0 -32768\n",count: 300_001).utf8))
            var value = Backup.Document(tracks: [.init(id: id,name: "Long dateline patrol",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: 300_003)],trackFiles: [id: data]); value.hasSettings = false
            return value
        }.value
        try await FieldEditAction.apply(.saveRecordedTrack(document),to: field)
        let before = field.document.trackFiles[id], selected = points.selectedId
        var pulses = 0, done = false
        let heartbeat = Task { while !done && !Task.isCancelled { pulses += 1; try? await Task.sleep(nanoseconds: 1_000_000) } }
        defer { done = true; heartbeat.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        let result = try await TrackMapFocusAction.prepare(trackID: id,field: field,waypoints: points)
        let elapsed = ProcessInfo.processInfo.systemUptime-start
        done = true; await heartbeat.value
        XCTAssertGreaterThan(pulses,2); XCTAssertLessThanOrEqual(result.points.count,6)
        let bounds = try XCTUnwrap(FieldMapGeometry.bounds(result.points))
        XCTAssertEqual(bounds.south,10); XCTAssertEqual(bounds.north,70); XCTAssertEqual(bounds.west,179.9); XCTAssertEqual(bounds.east,181.3,accuracy: 1e-9)
        XCTAssertEqual(field.document.trackFiles[id],before); XCTAssertEqual(points.selectedId,selected)
        let metrics = "300003 local points; fit coordinates \(result.points.count); main pulses \(pulses); scan seconds \(elapsed)"
        print("[track-focus-benchmark] \(metrics)")
        let attachment = XCTAttachment(string: metrics); attachment.name = "track-focus-benchmark"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
