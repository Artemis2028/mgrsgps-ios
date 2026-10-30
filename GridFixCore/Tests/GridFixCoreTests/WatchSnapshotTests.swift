import Foundation
import XCTest
@testable import GridFixCore

final class WatchSnapshotTests: XCTestCase {
    func testCompleteSnapshotReplacesAndExplicitlyClearsCachedTarget() throws {
        let target = WatchSnapshot.Target(id: "selected", name: "Rally", lat: 24.4539, lon: 54.3773)
        var cached = WatchSnapshot(target: target, nightMode: true, mgrsDigits: 8, units: 2, angleUnit: 1, northRef: 2)
        XCTAssertEqual(WatchSnapshot.decode(try JSONEncoder().encode(cached)), cached)
        let clear = WatchSnapshot(target: nil)
        cached = try XCTUnwrap(WatchSnapshot.decode(JSONEncoder().encode(clear)))
        XCTAssertNil(cached.target)
        XCTAssertFalse(cached.nightMode)
    }

    func testRejectsUnknownOrMalformedWireValues() throws {
        var payload = WatchSnapshot()
        payload.version = 2
        XCTAssertNil(WatchSnapshot.decode(try JSONEncoder().encode(payload)))
        payload.version = 1
        payload.mgrsDigits = 9
        XCTAssertFalse(payload.isValid)
        payload.mgrsDigits = 10
        payload.target = .init(id: "x", name: "Bad", lat: 91, lon: 0)
        XCTAssertFalse(payload.isValid)
        payload.target = nil
        payload.northRef = 99
        XCTAssertFalse(payload.isValid)
        payload.northRef = 0
        payload.declinationOverride = .nan
        XCTAssertFalse(payload.isValid)
    }

    func testReferenceConversionsAndExpiredMagneticModel() throws {
        var payload = WatchSnapshot()
        XCTAssertEqual(payload.bearing(trueDegrees: 361, lat: 24, lon: 54), 1)
        payload.northRef = 1
        payload.declinationOverride = 7
        XCTAssertEqual(payload.bearing(trueDegrees: 3, lat: 24, lon: 54), 356)
        payload.declinationOverride = nil
        XCTAssertNil(payload.bearing(trueDegrees: 3, lat: 24, lon: 54,
                                     date: Date(timeIntervalSince1970: 2_524_608_000)))
        payload.northRef = 2
        let actual = try XCTUnwrap(payload.bearing(trueDegrees: 90, lat: 24, lon: 54))
        let expected = (90 - UTM.gridConvergence(lat: 24, lon: 54) + 360).truncatingRemainder(dividingBy: 360)
        XCTAssertEqual(actual, expected, accuracy: 1e-9)
    }
}
