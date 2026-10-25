import XCTest
@testable import GridFixCore

final class KMLPackageTests: XCTestCase {
    private func kml(_ content: String) -> String { "<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document>\(content)</Document></kml>" }
    private func zip(_ members: [(String,Data)]) -> Data { ZipArchive.write(entries: members.map { .init(name: $0.0,data: $0.1) }) }
    private var waypoint: Data { Data("<gpx><wpt lat=\"34\" lon=\"-117\"><name>Camp</name></wpt></gpx>".utf8) }

    func testKMLClosedLineKeepsReturnLegWhilePolygonDropsClosure() throws {
        let content = try KML.parse(kml("""
        <Placemark><name>Route</name><LineString><coordinates>1,2 3,4 1,2</coordinates></LineString></Placemark>
        <Placemark><name>Area</name><Polygon><outerBoundaryIs><LinearRing><coordinates>1,2 3,4 5,6 1,2</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>
        """))
        XCTAssertEqual(content.lines[0].points.count,3); XCTAssertEqual(content.lines[0].points.first,content.lines[0].points.last)
        XCTAssertEqual(content.areas[0].points.count,3); XCTAssertNotEqual(content.areas[0].points.first,content.areas[0].points.last)
    }
    func testNestedMultiGeometryKeepsSiblingCoordinatesAndNearestFolderInEitherOrder() throws {
        let point = "<Point><coordinates>-117,34,99</coordinates></Point>", line = "<LineString><coordinates>-118,35 -119,36</coordinates></LineString>"
        for geometry in [point+line,line+point] {
            let result = try KML.parse(kml("<Folder><name>Parent</name><Folder><name>Child</name><Placemark><MultiGeometry>\(geometry)<MultiGeometry><Point><coordinates>-120,37</coordinates></Point></MultiGeometry></MultiGeometry><name>Mixed &amp; scoped</name></Placemark></Folder><Placemark><Point><coordinates>1,2</coordinates></Point></Placemark></Folder>"))
            XCTAssertEqual(result.waypoints.count,3); XCTAssertEqual(result.lines.count,1)
            XCTAssertEqual(result.waypoints[0].lat,34); XCTAssertEqual(result.waypoints[1].lon,-120)
            XCTAssertEqual(result.lines[0].points.map(\.lat),[35,36])
            XCTAssertEqual(result.waypoints.map(\.folder),["Child","Child","Parent"])
            XCTAssertEqual(result.waypoints[0].name,"Mixed & scoped"); XCTAssertNil(result.waypoints[0].metadata)
        }
    }
    func testForeignExtensionCoordinatesCannotMasqueradeAsGeometriesAndBadPositionsSkip() throws {
        let result = try KML.parse(kml("""
        <Placemark xmlns:x="urn:not-kml"><x:Point><x:coordinates>100,50</x:coordinates></x:Point><ExtendedData><Point><coordinates>101,51</coordinates></Point></ExtendedData><Point><x:coordinates>102,52</x:coordinates><coordinates>-117,34</coordinates></Point></Placemark>
        <Placemark><Point><coordinates>NaN,0 20,95</coordinates></Point></Placemark>
        """))
        XCTAssertEqual(result.waypoints.count,1); XCTAssertEqual(result.waypoints[0].lon,-117)
        XCTAssertEqual(result.skipped,3)
        XCTAssertThrowsError(try KML.parse("<html/>")); XCTAssertThrowsError(try KML.parse("<kml><Placemark>"))
    }
    func testPolygonHoleAndExcessGeometryNestingRejectTheWholeDocument() throws {
        let good = "<Placemark><Point><coordinates>1,2</coordinates></Point></Placemark>"
        let hole = "<Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>1,2 2,3 3,4</coordinates></LinearRing></outerBoundaryIs><innerBoundaryIs><LinearRing><coordinates>1,2 2,3 3,4</coordinates></LinearRing></innerBoundaryIs></Polygon></Placemark>"
        XCTAssertThrowsError(try KML.parse(kml(good+hole))) { XCTAssertTrue($0.localizedDescription.contains("holes")) }
        let deep = String(repeating: "<MultiGeometry>",count: 66)+"<Point><coordinates>1,2</coordinates></Point>"+String(repeating: "</MultiGeometry>",count: 66)
        XCTAssertThrowsError(try KML.parse(kml("<Placemark>"+deep+"</Placemark>")))
    }
    func testKMLExportsRingSectorTypedPointAndTracksAsGeography() throws {
        let ring = Backup.Graphic(id: "ring",name: "Ring",type: "ring",points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54)])
        let sector = Backup.Graphic(id: "sector",name: "Sector",type: "sector",points: [.init(lat: 24,lon: 54),.init(lat: 24.001,lon: 54),.init(lat: 24,lon: 54.002)])
        let cp = Backup.Graphic(id: "cp",name: "Hill",type: "checkpoint",points: [.init(lat: 24,lon: 54)])
        let xml = KML.build(waypoints: [.init(name: "A & <B>",lat: -34,lon: 117,folder: "Lane & west")],graphics: [ring,sector,cp],tracks: [.init(name: "Walk",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)])])
        let result = try KML.parse(xml)
        XCTAssertEqual(result.waypoints.map(\.name),["A & <B>","CP Hill"])
        XCTAssertEqual(result.waypoints.map(\.folder),["Lane & west","Graphics"])
        XCTAssertEqual(result.lines.count,2); XCTAssertEqual(result.lines[0].points.count,73)
        XCTAssertEqual(result.lines[1].folder,"Tracks"); XCTAssertEqual(result.areas.count,1)
        XCTAssertEqual(result.areas[0].points.first,.init(lat: 24,lon: 54))
        let fromKmz = try KMZ.parse(KMZ.build(waypoints: [],graphics: [ring],tracks: []))
        XCTAssertEqual(fromKmz.lines.count,1); XCTAssertEqual(fromKmz.lines[0].points.count,73)
    }
    func testCoTAffiliationFallbackAndUnsupportedEventsMatchAndroid() throws {
        let types = ["a-f-G","a-a-G","a-h-G","a-j-G","a-k-G","a-n-G","a-u-G","a-p-G","a-s-G","b-m-p-w"]
        let events = types.enumerated().map { index,type in ("cot/\(index).cot",Data("<event uid=\"Fallback\" type=\"\(type)\"><point lat=\"34\" lon=\"-117\"/><detail><contact callsign=\"Team &amp; one\"/></detail></event>".utf8)) }
        let invalid: [(String,Data)] = ["b-m-r","u-d-f","b-t-f","zero","bad","malformed"].map { name in
            let point = name == "zero" ? "0\" lon=\"0" : name == "bad" ? "NaN\" lon=\"500" : "34\" lon=\"-117"
            return (name+".cot",Data((name == "malformed" ? "<event>" : "<event type=\"\(name)\"><point lat=\"\(point)\"/></event>").utf8))
        }
        let content = try ATAKPackage.parse(zip(events+invalid))
        XCTAssertEqual(content.waypoints.map(\.affiliation),["friendly","friendly","hostile","hostile","hostile","neutral","unknown","unknown","unknown","none"])
        XCTAssertTrue(content.waypoints.allSatisfy { $0.symbol == "target" && $0.kind == "wp" && $0.name == "Team & one" && $0.metadata == nil })
        XCTAssertEqual(content.skipped,6)
    }
    func testATAKManifestTypesStableUIDsAndGPXRoutesExcludeOtherGraphics() throws {
        let a = Waypoint(id: "chosen-id",name: "A & \"B\"",lat: 34,lon: -117,folder: "Patrol",affiliation: "friendly",kind: "unit")
        let b = Waypoint(id: "other-id",name: "Basic",lat: 35,lon: -118,affiliation: "hostile")
        let route = Backup.Graphic(id: "r",name: "Route",type: "route",points: [.init(lat: 34,lon: -117),.init(lat: 35,lon: -118)])
        let area = Backup.Graphic(id: "a",name: "Area",type: "aa",points: [.init(lat: 34,lon: -117),.init(lat: 35,lon: -118),.init(lat: 35,lon: -117)])
        let bytes = try ATAKPackage.build(waypoints: [a,b],routes: [route,area],nowMillis: 1700000000000)
        let entries = try ZipArchive.read(bytes), texts = Dictionary(uniqueKeysWithValues: entries.map { ($0.name,String(decoding: $0.data,as: UTF8.self)) })
        let cot = try XCTUnwrap(texts["cot/gridfix-0.cot"]), manifest = try XCTUnwrap(texts["MANIFEST/manifest.xml"])
        XCTAssertTrue(cot.contains("uid=\"GRIDFIX-chosen-id\"")); XCTAssertTrue(cot.contains("type=\"a-f-G\"")); XCTAssertTrue(cot.contains("2023-11-14T22:13:20.000Z")); XCTAssertTrue(cot.contains("A &amp; &quot;B&quot;"))
        XCTAssertTrue(texts["cot/gridfix-1.cot"]!.contains("type=\"b-m-p-w\""))
        XCTAssertTrue(manifest.contains("<MissionPackageManifest version=\"2\">")); XCTAssertTrue(manifest.contains("zipEntry=\"routes.gpx\""))
        let imported = try ATAKPackage.parse(bytes)
        XCTAssertEqual(imported.waypoints.count,2); XCTAssertEqual(imported.lines.count,1); XCTAssertTrue(imported.areas.isEmpty)
        let reordered = try ZipArchive.read(ATAKPackage.build(waypoints: [b,a],routes: [],nowMillis: 999))
        XCTAssertTrue(String(decoding: reordered.first { $0.name == "cot/gridfix-1.cot" }!.data,as: UTF8.self).contains("GRIDFIX-chosen-id"))
    }
    func testPackageStagesAllMembersInOneNamespaceAndRetainsRawGPXTime() throws {
        let kmlData = Data(kml("<Placemark><name>KML point</name><Point><coordinates>-118,35</coordinates></Point></Placemark>").utf8)
        let gpx = Data("<gpx><trk><trkseg><trkpt lat=\"34\" lon=\"-117\"><time>1960-01-01T00:00:00Z</time></trkpt></trkseg></trk></gpx>".utf8)
        let nested = zip([("first.kml",kmlData),("ignored.kml",Data(kml("").utf8))])
        let data = zip([("first.gpx",waypoint),("nested.kmz",nested),("walk.gpx",gpx),("ignored.csv",Data("name,lat,lon\nIgnored,1,2".utf8))])
        let parsed = try ATAKPackage.parse(data), first = try parsed.document(now: 100), second = try ATAKPackage.parse(data).document(now: 999,knownFolders: ["IMPORTED"])
        XCTAssertEqual(parsed.waypoints.map(\.name),["Camp","KML point"]); XCTAssertLessThan(parsed.tracks[0].points[0].time,0)
        XCTAssertEqual(first.waypoints.map(\.id),second.waypoints.map(\.id)); XCTAssertEqual(first.tracks.map(\.id),second.tracks.map(\.id))
        XCTAssertEqual(try TrackCodec.decode(first.trackFiles[first.tracks[0].id]!).first?.time,0)
        XCTAssertNotEqual(first.waypoints[0].id,try GPX.parse(String(decoding: waypoint,as: UTF8.self)).waypoints[0].id)
    }
    func testIgnoredMembersNestedKMZAndTrailingMembersShareArchiveBudgets() throws {
        let limits = ImportArchiveBudget.Limits(entryBytes: 256,totalBytes: 4096,entries: 20)
        XCTAssertThrowsError(try ATAKPackage.parse(zip([("good.gpx",waypoint),("oversized.gpx",Data(repeating: 32,count: 257))]),budget: .init(limits),parseBudget: .init()))
        let large = zip([("doc.kml",Data(kml(String(repeating: " ",count: 300)).utf8))])
        let package = zip([("good.gpx",waypoint),("nested.kmz",large)])
        // The nested KML can be larger than its container once DEFLATE is used;
        // a Java-generated fixture below additionally covers compressed members.
        XCTAssertThrowsError(try ATAKPackage.parse(package,budget: .init(limits),parseBudget: .init()))
        XCTAssertThrowsError(try KMZ.parse(zip([("doc.kml",Data("<kml/>".utf8)),("ignored.bin",Data(count: 257))]),budget: .init(limits),filename: "map.kmz",parseBudget: .init()))
        let nestedIgnored = zip([("ignored.txt",Data(count: 200))])
        let aggregate = ImportArchiveBudget.Limits(entryBytes: 512,totalBytes: nestedIgnored.count+200,entries: 20)
        XCTAssertThrowsError(try ATAKPackage.parse(zip([("notes.txt",Data(count: 200)),("nested.kmz",nestedIgnored)]),budget: .init(aggregate),parseBudget: .init())) { XCTAssertTrue($0.localizedDescription.contains("nested.kmz!/ignored.txt")) }
        XCTAssertThrowsError(try ATAKPackage.parse(zip([("a",Data()),("b",Data()),("c",Data())]),budget: .init(.init(entryBytes: 512,totalBytes: 400,entries: 2)),parseBudget: .init()))
        XCTAssertEqual(try ATAKPackage.parse(zip([("good.gpx",waypoint)]),budget: .init(.init(entryBytes: waypoint.count,totalBytes: waypoint.count,entries: 1)),parseBudget: .init()).waypoints.count,1)
    }
    func testPackageCannotBypassSharedRecordOrPointLimitsAcrossFiles() throws {
        let budget = ImportParseBudget(); budget.recordLimit = 1
        XCTAssertThrowsError(try ATAKPackage.parse(zip([("a.gpx",waypoint),("b.gpx",waypoint)]),budget: .init(),parseBudget: budget))
        let points = ImportParseBudget(); points.pointLimit = 3
        let line = Data(kml("<Placemark><LineString><coordinates>1,2 3,4</coordinates></LineString></Placemark>").utf8)
        XCTAssertThrowsError(try ATAKPackage.parse(zip([("a.kml",line),("b.kmz",zip([("doc.kml",line)]))]),budget: .init(),parseBudget: points))
        let broken = zip([("good.gpx",waypoint),("bad.kml",Data("<kml><Placemark>".utf8))])
        XCTAssertThrowsError(try ATAKPackage.parse(broken))
    }
    func testJavaDeflatedMissionFixtureAndReorderedDirectoryKeepLocalIdentityOrder() throws {
        func fixture(_ name: String) throws -> Data { try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name,withExtension: "zip"))) }
        let raw = try fixture("android-mission-package"), reordered = try fixture("android-central-reordered")
        let content = try ATAKPackage.parse(raw), a = try content.document(now: 100), b = try ATAKPackage.parse(reordered).document(now: 200)
        XCTAssertEqual(content.waypoints.map(\.name),["Hostile & one","Camp"])
        XCTAssertEqual(content.waypoints[0].affiliation,"hostile"); XCTAssertEqual(content.lines[0].points.count,3)
        XCTAssertEqual(content.areas.count,1); XCTAssertEqual(content.tracks.count,1)
        XCTAssertEqual(a.waypoints.map(\.id),b.waypoints.map(\.id)); XCTAssertEqual(a.graphics.map(\.id),b.graphics.map(\.id)); XCTAssertEqual(a.tracks.map(\.id),b.tracks.map(\.id))
        XCTAssertEqual(try TextInterchange.preview(raw,filename: "mission.dpk").format,.atak)
        XCTAssertEqual(try TextInterchange.preview(raw).recordCount,5)
    }
    func testCompressedNestedKMZCannotBypassDeclaredOrSharedBudget() throws {
        let raw = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "android-nested-budget",withExtension: "zip")))
        let nested = try XCTUnwrap(ZipArchive.read(raw).first?.data)
        XCTAssertLessThan(nested.count,256)
        XCTAssertThrowsError(try ATAKPackage.parse(raw,budget: .init(.init(entryBytes: 256,totalBytes: 4096,entries: 20)),parseBudget: .init())) {
            XCTAssertTrue($0.localizedDescription.contains("nested.kmz!/doc.kml"),$0.localizedDescription)
        }
    }
    func testRawXMLBytesAndCDATAHonorDeclaredUnicodeEncoding() throws {
        let body = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><kml><Folder><name><![CDATA[Mission é]]></name><Placemark><name><![CDATA[Café & west]]></name><Point><coordinates><![CDATA[-117,34,0]]></coordinates></Point></Placemark></Folder></kml>"
        let bytes = try XCTUnwrap(body.data(using: .utf16))
        let doc = try TextInterchange.preview(bytes,filename: "unicode.kml").document
        XCTAssertEqual(doc.waypoints[0].name,"Café & west"); XCTAssertEqual(doc.waypoints[0].folder,"Mission é")
        let gpx = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><gpx><wpt lat=\"34\" lon=\"-117\"><name><![CDATA[Café]]></name></wpt></gpx>"
        let point = try TextInterchange.preview(XCTUnwrap(gpx.data(using: .utf16)),filename: "unicode.gpx").document.waypoints[0]
        XCTAssertEqual(point.name,"Café")
    }
    func testIgnoredCRCFailureStillRejectsPackageAndPathsAreNeverExtracted() throws {
        var bytes = zip([("good.gpx",waypoint),("ignored.bin",Data("CRC_SENTINEL".utf8))])
        let index = try XCTUnwrap(bytes.range(of: Data("CRC_SENTINEL".utf8))).lowerBound
        bytes[index] ^= 1
        XCTAssertThrowsError(try ATAKPackage.parse(bytes))
        let namedOnly = zip([("../../position.gpx",waypoint)])
        XCTAssertEqual(try ATAKPackage.parse(namedOnly).waypoints.count,1)
        XCTAssertThrowsError(try ZipArchive.read(namedOnly)) // Backup path rules remain strict.
    }
    func testBackupZIPHasExplicitRouteAndBinaryFormatsAreNotPasted() throws {
        XCTAssertThrowsError(try TextInterchange.preview(Backup.exportZip(.init()),filename: "backup.zip")) { XCTAssertTrue($0.localizedDescription.contains("Import backup")) }
        XCTAssertFalse(TextInterchangeFormat.atak.canPaste); XCTAssertFalse(TextInterchangeFormat.kmz.canPaste); XCTAssertTrue(TextInterchangeFormat.kml.canPaste)
        XCTAssertEqual(TextInterchange.fileLimit(filename: "mission.DPK"),512*1024*1024)
    }

    func testSinglePointTrackIsNotTurnedIntoAnInventedWaypointOnKMLExport() throws {
        let xml = KML.build(waypoints: [],graphics: [],tracks: [.init(name: "One fix",points: [.init(lat: 24,lon: 54)])])
        XCTAssertTrue(xml.contains("<LineString>")); XCTAssertFalse(xml.contains("<Point>"))
        XCTAssertTrue(try KML.parse(xml).isEmpty)
    }

}
