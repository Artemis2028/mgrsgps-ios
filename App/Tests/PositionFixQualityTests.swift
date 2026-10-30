import CoreLocation
import UIKit
import XCTest
@testable import MGRSGPS

final class PositionFixQualityTests: XCTestCase {
    private func fix(accuracy: Double = 5, uptime: Double = 100, wall: Date = Date()) -> Fix {
        .init(lat: 24.4539,lon: 54.3773,accuracyMeters: accuracy,altitudeMeters: nil,
              speedMetersPerSecond: nil,timestamp: wall,timestampUptime: uptime)
    }
    func testAndroidAccuracyAndTrustBoundariesWithoutInventedSatelliteOrProviderCaps() {
        // Expected values transcribed from Android faces/Faces.kt, not iOS code.
        let fixtures: [(Double,Int,Int,String)] = [(0,5,10,"EXCELLENT"),(1,5,10,"EXCELLENT"),
            (1.01,5,8,"EXCELLENT"),(5,5,8,"EXCELLENT"),(5.01,4,6,"GOOD"),(10,4,6,"GOOD"),
            (10.01,3,6,"FAIR"),(20,3,6,"FAIR"),(20.01,2,6,"POOR"),(50,2,6,"POOR"),(50.01,1,4,"DEGRADED")]
        for (accuracy,bars,trust,word) in fixtures {
            let quality = PositionFixQuality(fix: fix(accuracy: accuracy),nowUptime: 100)
            XCTAssertEqual(quality.bars,bars,"accuracy \(accuracy)")
            XCTAssertEqual(quality.trustDigits,trust,"accuracy \(accuracy)")
            XCTAssertEqual(quality.word,word,"accuracy \(accuracy)")
        }
    }
    func testStaleWholeSecondBoundaryAndWallClockIndependence() {
        for age in [10.0,30,30.999] {
            XCTAssertFalse(PositionFixQuality(fix: fix(),nowUptime: 100+age).stale)
        }
        for wall in [Date(timeIntervalSince1970: 0),Date.distantFuture] {
            let quality = PositionFixQuality(fix: fix(wall: wall),nowUptime: 131)
            XCTAssertTrue(quality.stale); XCTAssertEqual(quality.word,"STALE")
            XCTAssertEqual(quality.bars,1); XCTAssertEqual(quality.trustDigits,4)
            XCTAssertEqual(quality.ageText,"31 s")
        }
        XCTAssertEqual(PositionFixQuality(fix: fix(),nowUptime: 290).ageText,"3 m 10 s")
        XCTAssertEqual(PositionFixQuality(fix: fix(),nowUptime: 3700).ageText,">1 h")
    }
    func testInvalidAccuracyAndMonotonicTimesCannotClaimExcellentOrFresh() {
        for accuracy in [-1,Double.nan,Double.infinity] {
            XCTAssertEqual(PositionFixQuality(fix: fix(accuracy: accuracy),nowUptime: 100).word,"NO FIX")
        }
        for uptime in [0,-1,Double.nan,Double.infinity,200] {
            let quality = PositionFixQuality(fix: fix(uptime: uptime),nowUptime: 100)
            XCTAssertTrue(quality.stale); XCTAssertNil(quality.ageSeconds)
        }
    }
    @MainActor
    func testActualMainLocationManagerFollowsInterfaceRatherThanDeviceNames() {
        let manager = CLLocationManager(), pocketManager = CLLocationManager()
        let pocket = CoreLocationNavigationDriver(compass: pocketManager)
        defer { pocket.stop() }
        let actual = LocationService(manager: manager)
        actual.setDisplayOrientation(.landscapeRight); XCTAssertEqual(manager.headingOrientation,.landscapeLeft)
        actual.setDisplayOrientation(.landscapeLeft); XCTAssertEqual(manager.headingOrientation,.landscapeRight)
        actual.setDisplayOrientation(.portraitUpsideDown); XCTAssertEqual(manager.headingOrientation,.portraitUpsideDown)
        actual.setDisplayOrientation(.unknown); XCTAssertEqual(manager.headingOrientation,.portraitUpsideDown)
        actual.setDisplayOrientation(.portrait); XCTAssertEqual(manager.headingOrientation,.portrait)
        // Actual pocket driver retains the physical top edge independently.
        XCTAssertEqual(pocketManager.headingOrientation,.portrait)
    }
    func testStoppedCompassSamplesExpireAndFutureTimesAreRejected() {
        XCTAssertTrue(DisplayHeadingPolicy.isFresh(timestampUptime: 100,nowUptime: 102))
        XCTAssertFalse(DisplayHeadingPolicy.isFresh(timestampUptime: 100,nowUptime: 102.001))
        for stamp in [0,-1,Double.nan,Double.infinity,104] {
            XCTAssertFalse(DisplayHeadingPolicy.isFresh(timestampUptime: stamp,nowUptime: 103))
        }
    }
}
