import XCTest
@testable import GridFixCore

final class StreamingTrackTests: XCTestCase {
    private func source(_ bytes: Data,checksum: String? = nil) throws -> (SavedTrackSource,URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return (try SavedTrackSource(fileURL: file,sha256: checksum ?? FieldDataDisk.digest(bytes)),file)
    }
    func testEverySmallChunkSizePreservesUnicodeSeparatorsWhitespaceAndFinalRow() throws {
        let bytes = Data("\u{2003}\n24 179.9 0\r\n24.1 -179.9 12 -32768\u{85}\u{2028}24.2 179.8 25 4\u{2029} \t\n24.3 179.7 50".utf8)
        let expected = try TrackCodec.decodeLocal(bytes), (file,_) = try source(bytes)
        for size in 1...71 {
            var points: [TrackPoint] = []
            try file.visitPoints(chunkSize: size) { points.append($0) }
            XCTAssertEqual(points,expected,"chunk size \(size)")
            XCTAssertTrue(file.hasVerifiedBytes)
        }
    }
    func testLongRowIsScannedOnceAcrossChunksAndMalformedUTF8NeverDisappears() throws {
        var bytes = Data(String(repeating:" ",count:200_000).utf8)
        bytes.append(Data("24 54 0\n".utf8))
        let (file,_) = try source(bytes)
        var count = 0
        try file.visitPoints(chunkSize: 257) { _ in count += 1 }
        XCTAssertEqual(count,1)
        for bad in [Data([0xe2,0x80]),Data([0xc2]),Data([0xff,10])] {
            let (broken,_) = try source(bytes + bad)
            XCTAssertThrowsError(try broken.visitPoints(chunkSize: 1) { _ in })
            XCTAssertFalse(broken.hasVerifiedBytes)
        }
    }
    func testChecksumFailureAfterValidRowsCannotGrantCleanupAuthority() throws {
        let (file,_) = try source(Data("24 54 0\n24.1 54 1\n".utf8),checksum:String(repeating:"0",count:64))
        var count = 0
        XCTAssertThrowsError(try file.visitPoints { _ in count += 1 })
        XCTAssertEqual(count,2,"Derived results are provisional until stream verification completes")
        XCTAssertFalse(file.hasVerifiedBytes)
        XCTAssertThrowsError(try FieldMapGeometry.trackFitPoints(visit: file.visitPoints))
    }
    func testReplacementDuringVisitRefusesResultAndKeepsReplacement() throws {
        let bytes = Data("24 54 0\n24.1 54 1\n".utf8), (file,url) = try source(bytes)
        var replaced = false
        XCTAssertThrowsError(try file.visitPoints(chunkSize: 8) { _ in
            if !replaced { replaced = true; try Data("25 55 0\n".utf8).write(to: url,options:.atomic) }
        })
        XCTAssertFalse(file.hasVerifiedBytes)
        XCTAssertEqual(try Data(contentsOf:url),Data("25 55 0\n".utf8))
    }
    func testVisitorFailureRevokesPriorVerificationAndAllowsSuccessfulRetry() throws {
        let (file,_) = try source(Data("24 54 0\n".utf8))
        try file.visitPoints { _ in }
        XCTAssertTrue(file.hasVerifiedBytes)
        XCTAssertThrowsError(try file.visitPoints { _ in throw CancellationError() })
        XCTAssertFalse(file.hasVerifiedBytes)
        try file.visitPoints { _ in }
        XCTAssertTrue(file.hasVerifiedBytes)
    }
    func testCancellationDoesNotPublishPartialFitOrVerifySource() async throws {
        let (file,_) = try source(Data("24 54 0\n24.1 54 1\n".utf8))
        let worker = Task {
            try FieldMapGeometry.trackFitPoints { visit in
                try file.visitPoints { point in
                    withUnsafeCurrentTask { $0?.cancel() }
                    try visit(point)
                }
            }
        }
        do { _ = try await worker.value; XCTFail("Cancelled stream returned camera bounds") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(file.hasVerifiedBytes)
    }
    func testLongDeferredOverlayMatchesExactEagerStrideAndDatelineBounds() throws {
        var bytes = Data()
        for n in 0..<30_003 {
            let lat = n == 1234 ? -35.0 : n == 20001 ? 60.0 : 24.0
            bytes.append(Data("\(lat) \(n % 2 == 0 ? 179.9 : -179.8) \(n)\n".utf8))
        }
        let (file,_) = try source(bytes),id = UUID().uuidString.lowercased()
        var eager = Backup.Document()
        // Deliberately stale point count: preview stride must come from the log.
        eager.tracks = [.init(id:id,name:"Long patrol",startedAt:0,endedAt:0,distanceM:0,pointCount:2,folder:"Base")]
        eager.trackFiles[id] = bytes
        var deferred = eager; deferred.trackFiles = [:]; deferred.localTrackFiles[id] = file
        let a = try FieldMapGeometry.prepareOverlay(document:eager,folders:[])
        let b = try FieldMapGeometry.prepareOverlay(document:deferred,folders:[])
        XCTAssertEqual(a.points,b.points)
        XCTAssertEqual(try JSONSerialization.jsonObject(with:a.data) as? NSDictionary,
                       try JSONSerialization.jsonObject(with:b.data) as? NSDictionary)
        XCTAssertEqual(try FieldMapGeometry.trackFitPoints(visit:file.visitPoints),try FieldMapGeometry.trackFitPoints(bytes))
        let bounds = try XCTUnwrap(FieldMapGeometry.bounds(b.points))
        XCTAssertEqual(bounds.south,-35); XCTAssertEqual(bounds.north,60)
        XCTAssertLessThan(bounds.east-bounds.west,1)
        XCTAssertTrue(file.hasVerifiedBytes)
    }
    func testStreamedBacktrackMatchesExactAndroidSimplificationAndRejectsBadTail() throws {
        let points = (0..<5000).map { n in TrackPoint(lat:24+Double(n)/100_000,lon:54+sin(Double(n)/30)/1000,time:Int64(n)) }
        let (track,bytes) = try TrackCodec.imported(name:"Patrol",points:points,now:1)
        let (file,_) = try source(bytes)
        let a = try TrackBacktrack.route(track:track,data:bytes,now:5)
        let b = try TrackBacktrack.route(track:track,visit:file.visitPoints,now:5)
        XCTAssertEqual(a.points,b.points); XCTAssertEqual(a.name,b.name); XCTAssertEqual(a.folder,b.folder)
        let (bad,_) = try source(bytes + Data("91 54 1\n".utf8))
        XCTAssertThrowsError(try TrackBacktrack.route(track:track,visit:bad.visitPoints))
        XCTAssertFalse(bad.hasVerifiedBytes)
    }
}
