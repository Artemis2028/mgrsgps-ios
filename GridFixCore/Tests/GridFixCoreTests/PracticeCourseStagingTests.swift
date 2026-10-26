import XCTest
@testable import GridFixCore

final class PracticeCourseStagingTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    func testClearWaitsForDurabilityAndCannotClearReplacementRun() throws {
        let root = try directory(), store = PracticeCourseStore(directory: root)
        let first = try PracticeCourse(name: "First",waypointIDs: ["a","b"],startedAt: 1)
        try store.save(first)
        let clear = try store.saveSnapshot().prepare(nil)
        XCTAssertEqual(store.active,first); XCTAssertEqual(PracticeCourseStore(directory: root).active,first)
        let next = try PracticeCourse(name: "Next",waypointIDs: ["c","d"],startedAt: 2)
        try store.save(next)
        XCTAssertFalse(try store.publish(clear)); XCTAssertEqual(PracticeCourseStore(directory: root).active,next)
        XCTAssertTrue(try store.publish(store.saveSnapshot().prepare(nil)))
        XCTAssertNil(store.active); XCTAssertNil(PracticeCourseStore(directory: root).active)
    }
    func testFailedClearKeepsCompletedCourseAndCanRetry() throws {
        let root = try directory(), store = PracticeCourseStore(directory: root)
        var course = try PracticeCourse(name: "Complete",waypointIDs: ["a","b"],startedAt: 1)
        _ = try course.markFound(runID: course.runID,checkpointID: "a",now: 2)
        _ = try course.markFound(runID: course.runID,checkpointID: "b",now: 3)
        try store.save(course)
        let file = root.appendingPathComponent("practice-course-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publish(store.saveSnapshot().prepare(nil)))
        XCTAssertEqual(store.active,course)
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(try store.publish(store.saveSnapshot().prepare(nil)))
        XCTAssertNil(PracticeCourseStore(directory: root).active)
    }
    func testDamagedCourseAndForeignPreparationCannotOverwriteSessions() throws {
        let root = try directory(), other = PracticeCourseStore(directory: try directory())
        let foreign = try other.saveSnapshot().prepare(nil)
        let file = root.appendingPathComponent("practice-course-v1.json")
        try Data("damaged".utf8).write(to: file)
        let damaged = PracticeCourseStore(directory: root)
        XCTAssertThrowsError(try damaged.saveSnapshot().prepare(nil))
        XCTAssertThrowsError(try damaged.publish(foreign))
        XCTAssertEqual(try Data(contentsOf: file),Data("damaged".utf8))
    }
}
