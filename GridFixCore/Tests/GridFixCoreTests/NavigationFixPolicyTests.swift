import XCTest
@testable import GridFixCore

final class NavigationFixPolicyTests: XCTestCase {
    func testNavigationFreshnessAndAccuracyBoundariesMatchAndroid() {
        XCTAssertTrue(usable(accuracy: 25, timestamp: 100, now: 110))
        XCTAssertFalse(usable(accuracy: 25.01, timestamp: 100, now: 110))
        XCTAssertFalse(usable(accuracy: 5, timestamp: 100, now: 110.001))
        XCTAssertFalse(usable(accuracy: -1, timestamp: 100, now: 101))
    }

    func testFutureMissingAndNonfiniteSamplesAreUnavailable() {
        XCTAssertFalse(usable(accuracy: 5, timestamp: 101, now: 100))
        XCTAssertFalse(usable(accuracy: 5, timestamp: 0, now: 1))
        XCTAssertFalse(usable(accuracy: .nan, timestamp: 100, now: 101))
        XCTAssertFalse(usable(accuracy: 5, timestamp: .nan, now: 101))
        XCTAssertFalse(NavigationFixPolicy.isUsable(lat: 91, lon: 54, accuracyMeters: 5, timestampUptime: 100, nowUptime: 101))
    }

    func testAccuracyCircleMustFitEntirelyInsideArrivalRadius() {
        XCTAssertTrue(NavigationFixPolicy.insideArrivalRadius(distanceMeters: 39, accuracyMeters: 10))
        XCTAssertFalse(NavigationFixPolicy.insideArrivalRadius(distanceMeters: 40, accuracyMeters: 10))
        XCTAssertFalse(NavigationFixPolicy.insideArrivalRadius(distanceMeters: 49, accuracyMeters: 5))
        XCTAssertFalse(NavigationFixPolicy.insideArrivalRadius(distanceMeters: .nan, accuracyMeters: 5))
    }

    private func usable(accuracy: Double, timestamp: TimeInterval, now: TimeInterval) -> Bool {
        NavigationFixPolicy.isUsable(lat: 24, lon: 54, accuracyMeters: accuracy, timestampUptime: timestamp, nowUptime: now)
    }
}
