import Foundation
import XCTest
@testable import GridFixCore

final class PracticeStartupRecoveryTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private func file(_ root: URL) -> URL { root.appendingPathComponent("practice-course-v1.json") }
    func testWorkerPreparationPreservesLongRunSplitsAndOriginalBytes() async throws {
        let root = try directory(),store = PracticeCourseStore(directory: root)
        var course = try PracticeCourse(name: "Long CAFÉ course",waypointIDs: (0..<5_000).map { "point-\($0)" },startedAt: 100)
        _ = try course.markFound(runID: course.runID,checkpointID: "point-0",now: 200)
        _ = try course.markFound(runID: course.runID,checkpointID: "point-1",now: 500)
        try store.save(course)
        let bytes = try Data(contentsOf: file(root))
        let prepared = try await Task.detached { try PracticeCourseStore.prepareStartup(directory: root) }.value
        let reopened = try PracticeCourseStore(startup: prepared)
        XCTAssertEqual(reopened.active,course); XCTAssertNil(reopened.loadError)
        XCTAssertEqual(try Data(contentsOf: file(root)),bytes)
    }
    func testStartupRefusesCreatedReplacedAndRemovedSession() throws {
        let root = try directory(),missing = try PracticeCourseStore.prepareStartup(directory: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root).path))
        let store = PracticeCourseStore(directory: root)
        try store.save(PracticeCourse(name: "First",waypointIDs: ["a","b"],startedAt: 1))
        XCTAssertThrowsError(try PracticeCourseStore(startup: missing))
        let first = try PracticeCourseStore.prepareStartup(directory: root)
        try store.save(PracticeCourse(name: "Replacement",waypointIDs: ["c","d"],startedAt: 2))
        XCTAssertThrowsError(try PracticeCourseStore(startup: first))
        let replacement = try PracticeCourseStore.prepareStartup(directory: root)
        try FileManager.default.removeItem(at: file(root))
        XCTAssertThrowsError(try PracticeCourseStore(startup: replacement))
    }
    func testRecoveryStagesOffOwnerAndPublishesPreservedCopyBeforeReset() async throws {
        let root = try directory(),bytes = Data("SYNTHETIC corrupt CAFÉ course".utf8)
        try bytes.write(to: file(root))
        let startup = try await Task.detached { try PracticeCourseStore.prepareStartup(directory: root) }.value
        let store = try PracticeCourseStore(startup: startup)
        XCTAssertNotNil(store.loadError); XCTAssertThrowsError(try store.save(nil))
        let snapshot = try store.recoverySnapshot()
        let recovery = try await Task.detached { try snapshot.prepare() }.value
        XCTAssertNotNil(store.loadError); XCTAssertEqual(try Data(contentsOf: file(root)),bytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("practice-course-damaged-") })
        XCTAssertTrue(try store.publishRecovery(recovery))
        XCTAssertNil(store.loadError); XCTAssertNil(PracticeCourseStore(directory: root).active)
        let preserved = try FileManager.default.contentsOfDirectory(at: root,includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("practice-course-damaged-") }
        XCTAssertEqual(preserved.count,1); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved.first)),bytes)
        XCTAssertFalse(try store.publishRecovery(recovery))
    }
    func testLateRecoveryCannotEraseAReplacementSessionOrPublishAnArchive() throws {
        let root = try directory(),bytes = Data("damaged".utf8); try bytes.write(to: file(root))
        let damaged = PracticeCourseStore(directory: root),snapshot = try damaged.recoverySnapshot()
        let prepared = try snapshot.prepare()
        let replacement = try PracticeCourse(name: "Restored course",waypointIDs: ["a","b"],startedAt: 1)
        try FileManager.default.removeItem(at: file(root))
        try PracticeCourseStore(directory: root).save(replacement)
        let newest = try Data(contentsOf: file(root))
        XCTAssertThrowsError(try snapshot.prepare())
        XCTAssertThrowsError(try damaged.recoverySnapshot())
        XCTAssertThrowsError(try damaged.publishRecovery(prepared))
        XCTAssertEqual(try Data(contentsOf: file(root)),newest)
        XCTAssertEqual(PracticeCourseStore(directory: root).active,replacement)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("practice-course-damaged-") })
    }
    func testForeignAndCancelledRecoveryKeepOriginalFile() async throws {
        let root = try directory(),otherRoot = try directory(),bytes = Data("damaged".utf8)
        try bytes.write(to: file(root)); try bytes.write(to: file(otherRoot))
        let store = PracticeCourseStore(directory: root),other = PracticeCourseStore(directory: otherRoot)
        let snapshot = try store.recoverySnapshot(),prepared = try snapshot.prepare()
        defer { prepared.discard() }
        XCTAssertThrowsError(try other.publishRecovery(prepared))
        let gate = DispatchSemaphore(value: 0)
        let task = Task.detached { gate.wait(); return try snapshot.prepare() }
        task.cancel(); gate.signal()
        do { _ = try await task.value; XCTFail("Cancelled recovery must not publish") } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: file(root)),bytes); XCTAssertEqual(try Data(contentsOf: file(otherRoot)),bytes)
    }
}
