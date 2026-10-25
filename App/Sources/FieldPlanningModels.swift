import Foundation
import GridFixCore

struct FieldPlanningRequest: Identifiable {
    enum Kind { case sunMoon, declination }
    let id = UUID()
    let kind: Kind
    let centre: GeoPoint
    var date = Date()
    var timeZone = TimeZone.current
}

struct SunMoonPlan {
    struct Event: Identifiable { let id: String; let name: String; let local: String; let zulu: String }
    let dateLabel: String
    let sun: [Event]
    let moon: [Event]
    let phase: String
    let illumination: Int
    init(point: GeoPoint,date: Date,timeZone: TimeZone) throws {
        guard point.validPlanningPoint,date.timeIntervalSince1970.isFinite else { throw RouteCard.Failure.invalid("Choose a valid map location and planning date.") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year,.month,.day],from: date)
        guard let y = parts.year,let m = parts.month,let d = parts.day,(1...9999).contains(y) else { throw RouteCard.Failure.invalid("The planning date is outside the supported calendar range.") }
        let names = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]
        dateLabel = String(format: "%02d %@ %04d",d,names[m-1],y)
        let sunTimes = SunMoon.sunTimes(y: y,m: m,d: d,lat: point.lat,lon: point.lon)
        let moonInfo = SunMoon.moonInfo(y: y,m: m,d: d,lat: point.lat,lon: point.lon,timeZone: timeZone)
        func event(_ id: String,_ name: String,_ hour: Double?) -> Event {
            .init(id: id,name: name,local: SunMoon.formatLocal(hour,y: y,m: m,d: d,timeZone: timeZone),zulu: SunMoon.formatZulu(hour))
        }
        sun = [event("bmnt","BMNT",sunTimes.bmnt),event("civil-dawn","Civil dawn",sunTimes.civilDawn),event("sunrise","Sunrise",sunTimes.sunrise),event("sunset","Sunset",sunTimes.sunset),event("civil-dusk","Civil dusk",sunTimes.civilDusk),event("eent","EENT",sunTimes.eent)]
        moon = [event("moonrise","Moonrise",moonInfo.rises.first),event("moonset","Moonset",moonInfo.sets.first)]
        phase = moonInfo.phaseName; illumination = moonInfo.illuminationPct
    }
}

struct DeclinationDiagramReading {
    let magnetic: Double?
    let convergence: Double?
    let source: DeclinationSource
    let model: Double?
    let modelExpired: Bool
    let manual: Bool
    var gridMagneticAngle: Double? {
        guard let magnetic,let convergence else { return nil }; return abs(magnetic-convergence)
    }
    static func at(_ point: GeoPoint,date: Date,override: Double?,model: WMM? = WMM.bundled) -> Self {
        let valid = point.validPlanningPoint && date.timeIntervalSince1970.isFinite
        let automatic = valid ? DeclinationService(overrideDegrees: nil,model: model).declination(lat: point.lat,lon: point.lon,date: date,isCurrentPosition: false) : .init(degreesEast: nil,source: .none,modelExpired: false)
        let selected = valid ? DeclinationService(overrideDegrees: override,model: model).declination(lat: point.lat,lon: point.lon,date: date,isCurrentPosition: false) : automatic
        let magnetic = selected.degreesEast.flatMap { $0.isFinite ? $0 : nil }
        let convergence = valid && (-80...84).contains(point.lat) ? UTM.gridConvergence(lat: point.lat,lon: point.lon) : nil
        return .init(magnetic: magnetic,convergence: convergence,source: magnetic == nil ? .none : selected.source,model: automatic.degreesEast.flatMap { $0.isFinite ? $0 : nil },modelExpired: automatic.modelExpired,manual: override != nil)
    }
    static func eastWest(_ degrees: Double?) -> String {
        guard let degrees,degrees.isFinite else { return "Unavailable" }
        return String(format: "%.1f° %@",locale: Locale(identifier: "en_US_POSIX"),abs(degrees),degrees >= 0 ? "E" : "W")
    }
    static func displayAngle(_ degrees: Double) -> Double { degrees == 0 ? 0 : (degrees > 0 ? 1 : -1)*(8+min(24,abs(degrees)*2)) }
}

private extension GeoPoint {
    var validPlanningPoint: Bool { lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon) }
}
