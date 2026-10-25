import XCTest
@testable import GridFixCore

final class AndroidSunMoonParityTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let y: Int, m: Int, d: Int
        let lat: Double, lon: Double
        let zone: String
        let sunUT: [Double?]
        let local: [String], zulu: [String]
        let phase: String
        let illumination: Int
        let rises: [Double], sets: [Double]
    }
    func testUnmodifiedAndroidSourceVectorsAcrossZonesDatelineAndPolarSeasons() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "android-sunmoon",withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self,from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.count,8)
        for f in fixtures {
            let zone = try XCTUnwrap(TimeZone(identifier: f.zone))
            let sun = SunMoon.sunTimes(y: f.y,m: f.m,d: f.d,lat: f.lat,lon: f.lon)
            let times = [sun.bmnt,sun.civilDawn,sun.sunrise,sun.sunset,sun.civilDusk,sun.eent]
            for i in times.indices {
                if let expected = f.sunUT[i] { XCTAssertEqual(try XCTUnwrap(times[i]),expected,accuracy: 1e-9,f.name) }
                else { XCTAssertNil(times[i],f.name) }
            }
            XCTAssertEqual(times.map { SunMoon.formatLocal($0,y: f.y,m: f.m,d: f.d,timeZone: zone) },f.local,f.name)
            XCTAssertEqual(times.map { SunMoon.formatZulu($0) },f.zulu,f.name)
            let moon = SunMoon.moonInfo(y: f.y,m: f.m,d: f.d,lat: f.lat,lon: f.lon,timeZone: zone)
            XCTAssertEqual(moon.phaseName,f.phase,f.name); XCTAssertEqual(moon.illuminationPct,f.illumination,f.name)
            XCTAssertEqual(moon.rises.count,f.rises.count,f.name); XCTAssertEqual(moon.sets.count,f.sets.count,f.name)
            for (actual,expected) in zip(moon.rises,f.rises) { XCTAssertEqual(actual,expected,accuracy: 1e-8,f.name) }
            for (actual,expected) in zip(moon.sets,f.sets) { XCTAssertEqual(actual,expected,accuracy: 1e-8,f.name) }
        }
    }
}
