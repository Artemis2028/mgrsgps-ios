import XCTest
@testable import GridFixCore

final class WatchHeadingSampleTests: XCTestCase {
    func testFullCircleAndAcceptedAccuracyBoundaries() throws {
        for degrees in [0.0,359.999] {
            for accuracy in [0.0,25] {
                let sample = try XCTUnwrap(WatchHeadingSample(trueDegrees:degrees,accuracy:accuracy,
                    sampleUptime:100,sessionUptime:100,nowUptime:105))
                XCTAssertEqual(sample.trueDegrees,degrees)
                XCTAssertEqual(sample.accuracy,accuracy)
                XCTAssertTrue(sample.isFresh(nowUptime:105))
                XCTAssertFalse(sample.isFresh(nowUptime:105.001))
            }
        }
    }
    func testInvalidOrUncalibratedCompassNeverProducesHeading() {
        for degrees in [-1.0,360,Double.nan,Double.infinity] {
            XCTAssertNil(WatchHeadingSample(trueDegrees:degrees,accuracy:1,sampleUptime:100,sessionUptime:99,nowUptime:101))
        }
        for accuracy in [-1.0,25.001,Double.nan,Double.infinity] {
            XCTAssertNil(WatchHeadingSample(trueDegrees:90,accuracy:accuracy,sampleUptime:100,sessionUptime:99,nowUptime:101))
        }
    }
    func testCallbacksFromPreviousSessionAndFutureOrExpiredSamplesAreRejected() {
        XCTAssertNil(WatchHeadingSample(trueDegrees:90,accuracy:1,sampleUptime:99.999,sessionUptime:100,nowUptime:101))
        XCTAssertNil(WatchHeadingSample(trueDegrees:90,accuracy:1,sampleUptime:101.001,sessionUptime:100,nowUptime:101))
        XCTAssertNil(WatchHeadingSample(trueDegrees:90,accuracy:1,sampleUptime:100,sessionUptime:99,nowUptime:105.001))
        for bad in [0.0,Double.nan,Double.infinity] {
            XCTAssertNil(WatchHeadingSample(trueDegrees:90,accuracy:1,sampleUptime:100,sessionUptime:bad,nowUptime:101))
        }
    }
    func testMonotonicFreshnessCannotBeRevivedByClockRollback() throws {
        let sample = try XCTUnwrap(WatchHeadingSample(trueDegrees:90,accuracy:1,sampleUptime:100,sessionUptime:99,nowUptime:101))
        XCTAssertFalse(sample.isFresh(nowUptime:99))
        XCTAssertFalse(sample.isFresh(nowUptime:.nan))
        XCTAssertFalse(sample.isFresh(nowUptime:.infinity))
        XCTAssertNil(WatchHeadingSample(trueDegrees:90,accuracy:1,sampleUptime:.nan,sessionUptime:99,nowUptime:101))
        XCTAssertNil(WatchHeadingSample(trueDegrees:90,accuracy:1,sampleUptime:100,sessionUptime:99,nowUptime:.nan))
    }
    func testSteeringExpiresAtTwoSecondsWhileNumericReadoutCanRemainFresh() throws {
        let sample = try XCTUnwrap(WatchHeadingSample(trueDegrees:90,accuracy:1,sampleUptime:100,sessionUptime:99,nowUptime:100))
        XCTAssertTrue(sample.isFreshForSteering(nowUptime:102))
        XCTAssertFalse(sample.isFreshForSteering(nowUptime:102.001))
        XCTAssertTrue(sample.isFresh(nowUptime:104))
        XCTAssertFalse(sample.isFreshForSteering(nowUptime:99))
        XCTAssertFalse(sample.isFreshForSteering(nowUptime:.nan))
    }

}
