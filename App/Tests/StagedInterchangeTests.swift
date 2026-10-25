import Combine
import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class StagedInterchangeTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func document() throws -> Backup.Document {
        try GPX.parse("<gpx><wpt lat=\"24\" lon=\"54\"><name>Checkpoint</name></wpt><rte><name>Patrol</name><rtept lat=\"24\" lon=\"54\"/><rtept lat=\"24.01\" lon=\"54\"/></rte><trk><name>Walk</name><trkseg><trkpt lat=\"24\" lon=\"54\"/><trkpt lat=\"24.01\" lon=\"54\"/></trkseg></trk></gpx>")
    }
    func testCancelledBeforeStartDoesNotPublishAnything() async throws {
        let directory = try directory(), points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), document = try document()
        let work = Task { try await InterchangeCoordinator.apply(document,waypoints: points,field: field) }
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled import returned normally") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(points.waypoints.isEmpty); XCTAssertTrue(field.document.tracks.isEmpty); XCTAssertTrue(field.document.graphics.isEmpty)
    }
    func testCancellationAfterTrackPublicationFinishesPhaseAndRetryKeepsEditedTrack() async throws {
        let directory = try directory(), points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory), document = try document()
        let owner = ImportTaskOwner()
        let subscription = field.$document.dropFirst().sink { value in
            XCTAssertTrue(Thread.isMainThread)
            if !value.tracks.isEmpty { owner.work?.cancel() }
        }
        owner.work = Task { try await InterchangeCoordinator.apply(document,waypoints: points,field: field) }
        do { _ = try await owner.work!.value; XCTFail("Cancellation was swallowed") }
        catch { XCTAssertTrue(error is CancellationError) }
        subscription.cancel(); owner.work = nil
        XCTAssertEqual(field.document.tracks.count,1); XCTAssertTrue(field.document.graphics.isEmpty); XCTAssertTrue(points.waypoints.isEmpty)
        let id = try XCTUnwrap(field.document.tracks.first?.id)
        XCTAssertEqual(try FieldDataStore(directory: directory).points(for: id).count,2)
        try field.moveTrack(id,to: "Local edits")
        let result = try await InterchangeCoordinator.apply(document,waypoints: points,field: field)
        XCTAssertTrue(result.completed,result.message)
        XCTAssertEqual(points.waypoints.count,1); XCTAssertEqual(field.document.graphics.count,1)
        XCTAssertEqual(FieldDataStore(directory: directory).document.tracks.first?.folder,"Local edits")
    }
    func testInvalidPlanCannotCommitEarlierTrackPhase() async throws {
        let directory = try directory(), points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory)
        var document = try document(); document.waypoints[0].lat = .nan
        let result = try await InterchangeCoordinator.apply(document,waypoints: points,field: field)
        XCTAssertFalse(result.completed); XCTAssertTrue(result.message.contains("No records added"),result.message)
        XCTAssertTrue(field.document.tracks.isEmpty); XCTAssertTrue(points.waypoints.isEmpty)
    }
    func testLargeParsedGPXCommitsWhileMainActorKeepsServingEdits() async throws {
        let document = try await Task.detached(priority: .userInitiated) {
            let points = (0..<5000).map { Waypoint(id: "source-\($0)",name: "Point \($0)",lat: 24+Double($0)*0.000001,lon: 54) }
            let routes = (0..<1000).map { i in Backup.Graphic(id: "route-\(i)",name: "Route \(i)",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)]) }
            let track = GPX.Track(name: "Large track",points: (0..<50000).map { TrackPoint(lat: 24+Double($0%1000)*0.000001,lon: 54) })
            let bytes = Data(GPX.build(waypoints: points,routes: routes,tracks: [track]).utf8)
            return try TextInterchange.preview(bytes,format: .gpx,now: 1000).document
        }.value
        let directory = try directory(), points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory)
        let local = points.add(.init(name: "Local",lat: 24,lon: 54))
        let state = ImportHeartbeat()
        let heartbeat = Task { @MainActor in
            var last = ProcessInfo.processInfo.systemUptime
            while !state.done && !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                state.maximumGap = max(state.maximumGap,now-last); last = now; state.pulses += 1
                if state.pulses == 2 { points.update(id: local.id,draft: .init(name: "Edited during import",lat: 24,lon: 54)); points.select(local.id) }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        defer { state.done = true; heartbeat.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        let result = try await InterchangeCoordinator.apply(document,waypoints: points,field: field)
        let elapsed = ProcessInfo.processInfo.systemUptime-start
        state.done = true; await heartbeat.value
        XCTAssertTrue(result.completed,result.message); XCTAssertGreaterThan(state.pulses,2)
        let durable = WaypointStore(directory: directory), saved = FieldDataStore(directory: directory)
        XCTAssertEqual(durable.waypoints.count,5001); XCTAssertEqual(durable.selectedId,local.id)
        XCTAssertEqual(durable.waypoints.first { $0.id == local.id }?.name,"Edited during import")
        XCTAssertEqual(saved.document.graphics.count,1000)
        XCTAssertEqual(try saved.points(for: document.tracks[0].id).count,50000)
        let metrics = String(format: "Parsed GPX: 5000 waypoints, 1000 routes, 50000 track points; commit %.3f s; main-actor pulses %d; largest pulse gap %.3f s",elapsed,state.pulses,state.maximumGap)
        print("[staged-interchange-benchmark] \(metrics)")
        let attachment = XCTAttachment(string: metrics); attachment.name = "staged-interchange-benchmark"; attachment.lifetime = .keepAlways; add(attachment)
        // Record timing rather than impose a hardware-dependent pass threshold.
    }

    func testCommitCancellationLeavesAnExplicitMessageAndAllowsFreshPreviewRetry() async throws {
        let commit = InterchangeCommit(), failed = expectation(description: "cancelled commit finished")
        commit.setPresented(true)
        let subscription = commit.$importing.dropFirst().filter { !$0 }.sink { _ in failed.fulfill() }
        XCTAssertTrue(commit.start(Backup.Document(),apply: { _ in throw CancellationError() },completion: { _ in XCTFail("Cancelled apply completed normally") }))
        await fulfillment(of: [failed],timeout: 3)
        subscription.cancel()
        XCTAssertFalse(commit.importing); XCTAssertTrue(commit.failure?.contains("Already saved records are kept") == true)
        commit.clearFailure(); XCTAssertNil(commit.failure)
        let completed = expectation(description: "retry completed")
        XCTAssertTrue(commit.start(Backup.Document(),apply: { _ in .init(completed: true,message: "Imported") },completion: { _ in completed.fulfill() }))
        await fulfillment(of: [completed],timeout: 3)
        XCTAssertFalse(commit.importing); XCTAssertNil(commit.failure)
    }

    func testDepartedSheetCannotDismissAReplacementButApplyStillFinishes() async throws {
        let commit = InterchangeCommit(), entered = expectation(description: "apply started"), finished = expectation(description: "commit finished")
        commit.setPresented(true)
        let subscription = commit.$importing.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        let gate = ImportCommitGate()
        var applied = false
        XCTAssertTrue(commit.start(Backup.Document(),apply: { _ in
            entered.fulfill(); await gate.wait(); applied = true
            return .init(completed: true,message: "Imported")
        },completion: { _ in XCTFail("Departed sheet attempted to dismiss the replacement preview") }))
        await fulfillment(of: [entered],timeout: 3)
        commit.setPresented(false); await gate.finish()
        await fulfillment(of: [finished],timeout: 3)
        subscription.cancel(); XCTAssertTrue(applied); XCTAssertFalse(commit.importing)
        commit.setPresented(true)
        let replacement = expectation(description: "new presentation completed")
        XCTAssertTrue(commit.start(Backup.Document(),apply: { _ in .init(completed: true,message: "Imported") },completion: { _ in replacement.fulfill() }))
        await fulfillment(of: [replacement],timeout: 3)
    }

    func testConfirmedCommitRejectsSecondStartAndSurvivesOwnerRelease() async throws {
        var commit: InterchangeCommit? = InterchangeCommit()
        weak var retained = commit
        commit!.setPresented(true)
        let entered = expectation(description: "confirmed apply entered"), completed = expectation(description: "confirmed apply completed")
        let gate = ImportCommitGate()
        XCTAssertTrue(commit!.start(Backup.Document(),apply: { _ in
            entered.fulfill(); await gate.wait()
            return .init(completed: true,message: "Imported")
        },completion: { result in XCTAssertTrue(result.completed); completed.fulfill() }))
        await fulfillment(of: [entered],timeout: 3)
        XCTAssertTrue(commit!.importing)
        XCTAssertFalse(commit!.start(Backup.Document(),apply: { _ in XCTFail("Duplicate confirmation applied"); return .init(completed: false,message: "") },completion: { _ in XCTFail("Duplicate completion") }))
        commit = nil
        XCTAssertNotNil(retained)
        await gate.finish(); await fulfillment(of: [completed],timeout: 3)
        for _ in 0..<50 where retained != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(retained)
    }
}

@MainActor
private final class ImportTaskOwner { var work: Task<InterchangeCoordinator.Result,Error>? }
private actor ImportCommitGate {
    private var continuation: CheckedContinuation<Void,Never>?
    private var finished = false
    func wait() async { if !finished { await withCheckedContinuation { continuation = $0 } } }
    func finish() { finished = true; continuation?.resume(); continuation = nil }
}

@MainActor
private final class ImportHeartbeat {
    var done = false
    var pulses = 0
    var maximumGap = 0.0
}
