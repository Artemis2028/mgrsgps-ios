import Foundation

/// Android GraphicExportGeometry.kt: export visible ring/sector outlines rather than their handles.
struct GraphicExportGeometry {
    let points: [GeoPoint]
    let area: Bool
    static func make(_ graphic: Backup.Graphic) -> Self? {
        let points = graphic.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) }
        guard let center = points.first, points.allSatisfy({ TrackCodec.validCoordinates($0.lat,$0.lon) }) else { return nil }
        func range(_ edge: GeoPoint) -> Double { Geodesy.greatCircleMeters(center.lat,center.lon,edge.lat,edge.lon) }
        switch graphic.type {
        case "ring":
            guard points.count >= 2, range(points[1]) > 0 else { return nil }
            let ring = (0..<72).map { destination(center,range(points[1]),Double($0)*5) }
            return .init(points: ring+[ring[0]],area: false)
        case "sector":
            guard points.count >= 3 else { return nil }
            let radius = max(range(points[1]),range(points[2])); guard radius > 0 else { return nil }
            let left = Geodesy.greatCircleBearing(center.lat,center.lon,points[1].lat,points[1].lon)
            let right = Geodesy.greatCircleBearing(center.lat,center.lon,points[2].lat,points[2].lon)
            var sweep = (right-left+360).truncatingRemainder(dividingBy: 360); if sweep == 0 { sweep = 360 }
            let steps = max(1,min(72,Int(ceil(sweep/5))))
            let arc = (0...steps).map { destination(center,radius,left+sweep*Double($0)/Double(steps)) }
            return .init(points: [center]+arc,area: true)
        default: return .init(points: points,area: GraphicTypes.isArea(graphic.type) && points.count >= 3)
        }
    }
    private static func destination(_ start: GeoPoint,_ metres: Double,_ bearing: Double) -> GeoPoint {
        let angle = metres/6_371_008.8, heading = bearing*Double.pi/180
        let lat = start.lat*Double.pi/180, lon = start.lon*Double.pi/180
        let endLat = asin(max(-1,min(1,sin(lat)*cos(angle)+cos(lat)*sin(angle)*cos(heading))))
        let endLon = lon+atan2(sin(heading)*sin(angle)*cos(lat),cos(angle)-sin(lat)*sin(endLat))
        return .init(lat: endLat*180/Double.pi,lon: TerrainGeometry.wrap(endLon*180/Double.pi))
    }
    static func prefix(_ type: String) -> String {
        ["phase_line":"PL ","objective":"OBJ ","aa":"AA ","lz":"LZ ","pz":"PZ ","bp":"BP ","ea":"EA ","nai":"NAI ","tai":"TAI ","trp":"TRP ","checkpoint":"CP ","dp":"DP "][type] ?? ""
    }
}
