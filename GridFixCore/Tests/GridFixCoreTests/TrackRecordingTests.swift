import XCTest
@testable import GridFixCore

final class TrackRecordingTests: XCTestCase {
    func testLongInterruptedLogFinalizesSavesAndReopensBeyondBackupLimits() throws {
        let dir = try directory(),j = try journal(dir)
        let id = try XCTUnwrap(j.summary?.id),count = 300_001
        let bytes = Data(String(repeating: "24.0000000 54.0000000 1700000000000 12345.678901234567890\n",count: count).utf8)
        XCTAssertGreaterThan(bytes.count,16 * 1024 * 1024)
        let file = dir.appendingPathComponent("LiveRecording/points.txt")
        try bytes.write(to: file)
        let recovered = try TrackRecordingJournal(directory: dir)
        let document = try XCTUnwrap(recovered.finish(now: start+1000))
        XCTAssertEqual(document.tracks.first?.pointCount,count)
        XCTAssertEqual(document.tracks.first?.distanceM,0)
        XCTAssertEqual(document.trackFiles[id],bytes)
        XCTAssertThrowsError(try Backup.exportZip(document),"External backup bounds remain independent")
        let store = FieldDataStore(directory: dir)
        try store.saveRecordedTrack(document); try recovered.clear()
        let reopened = FieldDataStore(directory: dir)
        XCTAssertNil(reopened.loadError); XCTAssertEqual(reopened.document.tracks.first?.pointCount,count)
        XCTAssertEqual(reopened.document.trackFiles[id],bytes)
        XCTAssertEqual(try reopened.points(for: id).count,count)
        try reopened.moveTrack(id,to: "Long patrols")
        XCTAssertEqual(FieldDataStore(directory: dir).document.tracks.first?.folder,"Long patrols")
    }
    func testLocalSummaryChecksEveryRowAndMatchesCanonicalDistanceWithoutBackupCap() throws {
        let points: [TrackPoint] = [.init(lat: 24,lon: 54,time: 1000),.init(lat: 24.001,lon: 54,time: 2000,altitudeMeters: 12)]
        let data = try TrackCodec.encode(points)
        let summary = try TrackCodec.summarizeLocal(data)
        XCTAssertEqual(summary.count,points.count); XCTAssertEqual(summary.last,points.last)
        XCTAssertEqual(summary.distanceM,TrackCodec.distance(points),accuracy: 0.00001)
        XCTAssertEqual(try TrackCodec.decodeLocal(data),points)
        XCTAssertEqual(try TrackCodec.summarizeLocal(Data()).count,0)
        XCTAssertEqual(try TrackCodec.decodeLocal(Data(" \r\n24 54 1000\r24.001 54 2000 12\n".utf8)),points)
        for newline in ["\n","\r\n","\r","\u{000b}","\u{000c}","\u{0085}","\u{2028}","\u{2029}"] {
            let legacy = Data(("24 54 1000"+newline+"24.001 54 2000 12"+newline).utf8)
            XCTAssertEqual(try TrackCodec.decodeLocal(legacy),try TrackCodec.decode(legacy))
        }
        let long = Data(String(repeating: "24 54 0\n",count: 250_001).utf8)
        XCTAssertEqual(try TrackCodec.summarizeLocal(long).count,250_001)
        XCTAssertThrowsError(try TrackCodec.decode(long))
        for bad in [Data("not a point\n".utf8),Data([0xff,10]),Data("91 0 0\n".utf8),Data("0 0 -1\n".utf8)] {
            XCTAssertThrowsError(try TrackCodec.summarizeLocal(long+bad),"Invalid trailing rows must never be skipped")
        }
    }
    private let start: Int64 = 1_700_000_000_000
    private func directory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return path
    }
    private func sample(meters: Double, seconds: Double, accuracy: Double = 5, altitude: Double? = nil) -> RecordingSample {
        let point = GeoPoint(lat: 24 + meters / 110_760, lon: 54)
        return RecordingSample(point: .init(lat: point.lat, lon: point.lon, time: start + Int64(seconds * 1000), altitudeMeters: altitude),
                               accuracyMeters: accuracy, uptime: 100 + seconds)
    }
    private func journal(_ directory: URL) throws -> TrackRecordingJournal {
        let journal = try TrackRecordingJournal(directory: directory)
        try journal.start(now: start, uptime: 100)
        return journal
    }

    func testAndroidAccuracySpacingAndSlowMovementThresholds() throws {
        let j = try journal(directory())
        XCTAssertNil(try j.append(sample(meters: 0, seconds: 0, accuracy: 30.01)))
        XCTAssertNil(try j.append(sample(meters: 0, seconds: 0, accuracy: -1)))
        XCTAssertNil(try j.append(sample(meters: 0, seconds: 0, accuracy: .nan)))
        XCTAssertEqual(try j.append(sample(meters: 0, seconds: 0, accuracy: 30))?.pointCount, 1)
        XCTAssertNil(try j.append(sample(meters: 4.9, seconds: 1)))
        XCTAssertNil(try j.append(sample(meters: 1.1, seconds: 15)))
        XCTAssertNil(try j.append(sample(meters: 0.9, seconds: 16)))
        XCTAssertEqual(try j.append(sample(meters: 1.1, seconds: 16))?.pointCount, 2)
        XCTAssertEqual(try j.append(sample(meters: 6.2, seconds: 17))?.pointCount, 3)
        XCTAssertEqual(j.summary!.distanceM, 6.2, accuracy: 0.02)
    }

    func testRejectedSamplesNeverBecomeFilterAnchorAndTimesMustAdvance() throws {
        let j = try journal(directory())
        XCTAssertNil(try j.append(sample(meters: 0, seconds: -1)))
        _ = try j.append(sample(meters: 0, seconds: 0))
        XCTAssertNil(try j.append(sample(meters: 10, seconds: 0)))
        XCTAssertNil(try j.append(sample(meters: 10, seconds: -1)))
        XCTAssertNil(try j.append(sample(meters: 4, seconds: 1)))
        XCTAssertEqual(try j.append(sample(meters: 5.1, seconds: 2))?.pointCount, 2)
        let doc = try XCTUnwrap(j.finish(now: start + 5000))
        let points = try TrackCodec.decode(doc.trackFiles.values.first!)
        XCTAssertEqual(points.count, 2)
        XCTAssertNil(try j.append(sample(meters: 20, seconds: 6)), "Callbacks after Stop cannot append")
    }

    func testEachAcceptedPointIsOnDiskAndRecoveredWithoutExplicitStop() throws {
        let dir = try directory(), j = try journal(dir)
        let id = try XCTUnwrap(j.summary?.id)
        _ = try j.append(sample(meters: 0, seconds: 0, altitude: 12.5))
        _ = try j.append(sample(meters: 10, seconds: 2))
        let bytes = try Data(contentsOf: dir.appendingPathComponent("LiveRecording/points.txt"))
        XCTAssertEqual(try TrackCodec.decode(bytes).count, 2)
        let reopened = try TrackRecordingJournal(directory: dir)
        XCTAssertFalse(reopened.isRecording)
        XCTAssertNil(try reopened.append(sample(meters: 20, seconds: 4)))
        let doc = try XCTUnwrap(reopened.finish(now: start + 10_000))
        XCTAssertEqual(doc.tracks.first?.id, id)
        XCTAssertEqual(doc.tracks.first?.pointCount, 2)
        XCTAssertEqual(doc.tracks.first!.distanceM, 10, accuracy: 0.02)
        XCTAssertEqual(try TrackCodec.decode(doc.trackFiles[id]!).first?.altitudeMeters, 12.5)
        XCTAssertNil(try TrackCodec.decode(doc.trackFiles[id]!).last?.altitudeMeters)
    }

    func testRecoveryDropsOnlyIncompleteTailAndRejectsMalformedCompleteRows() throws {
        let dir = try directory(), j = try journal(dir)
        _ = try j.append(sample(meters: 0, seconds: 0))
        let file = dir.appendingPathComponent("LiveRecording/points.txt")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("24.000".utf8)); try handle.close()
        let reopened = try TrackRecordingJournal(directory: dir)
        XCTAssertEqual(try reopened.finish(now: start + 1000)?.tracks.first?.pointCount, 1)
        let original = try Data(contentsOf: file)
        try (original + Data("not a point\n".utf8)).write(to: file)
        XCTAssertThrowsError(try TrackRecordingJournal(directory: dir).finish(now: start + 1000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAppendFailureStopsQueuedWritesWithoutPublishingUnsavedDistance() throws {
        let dir = try directory(), j = try journal(dir)
        _ = try j.append(sample(meters: 0, seconds: 0))
        let previous = j.summary
        let file = dir.appendingPathComponent("LiveRecording/points.txt")
        let saved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        XCTAssertThrowsError(try j.append(sample(meters: 10, seconds: 2)))
        XCTAssertFalse(j.isRecording)
        XCTAssertEqual(j.summary, previous)
        XCTAssertNil(try j.append(sample(meters: 20, seconds: 3)))
        try FileManager.default.removeItem(at: file); try saved.write(to: file)
        XCTAssertEqual(try j.finish(now: start + 10_000)?.tracks.first?.pointCount, 1)
    }

    func testFinishedPublicationIsIdempotentAndJournalSurvivesFailedArchiveWrite() throws {
        let dir = try directory(), j = try journal(dir), store = FieldDataStore(directory: dir)
        _ = try j.append(sample(meters: 0, seconds: 0))
        let doc = try XCTUnwrap(j.finish(now: start + 1000, name: "  Patrol  "))
        let blocked = dir.appendingPathComponent("field-data-v2.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.saveRecordedTrack(doc))
        XCTAssertTrue(store.document.tracks.isEmpty)
        XCTAssertTrue(try TrackRecordingJournal(directory: dir).hasPendingSession)
        try FileManager.default.removeItem(at: blocked)
        try store.saveRecordedTrack(doc)
        // Simulate process death after archive publication but before cleanup.
        let retry = try XCTUnwrap(TrackRecordingJournal(directory: dir).finish(now: start + 5000))
        try store.saveRecordedTrack(retry)
        XCTAssertEqual(store.document.tracks.count, 1)
        XCTAssertEqual(store.document.tracks.first?.name, "Patrol")
        XCTAssertEqual(store.document.tracks.first?.endedAt, start + 1000)
        try j.clear()
        XCTAssertFalse(try TrackRecordingJournal(directory: dir).hasPendingSession)
        XCTAssertEqual(FieldDataStore(directory: dir).document.tracks.count, 1)
    }

    func testConflictingTrackIdNeverDestroysRecoveryJournal() throws {
        let dir = try directory(), j = try journal(dir), store = FieldDataStore(directory: dir)
        _ = try j.append(sample(meters: 0, seconds: 0))
        let doc = try XCTUnwrap(j.finish(now: start + 1000))
        var other = doc
        other.trackFiles[doc.tracks[0].id] = try TrackCodec.encode([TrackPoint(lat: 25, lon: 55)])
        try store.saveRecordedTrack(other)
        XCTAssertThrowsError(try store.saveRecordedTrack(doc))
        XCTAssertTrue(try TrackRecordingJournal(directory: dir).hasPendingSession)
    }

    func testStagedFinalizationRebasesWithoutLosingConcurrentEditsOrNewerTrackMetadata() throws {
        let dir = try directory(), j = try journal(dir), store = FieldDataStore(directory: dir)
        _ = try j.append(sample(meters: 0,seconds: 0))
        let recording = try XCTUnwrap(j.finish(now: start+1000,name: "Patrol"))
        let edit = FieldDataStore.Edit.saveRecordedTrack(recording)
        let stale = try store.restoreSnapshot().prepare(edit: edit)
        XCTAssertTrue(store.document.tracks.isEmpty)
        XCTAssertTrue(FieldDataStore(directory: dir).document.tracks.isEmpty)
        try store.saveGraphic(.init(id: "concurrent",name: "Concurrent line",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 25,lon: 55)]))
        XCTAssertFalse(try store.publishEdit(stale))
        XCTAssertTrue(try store.publishEdit(store.restoreSnapshot().prepare(edit: edit)))
        XCTAssertEqual(store.document.graphics.count,1); XCTAssertEqual(store.document.tracks.count,1)
        let id = recording.tracks[0].id
        try store.setTrackVisible(id,visible: false); try store.moveTrack(id,to: "Later folder")
        XCTAssertTrue(try store.publishEdit(store.restoreSnapshot().prepare(edit: edit)))
        XCTAssertFalse(store.document.tracks[0].visible); XCTAssertEqual(store.document.tracks[0].folder,"Later folder")
        XCTAssertEqual(store.document.trackFiles[id],recording.trackFiles[id])
        XCTAssertTrue(try TrackRecordingJournal(directory: dir).hasPendingSession,"Only the recorder may acknowledge its journal")
    }

    func testStagedFailureAndCollisionKeepPendingJournalAndExistingArchive() throws {
        let dir = try directory(), j = try journal(dir), store = FieldDataStore(directory: dir)
        _ = try j.append(sample(meters: 0,seconds: 0))
        let recording = try XCTUnwrap(j.finish(now: start+1000))
        let path = dir.appendingPathComponent("field-data-v2.json")
        try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publishEdit(store.restoreSnapshot().prepare(edit: .saveRecordedTrack(recording))))
        XCTAssertTrue(store.document.tracks.isEmpty); XCTAssertTrue(j.hasPendingSession)
        try FileManager.default.removeItem(at: path)
        XCTAssertTrue(try store.publishEdit(store.restoreSnapshot().prepare(edit: .saveRecordedTrack(recording))))
        let archived = try Data(contentsOf: path)
        var collision = recording
        collision.trackFiles[recording.tracks[0].id] = try TrackCodec.encode([TrackPoint(lat: 25,lon: 55)])
        XCTAssertThrowsError(try store.restoreSnapshot().prepare(edit: .saveRecordedTrack(collision)))
        XCTAssertEqual(try Data(contentsOf: path),archived); XCTAssertTrue(j.hasPendingSession)
    }

    func testEmptyRecordingAndDiscardDoNotCreateSavedTracks() throws {
        let dir = try directory(), j = try journal(dir)
        XCTAssertNil(try j.finish(now: start + 1000, discardEmpty: true))
        try j.clear()
        try j.start(now: start + 2000, uptime: 102)
        _ = try j.append(sample(meters: 0, seconds: 2))
        try j.clear()
        XCTAssertFalse(try TrackRecordingJournal(directory: dir).hasPendingSession)
        try j.start(now: start + 3000, uptime: 103)
        XCTAssertEqual(try j.finish(now: start + 4000)?.tracks.first?.pointCount, 0, "An explicit empty save matches Android; only an empty orphan is discarded")
    }

    func testWallClockAdjustmentDoesNotReplaceMonotonicFiltering() throws {
        let j = try journal(directory())
        _ = try j.append(sample(meters: 0, seconds: 0))
        let changed = RecordingSample(point: .init(lat: 24.0001, lon: 54, time: start - 10_000), accuracyMeters: 5, uptime: 105)
        XCTAssertEqual(try j.append(changed)?.pointCount, 2)
        let doc = try XCTUnwrap(j.finish(now: start + 10_000))
        XCTAssertEqual(try TrackCodec.decode(doc.trackFiles.values.first!).last?.time, start - 10_000)
    }

    func testLivePreviewIsBoundedWithoutDroppingDurablePoints() throws {
        let j = try journal(directory())
        for index in 0..<4002 { _ = try j.append(sample(meters: Double(index) * 6, seconds: Double(index))) }
        XCTAssertEqual(j.summary?.pointCount, 4002)
        XCTAssertEqual(j.summary?.livePoints.count, 2001)
        XCTAssertEqual(try j.finish(now: start + 5_000_000)?.tracks.first?.pointCount, 4002)
    }
}
