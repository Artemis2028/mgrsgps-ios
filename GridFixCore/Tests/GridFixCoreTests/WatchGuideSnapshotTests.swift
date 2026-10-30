import Foundation
import XCTest
@testable import GridFixCore

final class WatchGuideSnapshotTests: XCTestCase {
    private func packet() -> WatchGuideSnapshot { .init(sourceID:"phone",revision:1,at:1_000_000,active:true,available:true,targetName:"OBJ CAFÉ",status:"Inside lane · silent",laneName:"Creek",laneState:"INSIDE") }
    func testSharedAndroidGoldenDecisionsAndInactiveClear() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"watch-guide-v1",withExtension:"json"))
        let packets = try JSONDecoder().decode([WatchGuideSnapshot].self,from:Data(contentsOf:url))
        XCTAssertEqual(packets.count,7)
        XCTAssertEqual(packets.prefix(5).compactMap(\.laneState),["NOT_YET","INSIDE","OUT_LEFT","OUT_RIGHT","OVERSHOT"])
        for packet in packets { XCTAssertEqual(WatchGuideSnapshot.decode(try JSONEncoder().encode(packet)),packet) }
        XCTAssertEqual(packets[2].crossedLine,"Creek bank"); XCTAssertEqual(packets[4].crossedLine,"Power line")
        XCTAssertEqual(packets[5].displayStatus(at:Date(timeIntervalSince1970:Double(packets[5].at)/1000)),"Phone guidance unavailable")
        XCTAssertFalse(packets[6].active); XCTAssertNil(packets[6].laneState)
    }
    func testExpiryFutureClockAndUnavailableNeverShowSteering() {
        var p = packet()
        XCTAssertEqual(p.displayStatus(at:Date(timeIntervalSince1970:1020)),p.status)
        XCTAssertFalse(p.isFresh(at:Date(timeIntervalSince1970:1020.001)))
        XCTAssertFalse(p.isFresh(at:Date(timeIntervalSince1970:997.999)))
        XCTAssertEqual(p.displayStatus(at:Date(timeIntervalSince1970:1021)),"Phone guidance expired · open phone")
        p.available = false
        XCTAssertEqual(p.displayStatus(at:Date(timeIntervalSince1970:1000)),"Phone guidance unavailable")
    }
    func testReorderedDecisionCannotUndoStopOrNewRun() {
        let p = packet()
        let stopped = WatchGuideSnapshot(sourceID:"phone",revision:2,at:p.at,active:false)
        XCTAssertTrue(stopped.shouldApply(over:p)); XCTAssertFalse(p.shouldApply(over:stopped))
        XCTAssertTrue(stopped.shouldApply(over:stopped))
        var conflict = stopped; conflict.active = true
        XCTAssertFalse(conflict.shouldApply(over:stopped))
        conflict.sourceID = "different-phone"; conflict.at -= 1
        XCTAssertFalse(conflict.shouldApply(over:stopped))
    }
    func testMalformedOversizedUnknownAndContradictoryPacketsRefused() throws {
        var p = packet(); p.version = 2; XCTAssertFalse(p.isValid)
        p = packet(); p.laneState = "QUIET_PERIMETER"; XCTAssertFalse(p.isValid)
        p = packet(); p.active = false; XCTAssertFalse(p.isValid)
        p = packet(); p.laneName = nil; XCTAssertFalse(p.isValid)
        p = packet(); p.status = String(repeating:"É",count:321); XCTAssertFalse(p.isValid)
        p = packet(); p.targetName = nil; XCTAssertFalse(p.isValid)
        XCTAssertNil(WatchGuideSnapshot.decode(Data(repeating:32,count:4097)))
        XCTAssertNil(WatchGuideSnapshot.decode(Data("{}".utf8)))
    }

    func testReceiptDeadlineRejectsClockStepsAndCannotReviveAfterExpiry() {
        let p = packet(); var scene = WatchGuideScene()
        XCTAssertTrue(scene.apply(p,now: Date(timeIntervalSince1970:1000),uptime:100))
        XCTAssertTrue(scene.isFresh(now: Date(timeIntervalSince1970:1019),uptime:119))
        XCTAssertFalse(scene.isFresh(now: Date(timeIntervalSince1970:1001),uptime:119))
        XCTAssertFalse(scene.isFresh(now: Date(timeIntervalSince1970:1030),uptime:101))
        XCTAssertFalse(scene.isFresh(now: Date(timeIntervalSince1970:1001),uptime:121))
        XCTAssertEqual(scene.displayStatus(now: Date(timeIntervalSince1970:1001),uptime:121),"Phone guidance expired · open phone")
    }
    func testReplayAndNewRevisionWithSameTimestampNeverRenewReceiptBudget() {
        let p = packet(); var scene = WatchGuideScene()
        XCTAssertTrue(scene.apply(p,now: Date(timeIntervalSince1970:1000),uptime:100))
        XCTAssertTrue(scene.apply(p,now: Date(timeIntervalSince1970:1001),uptime:119))
        XCTAssertTrue(scene.isFresh(now: Date(timeIntervalSince1970:1001),uptime:119))
        XCTAssertFalse(scene.isFresh(now: Date(timeIntervalSince1970:1002),uptime:121))
        var changed = p; changed.revision = 2; changed.status = "Crossed right"; changed.laneState = "OUT_RIGHT"
        XCTAssertTrue(scene.apply(changed,now: Date(timeIntervalSince1970:1002),uptime:121))
        XCTAssertFalse(scene.isFresh(now: Date(timeIntervalSince1970:1002),uptime:121))
        changed.revision = 3; changed.at = 1_003_000
        XCTAssertTrue(scene.apply(changed,now: Date(timeIntervalSince1970:1003),uptime:122))
        XCTAssertTrue(scene.isFresh(now: Date(timeIntervalSince1970:1003),uptime:122))
        XCTAssertFalse(scene.apply(p,now: Date(timeIntervalSince1970:1003),uptime:122))
    }
    func testCacheReloadPreservesDeadlineAndRefusesRebootOrClockChange() throws {
        var scene = WatchGuideScene(); XCTAssertTrue(scene.apply(packet(),now: Date(timeIntervalSince1970:1005),uptime:100))
        let cached = try XCTUnwrap(WatchGuideScene.decodeCache(try XCTUnwrap(scene.encodedCache())))
        XCTAssertEqual(cached.snapshot,packet())
        XCTAssertTrue(cached.isFresh(now: Date(timeIntervalSince1970:1019),uptime:114))
        XCTAssertFalse(cached.isFresh(now: Date(timeIntervalSince1970:1021),uptime:116))
        XCTAssertFalse(cached.isFresh(now: Date(timeIntervalSince1970:1006),uptime:1))
        XCTAssertFalse(cached.isFresh(now: Date(timeIntervalSince1970:1001),uptime:101))
    }
    func testLegacyCacheKeepsOrderingButNeedsNewLivePacket() {
        let p = packet(); var scene = WatchGuideScene.legacy(p)
        XCTAssertEqual(scene.snapshot,p); XCTAssertNil(scene.encodedCache())
        XCTAssertFalse(scene.isFresh(now: Date(timeIntervalSince1970:1000),uptime:100))
        XCTAssertFalse(scene.apply(p,now: Date(timeIntervalSince1970:1000),uptime:100))
        var fresh = p; fresh.revision = 2
        XCTAssertTrue(scene.apply(fresh,now: Date(timeIntervalSince1970:1001),uptime:101))
        XCTAssertTrue(scene.isFresh(now: Date(timeIntervalSince1970:1001),uptime:101))
        scene.clear(); XCTAssertNil(scene.snapshot); XCTAssertFalse(scene.isFresh(now: Date(timeIntervalSince1970:1001),uptime:101))
    }
    func testMalformedCacheFuturePacketAndInvalidClocksAreRefused() throws {
        var scene = WatchGuideScene(); var p = packet(); p.at = 1_003_000
        XCTAssertFalse(scene.apply(p,now: Date(timeIntervalSince1970:1000),uptime:100))
        XCTAssertFalse(scene.apply(packet(),now: Date(timeIntervalSince1970:1000),uptime:.nan))
        XCTAssertTrue(scene.apply(packet(),now: Date(timeIntervalSince1970:1000),uptime:100))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(scene.encodedCache())) as? [String:Any])
        raw["deadline"] = 121
        XCTAssertNil(WatchGuideScene.decodeCache(try JSONSerialization.data(withJSONObject:raw)))
        XCTAssertNil(WatchGuideScene.decodeCache(Data(repeating:32,count:8193)))
        XCTAssertNil(WatchGuideScene.decodeCache(Data("{}".utf8)))
    }
}
