import Foundation
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor final class WatchContextBudgetTests: XCTestCase {
    func testIndependentRemoteContextFitsAndPreservesLocalMapAndGuide() throws {
        let remote = WatchTAKSnapshot(sourceID:"phone",revision:1,at:1_000_000,enabled:false,connected:false)
        let map = Data(repeating:1,count:48*1024),guide = Data(repeating:2,count:1024)
        let context = try XCTUnwrap(WatchPhoneBridge.boundedContext([WatchMapSnapshot.contextKey:map,WatchGuideSnapshot.contextKey:guide,WatchSnapshot.contextKey:Data(repeating:3,count:1024)],tak:remote))
        XCTAssertEqual(context[WatchMapSnapshot.contextKey] as? Data,map)
        XCTAssertEqual(context[WatchGuideSnapshot.contextKey] as? Data,guide)
        XCTAssertEqual(WatchTAKSnapshot.decode(try XCTUnwrap(context[WatchTAKSnapshot.contextKey] as? Data)),remote)
        XCTAssertLessThanOrEqual(try PropertyListSerialization.data(fromPropertyList:context,format:.binary,options:0).count,60*1024)
    }
    func testOversizedMapGetsExplicitCacheWarningAndRemoteClearStillTravels() throws {
        let remote = WatchTAKSnapshot(sourceID:"phone",revision:2,at:1_000_001,enabled:false,connected:false)
        let context = try XCTUnwrap(WatchPhoneBridge.boundedContext([WatchMapSnapshot.contextKey:Data(repeating:0,count:60*1024),WatchSnapshot.contextKey:Data([1])],tak:remote))
        XCTAssertNil(context[WatchMapSnapshot.contextKey]); XCTAssertNotNil(context["gridfix.map.error"])
        XCTAssertEqual(WatchTAKSnapshot.decode(try XCTUnwrap(context[WatchTAKSnapshot.contextKey] as? Data)),remote)
        XCTAssertNil(WatchPhoneBridge.boundedContext([WatchSnapshot.contextKey:Data(repeating:0,count:70*1024)],tak:remote))
    }
}
