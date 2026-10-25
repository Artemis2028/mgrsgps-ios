import GridFixCore
import XCTest
@testable import MGRSGPS

final class FieldPlanningTests: XCTestCase {
    private func day(_ y: Int,_ m: Int,_ d: Int,_ zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: y,month: m,day: d,hour: 12))!
    }
    func testAlmanacUsesRequestedLocalDateAndAndroidTimes() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Dubai"))
        let plan = try SunMoonPlan(point: .init(lat: 24.4539,lon: 54.3773),date: day(2026,6,21,zone),timeZone: zone)
        XCTAssertEqual(plan.dateLabel,"21 JUN 2026"); XCTAssertEqual(plan.sun.count,6); XCTAssertEqual(plan.moon.count,2)
        XCTAssertEqual(plan.sun[0].local,"0438"); XCTAssertEqual(plan.sun[0].zulu,"0038Z")
        XCTAssertEqual(plan.phase,"First quarter"); XCTAssertEqual(plan.illumination,46)
        XCTAssertEqual(plan.moon.last?.local,"----")
    }
    func testPolarCrossingsStayAbsentAndInvalidLocationCannotReachMoonIntegerConversion() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Arctic/Longyearbyen"))
        let plan = try SunMoonPlan(point: .init(lat: 78.22,lon: 15.65),date: day(2026,6,21,zone),timeZone: zone)
        XCTAssertEqual(plan.sun.first { $0.id == "sunrise" }?.local,"----")
        XCTAssertEqual(plan.sun.first { $0.id == "sunset" }?.zulu,"----")
        XCTAssertThrowsError(try SunMoonPlan(point: .init(lat: .nan,lon: 0),date: Date(),timeZone: zone))
    }
    func testManualDeclinationModelComparisonAndGridMagneticAngle() throws {
        let date = Date(timeIntervalSince1970: 1792886400)
        let value = DeclinationDiagramReading.at(.init(lat: 24,lon: 54),date: date,override: 10)
        XCTAssertEqual(value.magnetic,10); XCTAssertEqual(value.source,.override); XCTAssertTrue(value.manual)
        XCTAssertNotNil(value.model); XCTAssertNotEqual(value.model,10)
        XCTAssertEqual(try XCTUnwrap(value.convergence),-1.2211,accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(value.gridMagneticAngle),11.2211,accuracy: 0.0001)
        let zero = DeclinationDiagramReading.at(.init(lat: 0,lon: 3),date: date,override: 0,model: nil)
        XCTAssertEqual(zero.magnetic,0); XCTAssertEqual(zero.gridMagneticAngle,0)
        XCTAssertEqual(DeclinationDiagramReading.eastWest(zero.magnetic),"0.0° E")
    }
    func testMissingExpiredPolarAndNonfiniteReferencesAreExplicit() {
        let date = Date(timeIntervalSince1970: 2082758400)
        let missing = DeclinationDiagramReading.at(.init(lat: 24,lon: 54),date: date,override: nil,model: nil)
        XCTAssertNil(missing.magnetic); XCTAssertNil(missing.gridMagneticAngle); XCTAssertEqual(missing.source,.none)
        XCTAssertNotNil(missing.convergence)
        let expired = DeclinationDiagramReading.at(.init(lat: 24,lon: 54),date: date,override: nil)
        XCTAssertTrue(expired.modelExpired)
        let polar = DeclinationDiagramReading.at(.init(lat: 85,lon: 0),date: date,override: 10)
        XCTAssertNil(polar.convergence); XCTAssertNil(polar.gridMagneticAngle); XCTAssertEqual(polar.magnetic,10)
        XCTAssertNil(DeclinationDiagramReading.at(.init(lat: 24,lon: 54),date: date,override: .nan).magnetic)
    }
    func testPositionSolarRowsUsePhoneLocalDayAndExplicitLocalZuluSuffixes() throws {
        let zone=try XCTUnwrap(TimeZone(identifier:"Asia/Dubai"))
        let point=GeoPoint(lat:24.4539,lon:54.3773),date=day(2026,1,15,zone)
        let readout=PositionSunReadout(point:point,date:date,timeZone:zone)
        let plan=try SunMoonPlan(point:point,date:date,timeZone:zone)
        XCTAssertEqual(readout.events.map(\.id),["BMNT","SR","SS","EENT"])
        for (row,event) in zip(readout.events,[plan.sun[0],plan.sun[2],plan.sun[3],plan.sun[5]]) {
            XCTAssertEqual(row.value,event.local+"L "+event.zulu)
        }
        let polar=PositionSunReadout(point:.init(lat:89,lon:0),date:day(2026,6,21,zone),timeZone:zone)
        XCTAssertTrue(polar.events.allSatisfy{$0.value == "----"})
        let utc=TimeZone(secondsFromGMT:0)!
        let zulu=PositionSunReadout(point:point,date:date,timeZone:utc)
        XCTAssertNotEqual(zulu.zone,readout.zone)
        XCTAssertNotEqual(zulu.events.first?.value,readout.events.first?.value)
    }

}
