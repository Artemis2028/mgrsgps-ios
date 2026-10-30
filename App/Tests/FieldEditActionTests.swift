import Combine
import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class FieldEditActionTests: XCTestCase {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }; return directory
    }
    private func graphic(_ id: String = "g") -> Backup.Graphic {
        .init(id: id,name: "Route",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],folder: "Patrol")
    }
    func testSavePublishesOnMainAndRegistersFolderWithoutChangingSelection() async throws {
        let directory = try directory(), field = FieldDataStore(directory: directory), points = WaypointStore(directory: directory)
        let target = points.add(.init(name: "Selected",lat: 24,lon: 54)); points.select(target.id)
        let subscription = field.$document.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        let saved = try await FieldEditAction.saveGraphic(graphic(),original: nil,field: field,waypoints: points)
        XCTAssertEqual(saved,graphic()); XCTAssertEqual(FieldDataStore(directory: directory).document.graphics,[saved])
        XCTAssertTrue(WaypointStore(directory: directory).folders.contains { $0.name == "Patrol" })
        XCTAssertEqual(WaypointStore(directory: directory).selectedId,target.id)
        subscription.cancel()
    }
    func testFolderFailureReportsSavedGraphicAndRetryKeepsItsNewerVisibility() async throws {
        let directory = try directory(), field = FieldDataStore(directory: directory), points = WaypointStore(directory: directory)
        let target = points.add(.init(name: "Selected",lat: 24,lon: 54)); points.select(target.id)
        let blocked = directory.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: blocked); try FileManager.default.createDirectory(at: blocked,withIntermediateDirectories: false)
        do { _ = try await FieldEditAction.saveGraphic(graphic(),original: nil,field: field,waypoints: points); XCTFail("Folder write unexpectedly succeeded") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Graphic saved"),error.localizedDescription) }
        XCTAssertEqual(FieldDataStore(directory: directory).document.graphics.count,1)
        try await FieldEditAction.apply(.setGraphicVisible("g",false),to: field)
        try FileManager.default.removeItem(at: blocked)
        let saved = try await FieldEditAction.saveGraphic(graphic(),original: nil,field: field,waypoints: points)
        XCTAssertFalse(saved.visible); XCTAssertEqual(field.document.graphics.count,1)
        let reopened = WaypointStore(directory: directory)
        XCTAssertEqual(reopened.selectedId,target.id); XCTAssertEqual(reopened.waypoints.count,1)
        XCTAssertTrue(reopened.folders.contains { $0.name == "Patrol" })
    }
    func testCancelledBeforeStartDoesNotCreateGraphicButPublicationFinishesAStartedEdit() async throws {
        let directory = try directory(), field = FieldDataStore(directory: directory), value = graphic()
        let cancelled = Task { try await FieldEditAction.apply(.createGraphic(value),to: field) }
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Pre-cancelled edit published") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(field.document.graphics.isEmpty)
        let owner = EditTaskOwner()
        let subscription = field.$document.dropFirst().sink { _ in owner.work?.cancel() }
        owner.work = Task { try await FieldEditAction.apply(.createGraphic(value),to: field) }
        try await owner.work!.value
        XCTAssertTrue(owner.work!.isCancelled)
        XCTAssertEqual(FieldDataStore(directory: directory).document.graphics,[value])
        subscription.cancel(); owner.work = nil
    }
    func testMutationOwnsWorkRejectsDuplicatesAndDoesNotDismissDepartedPresentation() async throws {
        var mutation: FieldMutation? = FieldMutation(); weak var retained = mutation
        mutation!.setPresented(true)
        let entered = expectation(description: "confirmed action entered"), finished = expectation(description: "confirmed action finished")
        let gate = EditGate(); var applied = false
        XCTAssertTrue(mutation!.run("Saving…",action: { entered.fulfill(); await gate.wait(); applied = true },completion: { presented in
            XCTAssertFalse(presented); finished.fulfill()
        }))
        await fulfillment(of: [entered],timeout: 3)
        XCTAssertTrue(mutation!.working)
        XCTAssertFalse(mutation!.run("Duplicate",action: { XCTFail("Duplicate action ran") }))
        mutation!.setPresented(false); mutation = nil
        XCTAssertNotNil(retained)
        await gate.finish(); await fulfillment(of: [finished],timeout: 3)
        XCTAssertTrue(applied)
        for _ in 0..<50 where retained != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(retained)
    }
    func testFinishedMutationCannotDismissAReopenedPresentationAndPublishesOnMain() async throws {
        let mutation = FieldMutation(), gate = EditGate()
        let entered = expectation(description: "old presentation work entered"), finished = expectation(description: "old work finished")
        var applied = false
        let subscription = mutation.$label.dropFirst().sink { _ in XCTAssertTrue(Thread.isMainThread) }
        defer { subscription.cancel() }
        mutation.setPresented(true)
        XCTAssertTrue(mutation.run("Saving…",action: {
            XCTAssertTrue(Thread.isMainThread); entered.fulfill(); await gate.wait(); applied = true
        },completion: { current in XCTAssertTrue(Thread.isMainThread); XCTAssertFalse(current); finished.fulfill() }))
        await fulfillment(of: [entered],timeout: 3)
        mutation.setPresented(false); mutation.setPresented(true)
        await gate.finish(); await fulfillment(of: [finished],timeout: 3)
        XCTAssertTrue(applied); XCTAssertFalse(mutation.working)
        let next = expectation(description: "new presentation remains usable")
        XCTAssertTrue(mutation.run("Next",action: {},completion: { XCTAssertTrue($0); next.fulfill() }))
        await fulfillment(of: [next],timeout: 3)
    }
    func testMutationFailureKeepsErrorAndReleasesBusyStateForRetry() async throws {
        let mutation = FieldMutation(), done = expectation(description: "failed edit finished")
        let subscription = mutation.$label.dropFirst().filter { $0 == nil }.sink { _ in done.fulfill() }
        XCTAssertTrue(mutation.run("Saving…",action: { throw CocoaError(.fileWriteOutOfSpace) }))
        await fulfillment(of: [done],timeout: 3); subscription.cancel()
        XCTAssertFalse(mutation.working); XCTAssertNotNil(mutation.error)
        mutation.clearError(); XCTAssertNil(mutation.error)
        mutation.setPresented(true)
        let retry = expectation(description: "retry completed")
        XCTAssertTrue(mutation.run("Retrying…",action: {},completion: { XCTAssertTrue($0); retry.fulfill() }))
        await fulfillment(of: [retry],timeout: 3)
        XCTAssertFalse(mutation.working); XCTAssertNil(mutation.error)
    }
    func testLargeArchiveConcurrentEditsKeepMainActorResponsiveAndPreserveBothIntents() async throws {
        let directory = try directory()
        let field = try await Task.detached(priority: .userInitiated) {
            var source = Backup.Document(); source.hasSettings = false
            source.graphics = (0..<1000).map { i in Backup.Graphic(id: "route-\(i)",name: "Route \(i)",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)]) }
            let (track,bytes) = try TrackCodec.imported(name: "Large track",points: (0..<50000).map { TrackPoint(lat: 24+Double($0%1000)*0.000001,lon: 54) },now: 1000)
            source.tracks = [track]; source.trackFiles[track.id] = bytes
            let field = FieldDataStore(directory: directory); _ = try field.restore(source); return field
        }.value
        let original = field.document.graphics[0], originalBytes = field.document.trackFiles
        var updated = original; updated.name = "Edited route"
        let additional = Backup.Graphic(id: "additional",name: "Concurrent",type: "checkpoint",points: [.init(lat: 24,lon: 54)])
        let state = EditHeartbeat()
        let heartbeat = Task { @MainActor in
            var last = ProcessInfo.processInfo.systemUptime
            while !state.done && !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                state.maximumGap = max(state.maximumGap,now-last); last = now; state.pulses += 1
                if state.pulses == 2 { state.second = Task { try await FieldEditAction.apply(.createGraphic(additional),to: field) } }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        defer { state.done = true; heartbeat.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        try await FieldEditAction.apply(.editGraphic(original: original,updated: updated),to: field)
        try await state.second?.value
        let elapsed = ProcessInfo.processInfo.systemUptime-start
        state.done = true; await heartbeat.value
        XCTAssertGreaterThan(state.pulses,2); XCTAssertNotNil(state.second)
        let reopened = FieldDataStore(directory: directory)
        XCTAssertEqual(reopened.document.graphics.count,1001)
        XCTAssertEqual(reopened.document.graphics.first { $0.id == original.id }?.name,"Edited route")
        XCTAssertTrue(reopened.document.graphics.contains { $0.id == "additional" })
        XCTAssertEqual(reopened.document.trackFiles,originalBytes)
        let metrics = String(format: "1000 routes / 50000 track points; two concurrent atomic edits %.3f s; main-actor pulses %d; largest gap %.3f s",elapsed,state.pulses,state.maximumGap)
        print("[field-edit-benchmark] \(metrics)")
        let attachment = XCTAttachment(string: metrics); attachment.name = "field-edit-benchmark"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

@MainActor
private final class EditTaskOwner { var work: Task<Void,Error>? }
private actor EditGate {
    private var done = false
    private var continuation: CheckedContinuation<Void,Never>?
    func wait() async { if !done { await withCheckedContinuation { continuation = $0 } } }
    func finish() { done = true; continuation?.resume(); continuation = nil }
}
@MainActor
private final class EditHeartbeat {
    var done = false
    var pulses = 0
    var maximumGap = 0.0
    var second: Task<Void,Error>?
}
