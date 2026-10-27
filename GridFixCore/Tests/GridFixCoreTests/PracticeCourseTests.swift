import XCTest
@testable import GridFixCore

final class PracticeCourseTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    func testAndroidMissingFutureCheckpointPauseRestoreAndTimedSplits() throws {
        var course = try PracticeCourse(name: "Practice",waypointIDs: ["a","b","c"],startedAt: 100)
        XCTAssertTrue(try course.markFound(runID: course.runID,checkpointID: "a",now: 200))
        course.reconcile(availableIDs: ["a","b"])
        XCTAssertTrue(course.paused); XCTAssertEqual(course.missingIDs,["c"]); XCTAssertNil(course.targetID)
        XCTAssertFalse(try course.markFound(runID: course.runID,checkpointID: "b",now: 300)); XCTAssertNil(course.result)
        let dir = try directory(), saved = PracticeCourseStore(directory: dir); try saved.save(course)
        course = try XCTUnwrap(PracticeCourseStore(directory: dir).active)
        course.reconcile(availableIDs: ["b","c"])
        XCTAssertFalse(course.paused); XCTAssertEqual(course.targetID,"b")
        XCTAssertTrue(try course.markFound(runID: course.runID,checkpointID: "b",now: 800))
        XCTAssertTrue(try course.markFound(runID: course.runID,checkpointID: "c",now: 900))
        XCTAssertEqual(course.result?.total,800); XCTAssertEqual(course.result?.splits,[100,600,100])
    }
    func testStaleCallbacksCannotSkipDoubleScoreOrAdvanceReplacementRun() throws {
        var course = try PracticeCourse(name: "Practice",waypointIDs: ["a","b"],startedAt: 100)
        let old = try PracticeCourse(name: "Practice",waypointIDs: ["a","b"],startedAt: 100)
        XCTAssertFalse(try course.markFound(runID: old.runID,checkpointID: "a",now: 200))
        XCTAssertFalse(try course.markFound(runID: course.runID,checkpointID: "b",now: 200))
        XCTAssertTrue(try course.markFound(runID: course.runID,checkpointID: "a",now: 200))
        XCTAssertFalse(try course.markFound(runID: course.runID,checkpointID: "a",now: 201))
        XCTAssertThrowsError(try course.markFound(runID: course.runID,checkpointID: "b",now: 199))
        XCTAssertEqual(course.foundAt,[200])
    }
    func testMaximumCourseMissingCheckpointsPersistAndRestoreWithoutRescoringCompletedPoint() throws {
        let ids = (0..<10_000).map { "checkpoint-\($0)" }
        var course = try PracticeCourse(name: "Full course",waypointIDs: ids,startedAt: 100)
        XCTAssertTrue(try course.markFound(runID: course.runID,checkpointID: ids[0],now: 200))
        course.reconcile(availableIDs: [])
        XCTAssertTrue(course.valid); XCTAssertTrue(course.paused); XCTAssertNil(course.targetID)
        XCTAssertEqual(course.missingIDs,Array(ids.dropFirst()))
        let positions = (2...10_000).map(String.init).joined(separator: ", ")
        XCTAssertEqual(course.pauseReason,"Missing checkpoints \(positions). Restore the same checkpoint IDs or end the course. Elapsed time continues.")
        XCTAssertFalse(try course.markFound(runID: course.runID,checkpointID: ids[1],now: 300))
        let dir = try directory(), saved = PracticeCourseStore(directory: dir)
        try saved.save(course)
        course = try XCTUnwrap(PracticeCourseStore(directory: dir).active)
        XCTAssertEqual(course.foundAt,[200]); XCTAssertEqual(course.missingIDs,Array(ids.dropFirst()))
        course.reconcile(availableIDs: Set(ids.dropFirst()))
        XCTAssertTrue(course.valid); XCTAssertFalse(course.paused); XCTAssertNil(course.pauseReason)
        XCTAssertEqual(course.targetID,ids[1])
        XCTAssertTrue(try course.markFound(runID: course.runID,checkpointID: ids[1],now: 800))
        XCTAssertEqual(course.foundAt,[200,800]); XCTAssertEqual(course.targetID,ids[2])
    }
    func testInvalidMissingCheckpointListsKeepOriginalSavedBytes() throws {
        var course = try PracticeCourse(name: "Practice",waypointIDs: ["a","b","c"],startedAt: 100)
        XCTAssertTrue(try course.markFound(runID: course.runID,checkpointID: "a",now: 200))
        course.reconcile(availableIDs: [])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(course)) as? [String:Any])
        for missing in [["b","b"],["c","b"],["a","b","c"],["b","unknown"]] {
            var invalid = original; invalid["missingIDs"] = missing
            let bytes = try JSONSerialization.data(withJSONObject: ["version":1,"active":invalid],options: [.sortedKeys])
            let dir = try directory(), path = dir.appendingPathComponent("practice-course-v1.json")
            try bytes.write(to: path)
            let saved = PracticeCourseStore(directory: dir)
            XCTAssertNotNil(saved.loadError,"\(missing)"); XCTAssertNil(saved.active)
            XCTAssertThrowsError(try saved.save(nil)); XCTAssertEqual(try Data(contentsOf: path),bytes)
        }
    }
    func testUncertaintyThresholdStrictAndMissingAccuracyCannotScore() {
        XCTAssertTrue(PracticeCourse.canScore(distance: 19.99,accuracy: 5))
        XCTAssertFalse(PracticeCourse.canScore(distance: 20,accuracy: 5))
        for accuracy in [-1,26,Double.nan,Double.infinity] { XCTAssertFalse(PracticeCourse.canScore(distance: 0,accuracy: accuracy)) }
        XCTAssertFalse(PracticeCourse.canScore(distance: .nan,accuracy: 1))
    }
    func testMalformedPersistedProgressIsPreservedAndResetKeepsCopy() throws {
        let dir = try directory(), path = dir.appendingPathComponent("practice-course-v1.json")
        let bytes = Data("damaged".utf8); try bytes.write(to: path)
        let saved = PracticeCourseStore(directory: dir); XCTAssertNotNil(saved.loadError)
        XCTAssertThrowsError(try saved.save(nil)); XCTAssertEqual(try Data(contentsOf: path),bytes)
        try saved.preserveDamagedAndReset(); XCTAssertNil(saved.loadError)
        let kept = try FileManager.default.contentsOfDirectory(at: dir,includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("practice-course-damaged-") }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(kept)),bytes)
        XCTAssertNil(PracticeCourseStore(directory: dir).active)
    }
    func testWriteFailureDoesNotPublishNewRunOrEraseOldProgress() throws {
        let dir = try directory(), saved = PracticeCourseStore(directory: dir)
        let old = try PracticeCourse(name: "Old",waypointIDs: ["a","b"],startedAt: 100); try saved.save(old)
        let path = dir.appendingPathComponent("practice-course-v1.json")
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        XCTAssertThrowsError(try saved.save(nil)); XCTAssertEqual(saved.active,old)
    }
    func testRandomScatterMatchesBoundsSeparationAndFailureCreatesNoFolder() throws {
        var seed: UInt64 = 42
        let points = try PracticeCourseGenerator.scatter(origin: .init(lat: 24,lon: 179.999),count: 8,radius: 500) {
            seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 11)/Double(UInt64(1)<<53)
        }
        XCTAssertEqual(points.count,8)
        for (i,p) in points.enumerated() {
            XCTAssertTrue(TrackCodec.validCoordinates(p.lat,p.lon))
            let fromOrigin = Geodesy.greatCircleMeters(24,179.999,p.lat,p.lon)
            XCTAssertGreaterThan(fromOrigin,119); XCTAssertLessThan(fromOrigin,501)
            for q in points.prefix(i) { XCTAssertGreaterThan(Geodesy.navInfo(fromLat: p.lat,fromLon: p.lon,toLat: q.lat,toLon: q.lon).distanceMeters,120) }
        }
        XCTAssertThrowsError(try PracticeCourseGenerator.scatter(origin: .init(lat: 24,lon: 54),count: 8,radius: 500,random: { 0 }))
    }
    func testNavigationGateCoversSelectionAndCanClearWhilePaused() throws {
        let store = WaypointStore(directory: try directory())
        let a = store.add(.init(name: "A",lat: 0,lon: 0)), b = store.add(.init(name: "B",lat: 0,lon: 1))
        try store.setPracticeNavigationTarget(a.id,locked: true)
        store.select(b.id); XCTAssertEqual(store.selectedId,a.id)
        store.select(nil); XCTAssertEqual(store.selectedId,a.id)
        try store.setPracticeNavigationTarget(nil,locked: true)
        store.select(b.id); XCTAssertNil(store.selectedId)
        try store.setPracticeNavigationTarget(nil,locked: false)
        store.select(b.id); XCTAssertEqual(store.selectedId,b.id)
    }
    func testSelectionPersistenceFailureKeepsCourseGateClosedAndRetries() throws {
        let dir = try directory(), store = WaypointStore(directory: dir)
        let a = store.add(.init(name: "A",lat: 0,lon: 0)), b = store.add(.init(name: "B",lat: 0,lon: 1))
        let path = dir.appendingPathComponent("waypoints-v1.json"), before = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.setPracticeNavigationTarget(a.id,locked: true))
        XCTAssertTrue(store.practiceNavigationLocked); store.select(b.id); XCTAssertEqual(store.selectedId,a.id)
        XCTAssertThrowsError(try store.setPracticeNavigationTarget(a.id,locked: true))
        try FileManager.default.removeItem(at: path); try before.write(to: path)
        try store.setPracticeNavigationTarget(a.id,locked: true)
        XCTAssertEqual(WaypointStore(directory: dir).selectedId,a.id)
    }
    func testHistoryTieOrderingUsesAndroidUTF16Names() throws {
        let store = FieldDataStore(directory: try directory())
        var document = Backup.Document(); document.hasSettings = false
        document.courseHistory = ["\u{E000}","😀"].map { .init(name: $0,points: 2,started: 100,total: 200,splits: [100,100]) }
        _ = try store.restore(document)
        XCTAssertEqual(store.document.courseHistory.map(\.name),["😀","\u{E000}"])
    }
    func testInvalidCourseAndTimeFormatting() throws {
        let invalid = Data("{\"runID\":\"bad\",\"name\":\"Bad\",\"waypointIDs\":[],\"startedAt\":0,\"foundAt\":[],\"missingIDs\":[]}".utf8)
        let decoded = try JSONDecoder().decode(PracticeCourse.self,from: invalid)
        XCTAssertFalse(decoded.valid); XCTAssertNil(decoded.result); XCTAssertNil(decoded.targetID)
        XCTAssertThrowsError(try PracticeCourse(name: "No",waypointIDs: ["a","a"],startedAt: 100))
        XCTAssertEqual(PracticeCourse.time(3_661_999),"1:01:01"); XCTAssertEqual(PracticeCourse.time(-1000),"0:00")
    }
}
