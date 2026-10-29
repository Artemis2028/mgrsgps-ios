import XCTest
@testable import GridFixCore

final class KMLStreamingTests: XCTestCase {
    func testExactBytesPreserveFolderOrderShapesEscapingAndEmptyTracks() throws {
        let points = [Waypoint(name:"CAFÉ <&> \"",lat:1,lon:179,folder:"Zulu"),Waypoint(name:"B",lat:2,lon:-179,folder:"Alpha"),Waypoint(name:"C",lat:3,lon:4,folder:"Zulu")]
        let vertices = [Backup.GraphicPoint(lat:1,lon:2),.init(lat:3,lon:4),.init(lat:5,lon:6)]
        let graphics = [Backup.Graphic(id:"a",name:"Area &1",type:"area",points:vertices),Backup.Graphic(id:"r",name:"Route",type:"route",points:vertices),Backup.Graphic(id:"t",name:"Label",type:"text",points:[vertices[0]])]
        let tracks = [GPX.Track(name:"Track <&>",points:[.init(lat:1,lon:2),.init(lat:3,lon:4)]),GPX.Track(name:"Empty",points:[]),GPX.Track(name:"One",points:[.init(lat:5,lon:6)])]
        let streams = tracks.map { track in GPX.TrackStream(name:track.name) { visit in for point in track.points { try visit(point) } } }
        var output = Data()
        try KML.write(waypoints:points,graphics:graphics,tracks:streams) { output.append($0) }
        XCTAssertEqual(output,Data(KML.build(waypoints:points,graphics:graphics,tracks:tracks).utf8))
    }
    func testLongLocalTrackRetainsEveryCoordinateWithBoundedWrites() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".kml")
        FileManager.default.createFile(atPath:url.path,contents:nil)
        defer { try? FileManager.default.removeItem(at:url) }
        let handle = try FileHandle(forWritingTo:url)
        var writes = 0,largest = 0
        let track = GPX.TrackStream(name:"Long") { visit in
            for i in 0..<300_003 { try visit(.init(lat:i == 300_002 ? 60 : 24,lon:i == 0 ? 179.9 : -179.8)) }
        }
        try KML.write(waypoints:[],graphics:[],tracks:[track]) { bytes in writes += 1; largest = max(largest,bytes.count); try handle.write(contentsOf:bytes) }
        try handle.close()
        let parser = try XCTUnwrap(XMLParser(contentsOf:url)),counter = KMLStreamCoordinateCounter()
        parser.delegate = counter
        XCTAssertTrue(parser.parse(),String(describing:parser.parserError))
        XCTAssertEqual(counter.count,300_003); XCTAssertEqual(counter.first,"179.9000000,24.0000000,0"); XCTAssertEqual(counter.last,"-179.8000000,60.0000000,0")
        XCTAssertGreaterThan(writes,100); XCTAssertLessThan(largest,65*1024)
    }
    func testLateValidationFailureDoesNotFinishDocument() throws {
        enum Failure: Error { case checksum }
        var output = Data()
        let track = GPX.TrackStream(name:"Bad source") { visit in
            for _ in 0..<10_000 { try visit(.init(lat:24,lon:54)) }
            throw Failure.checksum
        }
        XCTAssertThrowsError(try KML.write(waypoints:[],graphics:[],tracks:[track]) { output.append($0) }) { XCTAssertTrue($0 is Failure) }
        XCTAssertFalse(output.isEmpty); XCTAssertFalse(String(decoding:output,as:UTF8.self).hasSuffix("</Document></kml>\n"))
    }
    func testSinkFailurePropagatesWithoutCompletingSource() throws {
        enum Failure: Error { case full }
        let track = GPX.TrackStream(name:"Long") { visit in
            for _ in 0..<10_000 { try visit(.init(lat:24,lon:54)) }
            XCTFail("Failed output should stop source visitation")
        }
        XCTAssertThrowsError(try KML.write(waypoints:[],graphics:[],tracks:[track]) { _ in throw Failure.full }) { XCTAssertTrue($0 is Failure) }
    }
    func testCancellationDuringOutputCannotReturnSuccess() async throws {
        let task = Task {
            let track = GPX.TrackStream(name:"Cancel") { visit in for _ in 0..<10_000 { try visit(.init(lat:24,lon:54)) } }
            try KML.write(waypoints:[],graphics:[],tracks:[track]) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        do { try await task.value; XCTFail("Cancelled output completed") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

private final class KMLStreamCoordinateCounter: NSObject,XMLParserDelegate {
    var count = 0,first: String?,last: String?
    private var reading = false,pending = ""
    private func finish() { if !pending.isEmpty { if first == nil { first = pending }; last = pending; count += 1; pending = "" } }
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) { if name == "coordinates" { reading = true } }
    func parser(_ parser:XMLParser,foundCharacters string:String) {
        guard reading else { return }
        for character in string { if character.isWhitespace { finish() } else { pending.append(character) } }
    }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) { if name == "coordinates" { finish(); reading = false } }
}
