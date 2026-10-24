import XCTest
@testable import GridFixCore

final class WatchFixPolicyTests: XCTestCase {
    func testRejectsMalformedLocationSamplesBeforeDisplay() {
        XCTAssertTrue(WatchFixPolicy.accepts(lat: 24, lon: 54, accuracy: 500, age: 20))
        for bad in [Double.infinity, -.infinity, .nan, -1] {
            XCTAssertFalse(WatchFixPolicy.accepts(lat: 24, lon: 54, accuracy: bad, age: 0))
            XCTAssertFalse(WatchFixPolicy.accepts(lat: 24, lon: 54, accuracy: 5, age: bad))
        }
        XCTAssertFalse(WatchFixPolicy.accepts(lat: .nan, lon: 54, accuracy: 5, age: 0))
        XCTAssertFalse(WatchFixPolicy.accepts(lat: 24, lon: 181, accuracy: 5, age: 0))
    }

    func testAuthorizationPrecisionAndForegroundImmediatelyGateFreshFix() {
        func usable(_ authorized: Bool = true, _ precise: Bool = true, _ foreground: Bool = true,
                    _ accuracy: Double = 5, _ now: Double = 101) -> Bool {
            WatchFixPolicy.isUsable(authorized: authorized, precise: precise, foreground: foreground,
                                    lat: 24, lon: 54, accuracy: accuracy, timestampUptime: 100, nowUptime: now)
        }
        XCTAssertTrue(usable())
        XCTAssertFalse(usable(false))
        XCTAssertFalse(usable(true, false))
        XCTAssertFalse(usable(true, true, false))
        XCTAssertFalse(usable(true, true, true, 26))
        XCTAssertFalse(usable(true, true, true, 5, 111))
    }

    func testMalformedAndHugeAgeFormattingDoesNotTrap() {
        XCTAssertEqual(WatchFixPolicy.ageLabel(.infinity), "AGE UNKNOWN")
        XCTAssertEqual(WatchFixPolicy.ageLabel(.nan), "AGE UNKNOWN")
        XCTAssertEqual(WatchFixPolicy.ageLabel(-1), "CLOCK CHANGED")
        XCTAssertEqual(WatchFixPolicy.ageLabel(60), "1M AGO")
        XCTAssertTrue(WatchFixPolicy.ageLabel(.greatestFiniteMagnitude).hasSuffix("D AGO"))
    }
}
