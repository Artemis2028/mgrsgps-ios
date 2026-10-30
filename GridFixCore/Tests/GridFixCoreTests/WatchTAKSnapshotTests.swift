import Foundation
import XCTest
@testable import GridFixCore

final class WatchTAKSnapshotTests: XCTestCase {
    private let date = Date(timeIntervalSince1970:1_792_970_000)
    private func remote(_ id:String = "team",points:[GeoPoint] = [.init(lat:24.4539,lon:54.3773)],closed:Bool = false,contact:Bool = true,life:Double = 120,name:String = "TEAM ONE") -> TAKRemoteItem {
        .init(id:id,callsign:name,affiliation:"friendly",points:points,closed:closed,isContact:contact,staleAt:date.addingTimeInterval(life),creator:nil)
    }
    private func packet(_ values:[TAKRemoteItem]? = nil,revision:Int64 = 1) -> WatchTAKSnapshot {
        .build(values ?? [remote()],enabled:true,connected:true,date:date,sourceID:"synthetic-phone",revision:revision)
    }
    func testSharedGoldenContactMarkerBentLineAndArea() throws {
        let data = try Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:"watch-tak-v1",withExtension:"json")))
        let golden = try XCTUnwrap(WatchTAKSnapshot.decode(data))
        let source = zip(["team","marker","line","area"],golden.items).map { id,item in
            TAKRemoteItem(id:id,callsign:item.name,affiliation:item.affiliation,points:item.points,closed:item.closed,isContact:item.contact,staleAt:Date(timeIntervalSince1970:Double(item.expiresAt)/1000),creator:"not exported")
        }
        XCTAssertEqual(packet(source,revision:7),golden)
        XCTAssertEqual(WatchTAKSnapshot.decode(try XCTUnwrap(golden.encoded())),golden)
        XCTAssertEqual(golden.items[1].name,"OP CAFÉ"); XCTAssertEqual(golden.items[2].points.count,3); XCTAssertTrue(golden.items[3].closed)
        XCTAssertFalse(String(decoding:golden.encoded()!,as:UTF8.self).contains("not exported"))
    }
    func testBoundedUnicodePacketsCountEveryOmissionAndKeepCompleteGeometry() throws {
        let source = (0..<1000).map { remote("uid-\($0)",name:String(repeating:"🧭",count:120)) }
        let p = packet(source),data = try XCTUnwrap(p.encoded())
        XCTAssertLessThanOrEqual(data.count,8192); XCTAssertLessThanOrEqual(p.items.count,64)
        XCTAssertEqual(p.omitted,source.count-p.items.count); XCTAssertEqual(Set(p.items.map(\.id)).count,p.items.count)
        XCTAssertTrue(p.items.allSatisfy { $0.name == String(repeating:"🧭",count:120) })
        XCTAssertNotNil(WatchTAKSnapshot.decode(data))
        let small = try XCTUnwrap(p.fitting(bytes:512)); XCTAssertLessThanOrEqual(small.encoded()!.count,512)
        XCTAssertEqual(small.items.count+small.omitted,1000)
    }
    func testWholeInvalidOrOversizedDrawingsAreOmittedAndStaleItemsNotExported() throws {
        let oversized = (0..<129).map { GeoPoint(lat:24+Double($0)*0.00001,lon:54) }
        let crossing = [GeoPoint(lat:24,lon:179),GeoPoint(lat:24,lon:-179),GeoPoint(lat:25,lon:-179)]
        let source = [remote("large",points:oversized,contact:false),remote("dateline",points:crossing,closed:true,contact:false),remote("polar",points:[.init(lat:86,lon:1)]),remote("zero",points:[.init(lat:0,lon:0)]),remote("bad-contact",points:[.init(lat:24,lon:54),.init(lat:25,lon:54)]),remote("stale",life:0),remote()]
        let p = packet(source)
        XCTAssertEqual(p.items.count,1); XCTAssertEqual(p.omitted,5); XCTAssertEqual(p.items[0].name,"TEAM ONE")
        let hidden = WatchTAKSnapshot.build(source,enabled:false,connected:true,date:date,sourceID:"phone",revision:2)
        XCTAssertTrue(hidden.items.isEmpty); XCTAssertEqual(hidden.omitted,0)
        let capped = packet([remote(life:7200)]); XCTAssertEqual(capped.items[0].expiresAt-capped.at,3_600_000)
    }
    func testDeletesHiddenLayerAndReorderedFramesCannotResurrectRemoteItems() {
        let p = packet(); var scene = WatchTAKScene()
        XCTAssertTrue(scene.apply(p,now:date,uptime:100)); XCTAssertEqual(scene.visible(now:date,uptime:100).count,1)
        let clear = packet([],revision:2)
        XCTAssertTrue(scene.apply(clear,now:date,uptime:100)); XCTAssertTrue(scene.visible(now:date,uptime:100).isEmpty)
        XCTAssertFalse(scene.apply(p,now:date,uptime:100)); XCTAssertFalse(scene.apply(clear,now:date,uptime:100))
        var future = packet(revision:3); future.at += 10_000
        XCTAssertFalse(scene.apply(future,now:date,uptime:100))
        var different = packet(revision:20); different.sourceID = "other"; different.at -= 1
        XCTAssertFalse(scene.apply(different,now:date,uptime:100))
    }
    func testMonotonicExpiryClockJumpAndCacheReloadDoNotExtendUnchangedItems() throws {
        var scene = WatchTAKScene(); let first = packet([remote(life:5)])
        XCTAssertTrue(scene.apply(first,now:date,uptime:100))
        XCTAssertEqual(scene.visible(now:date.addingTimeInterval(2),uptime:102).count,1)
        XCTAssertTrue(scene.visible(now:date.addingTimeInterval(20),uptime:102).isEmpty)
        var second = first; second.revision = 2; second.at += 1000
        XCTAssertTrue(scene.apply(second,now:date.addingTimeInterval(1),uptime:104))
        let restored = try XCTUnwrap(WatchTAKScene.decodeCache(XCTUnwrap(scene.encodedCache())))
        XCTAssertTrue(restored.visible(now:date.addingTimeInterval(2),uptime:105).isEmpty,"Original monotonic expiry survived the cache round-trip")
        XCTAssertTrue(restored.visible(now:date.addingTimeInterval(2),uptime:1).isEmpty,"A reboot cannot reuse the old monotonic anchor")
        var renewed = second; renewed.revision = 3; renewed.at += 1000; renewed.items[0].expiresAt += 10_000
        XCTAssertTrue(scene.apply(renewed,now:date.addingTimeInterval(2),uptime:105))
        XCTAssertEqual(scene.visible(now:date.addingTimeInterval(2),uptime:105).count,1)
    }
    func testMalformedBoundsDuplicateIDsAndImpossibleCacheAreRefused() throws {
        var p = packet(); p.version = 2; XCTAssertNil(WatchTAKSnapshot.decode(try JSONEncoder().encode(p)))
        p = packet(); p.items.append(p.items[0]); XCTAssertFalse(p.isValid)
        p = packet(); p.items[0].expiresAt = p.at; XCTAssertFalse(p.isValid)
        p = packet(); p.items[0].id = "unbounded arbitrary UID"; XCTAssertFalse(p.isValid)
        p = packet(); p.enabled = false; XCTAssertFalse(p.isValid)
        XCTAssertNil(WatchTAKSnapshot.decode(Data(repeating:32,count:8193)))
        XCTAssertNil(WatchTAKScene.decodeCache(Data(repeating:32,count:24*1024+1)))
        var scene = WatchTAKScene(); XCTAssertTrue(scene.apply(packet(),now:date,uptime:100))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(scene.encodedCache())) as? [String:Any])
        object["deadlines"] = ["unknown":101.0]
        XCTAssertNil(WatchTAKScene.decodeCache(try JSONSerialization.data(withJSONObject:object)))
    }
    func testActualCoTDeleteReplacesOnlySeparateRemoteScene() throws {
        var source = TAKRemoteScene(); source.apply(.item(remote()),now:date,uptime:100)
        let initial = packet(source.items); XCTAssertEqual(initial.items.count,1)
        source.apply(.delete("team"),now:date,uptime:100)
        XCTAssertTrue(packet(source.items,revision:2).items.isEmpty)
        let local = WatchMapSnapshot.build(waypoints:[Waypoint(name:"Saved",lat:24,lon:54)],folders:[],document:Backup.Document())
        XCTAssertEqual(local.waypoints.count,1)
    }
}
