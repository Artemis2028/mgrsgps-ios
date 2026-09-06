import XCTest
@testable import GridFixCore

/// Light data drives movement planning; event ordering is the invariant.
final class SunMoonTests: XCTestCase {

    func testTwilightBracketsTheDayInOrder() {
        let t = SunMoon.sunTimes(y: 2026, m: 6, d: 21, lat: 24.4539, lon: 54.3773)
        XCTAssertNotNil(t.bmnt)
        XCTAssertNotNil(t.sunrise)
        XCTAssertNotNil(t.sunset)
        XCTAssertNotNil(t.eent)
        XCTAssertLessThan(t.bmnt!, t.sunrise!)
        XCTAssertLessThan(t.sunrise!, t.sunset!)
        XCTAssertLessThan(t.sunset!, t.eent!)
    }

    func testZuluFormattingIsFourDigitsAndAZ() {
        let s = SunMoon.formatZulu(5.5)
        XCTAssertEqual(s, "0530Z")
    }

    func testPolarDayReportsNoSunriseRatherThanAWrongOne() {
        let t = SunMoon.sunTimes(y: 2026, m: 6, d: 21, lat: 78.22, lon: 15.65)
        XCTAssertTrue(t.sunrise == nil || t.sunset == nil,
                      "polar day should have no sunrise/sunset")
    }
}
