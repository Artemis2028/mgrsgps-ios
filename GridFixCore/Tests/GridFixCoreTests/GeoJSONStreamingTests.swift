import XCTest
@testable import GridFixCore

final class GeoJSONStreamingTests: XCTestCase {
    func testCompleteFeatureSemanticsMatchEagerExportIncludingSkippedShortTracks() throws {
        var waypoint = Waypoint(name:"CAFÉ <&> \"\\\n",lat:-0.00000005,lon:179.123456789,folder:"Recon")
        waypoint.metadata.elevationMeters = 42.5; waypoint.metadata.color = "#aabbcc"
        let vertices = [Backup.GraphicPoint(lat:1,lon:2),.init(lat:3,lon:4),.init(lat:5,lon:6)]
        let graphics = [Backup.Graphic(id:"a",name:"Area &1",type:"area",points:vertices),Backup.Graphic(id:"r",name:"Route",type:"route",points:vertices),Backup.Graphic(id:"t",name:"Label",type:"text",points:[vertices[0]])]
        let tracks = [GPX.Track(name:"Track \"\\\n café",points:[.init(lat:1.123456789,lon:-179.123456789),.init(lat:3,lon:4)]),GPX.Track(name:"Empty",points:[]),GPX.Track(name:"One",points:[.init(lat:5,lon:6)])]
        let streams = tracks.map { track in GPX.TrackStream(name:track.name) { visit in for point in track.points { try visit(point) } } }
        var bytes = Data()
        try GeoJSON.write(waypoints:[waypoint],graphics:graphics,tracks:streams) { bytes.append($0) }
        let actual = try JSONSerialization.jsonObject(with:bytes) as? NSDictionary
        let eager = try JSONSerialization.jsonObject(with:Data(GeoJSON.build(waypoints:[waypoint],graphics:graphics,tracks:tracks).utf8)) as? NSDictionary
        XCTAssertEqual(actual,eager)
        let features = try XCTUnwrap(actual?["features"] as? [[String:Any]])
        XCTAssertEqual(features.count,5)
        XCTAssertEqual((features[0]["properties"] as? [String:Any])?["name"] as? String,waypoint.name)
    }
    func testLongTrackWritesAllCoordinatesWithoutImportCeilings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".geojson")
        FileManager.default.createFile(atPath:url.path,contents:nil)
        defer { try? FileManager.default.removeItem(at:url) }
        let handle = try FileHandle(forWritingTo:url)
        var writes = 0,largest = 0
        let track = GPX.TrackStream(name:"Long") { visit in
            for i in 0..<300_003 { try visit(.init(lat:i == 300_002 ? 60 : 24.123456789,lon:i == 0 ? 179.9 : -179.123456789)) }
        }
        try GeoJSON.write(waypoints:[],graphics:[],tracks:[track]) { bytes in writes += 1; largest = max(largest,bytes.count); try handle.write(contentsOf:bytes) }
        try handle.close()
        // The validator may own the parsed output; the production writer above
        // generates/visits points without ever constructing this array.
        let stream = try XCTUnwrap(InputStream(url:url)); stream.open(); defer { stream.close() }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:stream) as? [String:Any])
        let features = try XCTUnwrap(root["features"] as? [[String:Any]])
        let geometry = try XCTUnwrap(features.first?["geometry"] as? [String:Any])
        let points = try XCTUnwrap(geometry["coordinates"] as? [[Double]])
        XCTAssertEqual(points.count,300_003); XCTAssertEqual(points.first,[179.9,24.1234568]); XCTAssertEqual(points.last,[-179.1234568,60])
        XCTAssertGreaterThan(writes,100); XCTAssertLessThan(largest,65*1024)
    }
    func testLateValidationFailureCannotCompleteCollectionEvenForShortTrack() throws {
        enum Failure: Error { case checksum }
        for count in [1,10_000] {
            let track = GPX.TrackStream(name:"Bad") { visit in
                for _ in 0..<count { try visit(.init(lat:24,lon:54)) }
                throw Failure.checksum
            }
            var output = Data()
            XCTAssertThrowsError(try GeoJSON.write(waypoints:[],graphics:[],tracks:[track]) { output.append($0) }) { XCTAssertTrue($0 is Failure) }
            XCTAssertThrowsError(try JSONSerialization.jsonObject(with:output))
        }
    }
    func testSinkFailureStopsVisiting() throws {
        enum Failure: Error { case full }
        let track = GPX.TrackStream(name:"Long") { visit in
            for _ in 0..<30_000 { try visit(.init(lat:24,lon:54)) }
            XCTFail("Output failure must stop visitation")
        }
        XCTAssertThrowsError(try GeoJSON.write(waypoints:[],graphics:[],tracks:[track]) { _ in throw Failure.full }) { XCTAssertTrue($0 is Failure) }
    }
    func testCancellationDuringOutputCannotFinish() async throws {
        let task = Task {
            let track = GPX.TrackStream(name:"Cancel") { visit in for _ in 0..<30_000 { try visit(.init(lat:24,lon:54)) } }
            try GeoJSON.write(waypoints:[],graphics:[],tracks:[track]) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        do { try await task.value; XCTFail("Cancelled output completed") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
