import XCTest
@testable import GridFixCore

final class ImportDuplicatesTests:XCTestCase {
    func testAndroidNamePlaceLineAndTrackFixtures() throws {
        let here=[Waypoint(name:"OBJ CRANE",lat:35.16,lon:-79.04),Waypoint(name:"LZ HAWK",lat:35.1,lon:-79)]
        let line=[GeoPoint(lat:35,lon:-79),GeoPoint(lat:35.01,lon:-79)]
        let graphics=[Backup.Graphic(id:"g",name:"PL BLUE",type:"route",points:line.map{.init(lat:$0.lat,lon:$0.lon)})]
        let tracks=[Backup.TrackMeta(id:"t",name:"Walk",startedAt:0,endedAt:1,distanceM:0,pointCount:2)]
        var data=InterchangeContents()
        data.waypoints=[.init(name:"obj crane ",lat:35.160004,lon:-79.040004),.init(name:"OBJ CRANE",lat:35.161,lon:-79.04),.init(name:"LZ EAGLE",lat:35.1,lon:-79)]
        data.lines=[.init(name:"PL BLUE",points:line)]
        data.tracks=[.init(name:"Walk",points:[.init(lat:35,lon:-79),.init(lat:35,lon:-79)]),.init(name:"Walk",points:[.init(lat:35,lon:-79)])]
        let result=try ImportDuplicates.check(data,waypoints:here,graphics:graphics,tracks:tracks)
        XCTAssertEqual(result.total,6);XCTAssertEqual(result.duplicates,3)
        XCTAssertEqual(result.withoutDuplicates.waypoints.map(\.name),["OBJ CRANE","LZ EAGLE"])
        XCTAssertTrue(result.withoutDuplicates.lines.isEmpty);XCTAssertEqual(result.withoutDuplicates.tracks.first?.points.count,1)
        XCTAssertEqual(data.waypoints.count,3,"Review must not mutate the original Import all choice")
    }
    func testStrictThresholdOrderedVerticesAndTrackLength() throws {
        let here=[Waypoint(name:"A",lat:0,lon:0)]
        var data=InterchangeContents();data.waypoints=[.init(name:"A",lat:0.00001,lon:0),.init(name:"A",lat:0.000009,lon:0)]
        let p=[GeoPoint(lat:35,lon:-79),GeoPoint(lat:35.001,lon:-79)]
        let g=Backup.Graphic(id:"g",name:"Line",type:"phase_line",points:p.map{.init(lat:$0.lat,lon:$0.lon)})
        data.lines=[.init(name:"Line",points:Array(p.reversed()))]
        data.tracks=[.init(name:"Walk",points:p.map{.init(lat:$0.lat,lon:$0.lon)})]
        let different=Backup.TrackMeta(id:"t",name:"Walk",startedAt:0,endedAt:1,distanceM:0,pointCount:2)
        XCTAssertEqual(try ImportDuplicates.check(data,waypoints:here,graphics:[g],tracks:[different]).duplicates,1)
        var same=different;same.distanceM=TrackCodec.distance(data.tracks[0].points)+0.99
        XCTAssertEqual(try ImportDuplicates.check(data,waypoints:here,graphics:[g],tracks:[same]).duplicates,2)
    }
    func testFilteredChoiceHasStableContentIdentityAndOnlyRetainedFolders() throws {
        var data=InterchangeContents()
        data.waypoints=[.init(name:"Old",lat:1,lon:2,folder:"Old folder"),.init(name:"New",lat:3,lon:4,folder:"New folder")]
        let check=try ImportDuplicates.check(data,waypoints:[Waypoint(name:"Old",lat:1,lon:2)],graphics:[],tracks:[])
        let a=try check.withoutDuplicates.document(now:10),b=try check.withoutDuplicates.document(now:20)
        XCTAssertEqual(a.waypoints.map(\.id),b.waypoints.map(\.id));XCTAssertEqual(a.folders.map(\.name),["New folder"])
        XCTAssertNotEqual(a.waypoints[0].id,try data.document(now:10).waypoints[1].id)
        let preview=try TextInterchange.preview(Data("name,lat,lon\nA,1,2\n".utf8),format:.csv)
        XCTAssertEqual(preview.contents?.waypoints.count,1)
    }
    func testIndexedLargeImportRetainsMovedRecords() throws {
        let here=(0..<5000).map{Waypoint(name:"Point \($0)",lat:1,lon:2)}
        var data=InterchangeContents();data.waypoints=(0..<5000).map{.init(name:"Point \($0)",lat:$0%2 == 0 ? 1:1.001,lon:2)}
        let check=try ImportDuplicates.check(data,waypoints:here,graphics:[],tracks:[])
        XCTAssertEqual(check.total,5000);XCTAssertEqual(check.duplicates,2500);XCTAssertEqual(check.withoutDuplicates.waypoints.count,2500)
    }
}
