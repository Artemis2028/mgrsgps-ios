import CoreLocation
import GridFixCore
import XCTest
@testable import MGRSGPS

final class MovementHeadingTests: XCTestCase {
    private func fix(course: Double? = 90,speed: Double? = 1.6,accuracy: Double = 5,uptime: Double = 100) -> Fix {
        .init(lat: 24.4539,lon: 54.3773,accuracyMeters: accuracy,altitudeMeters: nil,
              speedMetersPerSecond: speed,timestamp: Date(),timestampUptime: uptime,courseDegrees: course)
    }
    func testCoreLocationCourseSpeedAndTimestampBecomeTheActualFix() {
        let now = Date(timeIntervalSince1970: 1000)
        let location = CLLocation(coordinate: .init(latitude: 24.4539,longitude: 54.3773),altitude: 12,
                                  horizontalAccuracy: 5,verticalAccuracy: 3,course: 270,speed: 1.6,
                                  timestamp: now.addingTimeInterval(-3))
        let sample = Fix(location: location,now: now,uptime: 100)
        XCTAssertEqual(sample.courseDegrees,270); XCTAssertEqual(sample.speedMetersPerSecond,1.6)
        XCTAssertEqual(sample.timestampUptime,97); XCTAssertEqual(sample.altitudeMeters,12)
        let missing = CLLocation(coordinate: location.coordinate,altitude: 0,horizontalAccuracy: 5,
                                 verticalAccuracy: -1,course: -1,speed: -1,timestamp: now)
        let absent = Fix(location: missing,now: now,uptime: 100)
        XCTAssertNil(absent.courseDegrees); XCTAssertNil(absent.speedMetersPerSecond); XCTAssertNil(absent.altitudeMeters)
    }
    func testGlanceUsesTravelDirectionAndInstrumentsPreferTheCompass() {
        XCTAssertEqual(MovementHeading.position(face: .glance,compassTrue: 180,fix: fix()),.init(degreesTrue: 90,source: .course))
        for face in [PositionFace.lensatic,.dial] {
            XCTAssertEqual(MovementHeading.position(face: face,compassTrue: 180,fix: fix()),.init(degreesTrue: 180,source: .compass))
            XCTAssertEqual(MovementHeading.position(face: face,compassTrue: nil,fix: fix()),.init(degreesTrue: 90,source: .course))
        }
    }
    func testNavigationCourseFallbackRequiresMissingCompassAndUsableFix() {
        XCTAssertEqual(MovementHeading.navigation(hasCompass: false,compassTrue: nil,fix: fix(),nowUptime: 110),.init(degreesTrue: 90,source: .course))
        XCTAssertNil(MovementHeading.navigation(hasCompass: true,compassTrue: nil,fix: fix(),nowUptime: 100),"A bad/expired compass must not silently become GPS steering")
        XCTAssertEqual(MovementHeading.navigation(hasCompass: true,compassTrue: 180,fix: fix(),nowUptime: 100)?.source,.compass)
        XCTAssertNil(MovementHeading.navigation(hasCompass: false,compassTrue: nil,fix: fix(),nowUptime: 110.001))
        XCTAssertNil(MovementHeading.navigation(hasCompass: false,compassTrue: nil,fix: fix(accuracy: 25.01),nowUptime: 100))
        XCTAssertNil(MovementHeading.navigation(hasCompass: false,compassTrue: nil,fix: nil,nowUptime: 100))
    }
    func testStationarySlowMissingAndInvalidMotionCannotClaimCourse() {
        for speed in [nil,-1,0,0.5,Double.nan,Double.infinity] as [Double?] {
            XCTAssertNil(MovementHeading.position(face: .glance,compassTrue: nil,fix: fix(speed: speed)))
        }
        XCTAssertEqual(MovementHeading.position(face: .glance,compassTrue: nil,fix: fix(speed: 0.5001))?.degreesTrue,90)
        for course in [nil,-1,360,Double.nan,Double.infinity] as [Double?] {
            XCTAssertNil(MovementHeading.position(face: .glance,compassTrue: nil,fix: fix(course: course)))
        }
        XCTAssertEqual(MovementHeading.position(face: .glance,compassTrue: nil,fix: fix(course: 0))?.degreesTrue,0)
        XCTAssertEqual(MovementHeading.position(face: .glance,compassTrue: nil,fix: fix(course: 359.99))?.degreesTrue,359.99)
    }
    func testTrueCourseKeepsItsSourceWhileDisplayReferenceChanges() throws {
        let reading = try XCTUnwrap(MovementHeading.navigation(hasCompass: false,compassTrue: nil,fix: fix(course: 0),nowUptime: 100))
        XCTAssertEqual(reading.source,.course); XCTAssertEqual(reading.label,"GPS course")
        XCTAssertEqual(FieldMath.toNorthRef(angleTrue: reading.degreesTrue,north: .trueNorth,declinationEast: 12,convergence: 15),0)
        XCTAssertEqual(FieldMath.toNorthRef(angleTrue: reading.degreesTrue,north: .magnetic,declinationEast: 12,convergence: 15),348)
        XCTAssertEqual(FieldMath.toNorthRef(angleTrue: reading.degreesTrue,north: .grid,declinationEast: 12,convergence: 15),345)
        XCTAssertNil(FieldMath.toNorthRef(angleTrue: reading.degreesTrue,north: .magnetic,declinationEast: nil,convergence: 15))
        XCTAssertEqual(reading.degreesTrue,0,"A display reference must not rewrite the provider's true course")
    }
}
