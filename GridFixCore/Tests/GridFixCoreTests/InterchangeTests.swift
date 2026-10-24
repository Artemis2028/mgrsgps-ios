import XCTest
@testable import GridFixCore

final class InterchangeTests: XCTestCase {
    func testCSVHeadersAliasesMetadataAndInvalidRowsMatchAndroid() throws {
        let text = "title;latitude;longitude;overlay;elevation_m;time;colour;symbol_code\n\"Alpha; \"\"1\"\"\";35.1234;-79.4567;Day 2;120.5;1700000000;RED;1101\nBad;91;0;;;;;\nBravo;-10;-20;;99999;bad;invalid;999999\n"
        let parsed = try CSV.parse(text)
        XCTAssertEqual(parsed.waypoints.count,2); XCTAssertEqual(parsed.skipped,1)
        XCTAssertEqual(parsed.waypoints[0].name,"Alpha; \"1\""); XCTAssertEqual(parsed.waypoints[0].folder,"Day 2")
        XCTAssertEqual(parsed.waypoints[0].metadata,.init(color: "red",milgpsSymbolCode: 1101,elevationMeters: 120.5,timestampMillis: 1700000000000))
        XCTAssertEqual(parsed.waypoints[1].folder,"Imported"); XCTAssertNil(parsed.waypoints[1].metadata?.elevationMeters)
    }
    func testCSVHeaderlessGridLabelsArabicDigitsAndMultilineQuoting() throws {
        let a = try CSV.parse("A,10.5,20.5\nB,not,a number\nD,-10,-20\r\n")
        XCTAssertEqual(a.waypoints.map(\.name),["A","D"])
        let b = try CSV.parse("\u{FEFF}name\tmgrs\n\"SP\nNorth\"\t\"usng: ١٨S UJ ٢٣٤٨٧ ٠٦٤٨٣\"\n")
        XCTAssertEqual(b.waypoints.first?.name,"SP\nNorth"); XCTAssertNotNil(b.waypoints.first)
        XCTAssertEqual(MGRS.parse("MGRS:18S-UJ-23487-06483")?.lat,MGRS.parse("18SUJ2348706483")?.lat)
    }
    func testCSVExportRoundTripAndSpreadsheetFormulaNeutralisation() throws {
        let points = [Waypoint(name: "Alpha \"1\"",lat: 35,lon: -79,folder: "Recon, west"),Waypoint(name: "=SUM(A1)",lat: -33.9,lon: 151.2,metadata: .init(color: "red",elevationMeters: 120.5,timestampMillis: 1700000000000))]
        let export = CSV.build(points), back = try CSV.parse(export).waypoints
        XCTAssertTrue(export.hasPrefix("name,mgrs,latitude,longitude,elevation_m,folder,color,symbolcode,time\n"))
        XCTAssertEqual(back.count,2); XCTAssertEqual(back[0].name,points[0].name); XCTAssertEqual(back[0].folder,"Recon, west")
        XCTAssertEqual(back[1].name,"'=SUM(A1)"); XCTAssertEqual(back[1].lat,-33.9); XCTAssertEqual(back[1].metadata,points[1].metadata)
    }
    func testGeoJSONFeaturesUseLonLatAndOnlyPolygonOuterRing() throws {
        let text = """
        {"type":"FeatureCollection","features":[
        {"type":"Feature","properties":{"name":"CP1","folder":"Lane A"},"geometry":{"type":"Point","coordinates":[-79.5,35.25,110]}},
        {"type":"Feature","properties":{"title":"Route"},"geometry":{"type":"LineString","coordinates":[[-79.5,35.2],[-79.4,35.3]]}},
        {"type":"Feature","geometry":{"type":"Polygon","coordinates":[[[-79,35],[-78.9,35],[-78.9,35.1],[-79,35]],[[0,0],[1,0],[0,1],[0,0]]]}},
        {"type":"Feature","geometry":{"type":"Point","coordinates":[200,95]}}]}
        """
        let parsed = try GeoJSON.parse(text), doc = try parsed.document(now: 100)
        XCTAssertEqual(doc.waypoints.count,1); XCTAssertEqual(doc.waypoints[0].lon,-79.5); XCTAssertEqual(doc.waypoints[0].metadata.elevationMeters,110)
        XCTAssertEqual(parsed.lines.count,1); XCTAssertEqual(parsed.areas[0].points.count,3); XCTAssertEqual(doc.graphics.map(\.type),["route","aa"])
        XCTAssertEqual(parsed.skipped,2)
    }
    func testGeoJSONMultiGeometriesAndCollectionsDoNotTreatBooleansAsCoordinates() throws {
        let text = """
        {"type":"GeometryCollection","geometries":[
        {"type":"MultiPoint","coordinates":[[20,10],[21,11],[true,false]]},
        {"type":"MultiLineString","coordinates":[[[20,10],[21,11]],[[22,12],[23,13]]]},
        {"type":"MultiPolygon","coordinates":[[[[20,10],[21,10],[21,11],[20,10]]]]}]}
        """
        let parsed = try GeoJSON.parse(text)
        XCTAssertEqual(parsed.waypoints.map(\.name),["Feature 1 1","Feature 1 2"])
        XCTAssertEqual(parsed.lines.count,2); XCTAssertEqual(parsed.areas.count,1); XCTAssertEqual(parsed.skipped,1)
    }
    func testGeoJSONExportsRingAndSectorBoundariesAndTrackKind() throws {
        let ring = Backup.Graphic(id: "ring",name: "Ring",type: "ring",points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54)])
        let sector = Backup.Graphic(id: "sector",name: "Arc",type: "sector",points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54),.init(lat: 24,lon: 54.001)])
        let text = try GeoJSON.build(waypoints: [.init(name: "A",lat: -5.123456789,lon: 100)],graphics: [ring,sector],tracks: [.init(name: "Walk",points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54)])])
        let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let features = root["features"] as! [[String: Any]], ringGeometry = features[1]["geometry"] as! [String: Any]
        XCTAssertEqual(ringGeometry["type"] as? String,"LineString"); XCTAssertEqual((ringGeometry["coordinates"] as! [[Double]]).count,73)
        let sectorGeometry = features[2]["geometry"] as! [String: Any]
        let ringCoordinates = (sectorGeometry["coordinates"] as! [[[Double]]])[0]
        XCTAssertEqual(sectorGeometry["type"] as? String,"Polygon"); XCTAssertEqual(ringCoordinates.first,ringCoordinates.last); XCTAssertGreaterThan(ringCoordinates.count,4)
        XCTAssertEqual((features[3]["properties"] as! [String: Any])["kind"] as? String,"track")
        let parsed = try GeoJSON.parse(text)
        XCTAssertEqual(parsed.waypoints[0].lat,-5.1234568); XCTAssertEqual(parsed.lines.count,2)
    }
    func testIdentityMatchesJVMSourceContractAndIgnoresClockDestinationSpelling() throws {
        var input = InterchangeContents()
        input.waypoints = [.init(name: "One",lat: 34,lon: -117,folder: "Patrol"),.init(name: "Two",lat: 34,lon: -117,folder: "PATROL")]
        input.lines = [.init(name: "Route",folder: "Patrol",points: [.init(lat: 34,lon: -117),.init(lat: 34.1,lon: -117.1)])]
        input.areas = [.init(name: "Area",folder: "Patrol",points: [.init(lat: 34,lon: -117),.init(lat: 34.1,lon: -117.1),.init(lat: 34.2,lon: -117)])]
        input.tracks = [.init(name: "Track",points: [.init(lat: 34,lon: -117),.init(lat: 34.1,lon: -117.1)])]
        XCTAssertEqual(input.fingerprint(),"bd3372674fe88327d7d0a5cb133ba16e83bba462dff581fd200b81d7601361de")
        let first = try input.document(now: 100,knownFolders: ["patrol"]), second = try input.document(now: 9999,knownFolders: ["PATROL"])
        XCTAssertEqual(first.waypoints.map(\.id),["ecf0de26-81e5-31e6-a49a-05b9dc1e7d82","0274adcd-2ba2-399a-b140-172a2a890df2"])
        XCTAssertEqual(first.graphics.map(\.id),["44a08ce8-3511-3b1a-bfdb-de9700625861","748dfbc3-f742-3932-b33a-0c4d8105101f"])
        XCTAssertEqual(first.tracks[0].id,"f8558559-48c0-3733-a2fe-5cb6f6253d57")
        XCTAssertEqual(first.waypoints.map(\.id),second.waypoints.map(\.id)); XCTAssertEqual(first.graphics.map(\.id),second.graphics.map(\.id))
        XCTAssertEqual(first.waypoints[0].folder,"patrol"); XCTAssertEqual(second.waypoints[0].folder,"PATROL")
    }
    func testUnchangedGPXRetainsDistinctDuplicateOrdinalsAndHistoricalTrackNormalization() throws {
        let xml = "<gpx><wpt lat=\"24\" lon=\"54\"><name>A</name></wpt><wpt lat=\"24\" lon=\"54\"><name>A</name></wpt><trk><trkseg><trkpt lat=\"24\" lon=\"54\"><time>1960-01-01T00:00:00Z</time></trkpt><trkpt lat=\"24.01\" lon=\"54\"/></trkseg></trk></gpx>"
        let a = try GPX.parse(xml,now: 100), b = try GPX.parse(xml,now: 999,knownFolders: ["IMPORTED"])
        XCTAssertEqual(a.waypoints.map(\.id),b.waypoints.map(\.id)); XCTAssertNotEqual(a.waypoints[0].id,a.waypoints[1].id)
        XCTAssertEqual(b.waypoints[0].folder,"IMPORTED"); XCTAssertEqual(a.waypoints[0].folder,"Imported")
        XCTAssertEqual(a.tracks[0].id,b.tracks[0].id); XCTAssertEqual(a.tracks[0].folder,"Base")
        XCTAssertEqual(try TrackCodec.decode(a.trackFiles[a.tracks[0].id]!).first?.time,0)
    }
    func testBoundsMalformedInputAndContentSniffingBeforePublication() throws {
        XCTAssertThrowsError(try CSV.parse(String(repeating: "x",count: CSV.byteLimit+1)))
        XCTAssertThrowsError(try GeoJSON.parse("{broken"))
        let text = "name,lat,lon\nA,24,54\n"
        XCTAssertEqual(try TextInterchange.preview(Data(text.utf8),filename: "points.csv").format,.csv)
        XCTAssertEqual(try TextInterchange.preview(Data("<gpx/>".utf8),filename: "unknown").format,.gpx)
        XCTAssertThrowsError(try TextInterchange.preview(Data("<html/>".utf8)))
    }
}
