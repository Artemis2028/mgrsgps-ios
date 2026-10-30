import Foundation
import GridFixCore

struct RouteCardRequest: Equatable,Sendable {
    let routeID: String
    let name: String
    let points: [GeoPoint]
    let configuration: RouteCard.Configuration
    let declinationOverride: Double?
    let lanes: [NavLane]
    let laneWaypoints: [Waypoint]
    let laneGraphics: [Backup.Graphic]

    @MainActor init(route: Backup.Graphic,settings: AppSettings,lanes: [NavLane] = [],waypoints: [Waypoint] = [],graphics: [Backup.Graphic] = []) {
        routeID = route.id; name = route.name; points = route.points.map { .init(lat: $0.lat,lon: $0.lon) }
        configuration = .init(northReference: settings.northRef.rawValue,units: settings.units,angleUnit: settings.angleUnit,pacePer100m: settings.pacePer100m)
        declinationOverride = settings.declinationOverride
        laneWaypoints = waypoints.filter { $0.sourceRouteId == route.id }
        let ids = Set(laneWaypoints.map(\.id))
        self.lanes = lanes.filter { $0.scope == .route ? $0.targetId == route.id : ids.contains($0.targetId) }
        let links = Set(self.lanes.flatMap { [$0.left.graphicId,$0.right.graphicId,$0.backstop.graphicId].compactMap { $0 } })
        laneGraphics = graphics.filter { links.contains($0.id) }
    }
    func matches(_ route: Backup.Graphic?) -> Bool {
        route?.id == routeID && route?.type == "route" && route?.name == name && route?.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) } == points
    }
}

enum RouteCardOutput {
    static func report(_ request: RouteCardRequest,date: Date = Date(),model: WMM? = WMM.bundled) throws -> RouteCard.Report {
        var expired = false
        let service = DeclinationService(overrideDegrees: request.declinationOverride,model: model)
        let route = Backup.Graphic(id: request.routeID,name: request.name,type: "route",points: request.points.map { .init(lat: $0.lat,lon: $0.lon) })
        let limits = NavLanes.legLimits(route: route,lanes: request.lanes,waypoints: request.laneWaypoints,graphics: request.laneGraphics)
        var report = try RouteCard.report(name: request.name,points: request.points,configuration: request.configuration,generatedAt: date,legLimits: limits) { point in
            let reading = service.declination(lat: point.lat,lon: point.lon,date: date,isCurrentPosition: false)
            expired = expired || reading.modelExpired
            return reading.degreesEast
        }
        if request.configuration.northReference == 1 {
            if expired { report.notes.append("The bundled magnetic model is past its validity period; these bearings use an extrapolation.") }
            if let override = request.declinationOverride {
                report.notes.append(String(format: "Manual declination: %.1f deg %@.",locale: Locale(identifier: "en_US_POSIX"),abs(override),override >= 0 ? "E" : "W"))
            }
        }
        return report
    }
}
