import XCTest
@testable import GridFixCore

final class KMZStreamingTests: XCTestCase {
    func testExactLegacyArchiveBytesAndGeometry() throws {
        let point = Waypoint(name:"CAFÉ & patrol",lat:24,lon:54,folder:"Recon")
        let track = GPX.Track(name:"Walk",points:[.init(lat:24,lon:54),.init(lat:25,lon:55)])
        let stream = GPX.TrackStream(name:track.name) { visit in for point in track.points { try visit(point) } }
        var result = Data()
        try KMZ.write(waypoints:[point],graphics:[],tracks:[stream]) { result.append($0) }
        XCTAssertEqual(result,try KMZ.build(waypoints:[point],graphics:[],tracks:[track]))
        let decoded = try KMZ.parse(result)
        XCTAssertEqual(decoded.waypoints.first?.name,point.name); XCTAssertEqual(decoded.lines.first?.points.count,2)
    }
    func testLongSourceIsVisitedTwiceAndEveryCoordinateSurvivesArchive() throws {
        let count = 300_003
        var visits = 0,largest = 0,writes = 0,result = Data()
        let stream = GPX.TrackStream(name:"Long") { visit in
            for i in 0..<count { try visit(.init(lat:i == count-1 ? 60 : 24,lon:i == 0 ? 179.9 : -179.8)) }
        }
        try ZipArchive.writeStored(name:"doc.kml",produce: { sink in
            visits += 1; try KML.write(waypoints:[],graphics:[],tracks:[stream],sink:sink)
        }) { bytes in writes += 1; largest = max(largest,bytes.count); result.append(bytes) }
        XCTAssertEqual(visits,2); XCTAssertGreaterThan(writes,100); XCTAssertLessThan(largest,65*1024)
        let entry = try XCTUnwrap(try ZipArchive.read(result).first)
        XCTAssertEqual(entry.name,"doc.kml")
        let counter = KMZCoordinateCounter(),parser = XMLParser(data:entry.data); parser.delegate = counter
        XCTAssertTrue(parser.parse()); XCTAssertEqual(counter.count,count)
        XCTAssertEqual(counter.first,"179.9000000,24.0000000,0"); XCTAssertEqual(counter.last,"-179.8000000,60.0000000,0")
    }
    func testChangedSecondVisitCannotFinishCentralDirectory() throws {
        var visits = 0,result = Data()
        XCTAssertThrowsError(try ZipArchive.writeStored(name:"doc.kml",produce: { sink in
            visits += 1; try sink(Data((visits == 1 ? "before" : "after!").utf8))
        }) { result.append($0) }) { XCTAssertTrue($0.localizedDescription.contains("changed")) }
        XCTAssertEqual(visits,2); XCTAssertThrowsError(try ZipArchive.read(result))
    }
    func testValidationErrorsAndSinkErrorsPropagate() throws {
        enum Failure: Error {case checksum,full}
        var output = Data()
        XCTAssertThrowsError(try ZipArchive.writeStored(name:"doc.kml",produce: { sink in
            try sink(Data(repeating:1,count:100)); throw Failure.checksum
        }) { output.append($0) }) { XCTAssertTrue($0 is Failure) }
        XCTAssertTrue(output.isEmpty,"First-pass validation must precede ZIP output")
        var visits = 0
        XCTAssertThrowsError(try ZipArchive.writeStored(name:"doc.kml",produce: { sink in
            visits += 1; try sink(Data("valid".utf8))
        }) { _ in throw Failure.full }) { XCTAssertTrue($0 is Failure) }
        XCTAssertEqual(visits,1,"A failed header sink must not re-read the source")
    }
    func testEmptyChunksRetainCRCAndEmptyMembersRemainValid() throws {
        for chunks in [[Data()], [Data("before".utf8),Data(),Data("after".utf8)]] {
            var output = Data()
            try ZipArchive.writeStored(name:"doc.kml",produce: { sink in for c in chunks {try sink(c)} }) {output.append($0)}
            let combined = chunks.reduce(into:Data()) {$0.append($1)}
            XCTAssertEqual(output,ZipArchive.write(entries:[.init(name:"doc.kml",data:combined)]))
            XCTAssertEqual(try ZipArchive.read(output).first?.data,combined)
        }
    }
    func testCancellationAfterOutputStartsCannotReturnSuccess() async throws {
        let task = Task {
            try ZipArchive.writeStored(name:"doc.kml",produce: { try $0(Data("valid".utf8)) }) { _ in
                withUnsafeCurrentTask {$0?.cancel()}
            }
        }
        do {try await task.value;XCTFail("Cancelled ZIP output completed")}
        catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
    }
}
private final class KMZCoordinateCounter: NSObject,XMLParserDelegate {
    var count = 0,first: String?,last: String?
    private var reading = false,pending = ""
    private func finish() {if !pending.isEmpty {if first == nil {first=pending};last=pending;count += 1;pending=""}}
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {if name=="coordinates" {reading=true}}
    func parser(_ parser:XMLParser,foundCharacters string:String) {guard reading else {return};for c in string {if c.isWhitespace {finish()} else {pending.append(c)}}}
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {if name=="coordinates" {finish();reading=false}}
}
