import XCTest
@testable import GridFixCore

final class GPXStreamingTests: XCTestCase {
    func testExactCompatibilityBytesRetainMetadataEscapingRoutesAndTracks() throws {
        var waypoint = Waypoint(name:"CAFÉ <&> \"'",lat:-12.1234567,lon:179.9999999)
        waypoint.metadata.elevationMeters = -42.5; waypoint.metadata.timestampMillis = 1234567890
        waypoint.metadata.color = "#aabbcc"; waypoint.metadata.milgpsSymbolCode = 7
        let route = Backup.Graphic(id:"r",name:"Route & <1>",type:"route",points:[.init(lat:1,lon:2),.init(lat:3,lon:4)])
        let ignored = Backup.Graphic(id:"g",name:"Local area",type:"area",points:route.points)
        let points = [TrackPoint(lat:1,lon:2,time:0),TrackPoint(lat:3,lon:4,time:1234567890,altitudeMeters:12.75)]
        let tracks = [GPX.Track(name:"CAFÉ & patrol",points:points),GPX.Track(name:"Empty",points:[])]
        var bytes = Data()
        let streams = tracks.map { track in GPX.TrackStream(name:track.name) { visit in for p in track.points { try visit(p) } } }
        try GPX.write(waypoints:[waypoint],routes:[route,ignored],tracks:streams) { bytes.append($0) }
        XCTAssertEqual(bytes,Data(GPX.build(waypoints:[waypoint],routes:[route,ignored],tracks:tracks).utf8))
        let parsed = try GPX.parse(String(decoding:bytes,as:UTF8.self),now:1)
        XCTAssertEqual(parsed.waypoints.first?.name,waypoint.name)
        XCTAssertEqual(parsed.waypoints.first?.metadata,waypoint.metadata)
        XCTAssertEqual(parsed.graphics.first?.name,route.name)
    }
    func testCompleteLongTrackWritesBeyondImportBudgetsWithoutRetainingAPointArray() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".gpx")
        FileManager.default.createFile(atPath:file.path,contents:nil)
        defer { try? FileManager.default.removeItem(at:file) }
        let handle = try FileHandle(forWritingTo:file)
        var generated = 0,writes = 0,maxChunk = 0
        let track = GPX.TrackStream(name:"Long CAFÉ & patrol") { visit in
            for i in 0..<300_003 { try visit(.init(lat:i == 300_002 ? 60 : 24,lon:i == 0 ? 179.9 : -179.8,time:Int64(i+1)*1000,altitudeMeters:12.75)) }
        }
        // Count via output parsing, never via the untrusted saved summary.
        try GPX.write(waypoints:[],tracks:[track]) { bytes in
            writes += 1; maxChunk = max(maxChunk,bytes.count); try handle.write(contentsOf:bytes)
        }
        try handle.close()
        let parser = try XCTUnwrap(XMLParser(contentsOf:file)),counter = StreamingGPXCounter()
        parser.delegate = counter
        XCTAssertTrue(parser.parse(),String(describing:parser.parserError)); generated = counter.points
        XCTAssertEqual(generated,300_003); XCTAssertEqual(counter.elevations,300_003); XCTAssertEqual(counter.times,300_003)
        XCTAssertEqual(counter.firstLon,179.9); XCTAssertEqual(counter.lastLat,60)
        XCTAssertGreaterThan(writes,100); XCTAssertLessThan(maxChunk,65 * 1024)
        let size = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(size,TrackCodec.interchangeByteLimit)
        print("[gpx-stream] 300003 complete points; bytes \(size); writes \(writes); largest chunk \(maxChunk)")
    }
    func testSinkFailureStopsVisitingAndPropagatesWriteError() throws {
        enum Failure: Error { case full }
        let visited = GPXVisitCounter()
        let track = GPX.TrackStream(name:"Patrol") { point in
            for _ in 0..<10_000 { visited.increment(); try point(.init(lat:24,lon:54)) }
        }
        XCTAssertThrowsError(try GPX.write(waypoints:[],tracks:[track]) { _ in throw Failure.full }) { XCTAssertTrue($0 is Failure) }
        XCTAssertLessThan(visited.value,10_000)
    }
    func testLateSourceFailureNeverReturnsACompleteDocument() throws {
        enum Failure: Error { case checksum }
        var bytes = Data()
        let track = GPX.TrackStream(name:"Unverified") { point in
            for _ in 0..<5000 { try point(.init(lat:24,lon:54)) }
            throw Failure.checksum
        }
        XCTAssertThrowsError(try GPX.write(waypoints:[],tracks:[track]) { bytes.append($0) }) { XCTAssertTrue($0 is Failure) }
        XCTAssertFalse(bytes.isEmpty); XCTAssertFalse(String(decoding:bytes,as:UTF8.self).hasSuffix("</gpx>\n"))
    }
    func testCancellationDuringWritingThrowsInsteadOfFinishingTheFile() async throws {
        let task = Task {
            let track = GPX.TrackStream(name:"Cancel") { point in
                for _ in 0..<10_000 { try point(.init(lat:24,lon:54)) }
            }
            try GPX.write(waypoints:[],tracks:[track]) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        do { try await task.value; XCTFail("Cancelled export completed") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

private final class StreamingGPXCounter: NSObject,XMLParserDelegate {
    var points = 0,elevations = 0,times = 0
    var firstLon: Double?,lastLat: Double?
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        if name == "trkpt" { if points == 0 { firstLon = Double(attributes["lon"] ?? "") }; lastLat = Double(attributes["lat"] ?? "");points += 1 }
        if name == "ele" { elevations += 1 }; if name == "time" { times += 1 }
    }
}

private final class GPXVisitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
