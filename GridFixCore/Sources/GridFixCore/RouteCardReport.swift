import Foundation

extension RouteCard {
    public struct Configuration: Equatable,Sendable {
        public var northReference: Int
        public var units: DistanceUnit
        public var angleUnit: AngleUnit
        public var pacePer100m: Int
        public init(northReference: Int = 0,units: DistanceUnit = .metric,angleUnit: AngleUnit = .degrees,pacePer100m: Int = 65) {
            self.northReference = northReference; self.units = units; self.angleUnit = angleUnit; self.pacePer100m = pacePer100m
        }
        public var referenceLetter: String { northReference == 1 ? "M" : northReference == 2 ? "G" : "T" }
    }
    public struct Row: Equatable,Sendable {
        public var index: Int
        public var azimuth: String
        public var backAzimuth: String
        public var distance: String
        public var paces: Int
        public var destinationGrid: String
        public var distanceMeters: Double
        public var limits: String? = nil
    }
    public struct Report: Equatable,Sendable {
        public let name: String
        public let points: [GeoPoint]
        public let configuration: Configuration
        public let generatedAt: Date
        public let startGrid: String
        public let rows: [Row]
        public let totalMeters: Double
        public let totalPaces: Int
        public var notes: [String]
        public var dtg: String { Format.dtg(generatedAt) }
        public var totalDistance: String { Format.distance(meters: totalMeters,unit: configuration.units) }
        public var shareText: String {
            var lines = ["GRIDFIX ROUTE CARD - "+name.uppercased(with: Locale(identifier: "en_US_POSIX")),"START "+startGrid]
            lines += rows.flatMap { row -> [String] in
                var text = ["LEG \(row.index): \(row.azimuth) \(configuration.referenceLetter) / back \(row.backAzimuth) - \(row.distance) - \(row.paces) paces -> \(row.destinationGrid)"]
                if let limits = row.limits { text.append("  "+limits) }
                return text
            }
            lines += ["TOTAL \(totalDistance) - \(totalPaces) paces","Azimuth from leg start; back-azimuth from leg end.","North \(configuration.referenceLetter) - pace \(configuration.pacePer100m)/100 m - \(dtg)"]
            lines += notes
            return lines.joined(separator: "\n")
        }
    }
    public enum Failure: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
    }
    public static func report(name: String,points: [GeoPoint],configuration: Configuration,
                              generatedAt: Date = Date(),legLimits: [String?] = [],declination: (GeoPoint) -> Double?) throws -> Report {
        guard (2...250_000).contains(points.count), points.allSatisfy({ TrackCodec.validCoordinates($0.lat,$0.lon) }),
              (0...2).contains(configuration.northReference), (1...1000).contains(configuration.pacePer100m) else {
            throw Failure.invalid("Choose a route with 2-250,000 valid points and a pace count from 1-1,000 per 100 m.")
        }
        guard legLimits.isEmpty || legLimits.count == points.count-1 else { throw Failure.invalid("Lane limits must match the route's legs") }
        var rows: [Row] = [], missingReference = false, unavailableGrid = false
        for index in 0..<(points.count-1) {
            try Task.checkCancellation()
            let leg = legs(points: [points[index],points[index+1]],northReference: configuration.northReference,pacePer100m: configuration.pacePer100m,declination: declination)[0]
            func angle(_ value: Double?) -> String {
                guard let value, value.isFinite else { missingReference = true; return "UNAVAILABLE" }
                return Format.angle(degrees: value,unit: configuration.angleUnit)
            }
            let grid = MGRS.parts(lat: points[index+1].lat,lon: points[index+1].lon,digits: 8)?.full
            if grid == nil { unavailableGrid = true }
            rows.append(.init(index: index+1,azimuth: angle(leg.forward),backAzimuth: angle(leg.reverse),distance: Format.distance(meters: leg.distanceMeters,unit: configuration.units),paces: leg.paces,destinationGrid: grid ?? "UNAVAILABLE",distanceMeters: leg.distanceMeters,limits: legLimits.isEmpty ? nil : legLimits[index]))
        }
        let start = MGRS.parts(lat: points[0].lat,lon: points[0].lon,digits: 8)?.full
        var notes: [String] = []
        if missingReference { notes.append("Some bearings are unavailable in the selected north reference; no true-north fallback was substituted.") }
        if unavailableGrid || start == nil { notes.append("Some points are outside MGRS/UTM coverage; no grid was invented.") }
        if rows.contains(where: { $0.distanceMeters == 0 }) { notes.append("Zero-length legs have coincident endpoints; their azimuths are not meaningful.") }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Report(name: title.isEmpty ? "Route" : title,points: points,configuration: configuration,generatedAt: generatedAt,startGrid: start ?? "UNAVAILABLE",rows: rows,totalMeters: rows.reduce(0) { $0+$1.distanceMeters },totalPaces: rows.reduce(0) { $0+$1.paces },notes: notes)
    }
}

/// True-north-up equirectangular sketch, unwrapped leg by leg across the dateline.
/// It is a route schematic, not a basemap or a guaranteed ground scale.
public enum RouteSketch {
    public struct Point: Equatable,Sendable { public var x: Double; public var y: Double }
    public struct ScaleBar: Equatable,Sendable {
        public var meters: Double
        public var lengthPoints: Double
        public var label: String
    }
    public struct Layout: Equatable,Sendable {
        public var points: [Point]
        public var scaleBar: ScaleBar
    }
    public static func coordinates(_ points: [GeoPoint]) -> [Point] {
        guard !points.isEmpty else { return [] }
        let factor = cos(points.reduce(0) { $0+$1.lat }/Double(points.count)*Double.pi/180)
        var longitude = 0.0
        return points.enumerated().map { i,p in
            if i > 0 { longitude += TerrainGeometry.wrap(p.lon-points[i-1].lon) }
            return .init(x: longitude*factor,y: p.lat)
        }
    }
    public static func layout(_ points: [GeoPoint],width: Double,height: Double) throws -> Layout {
        guard !points.isEmpty, points.allSatisfy({ TrackCodec.validCoordinates($0.lat,$0.lon) }), width.isFinite,height.isFinite,width >= 120,height >= 120 else { throw RouteCard.Failure.invalid("Invalid route sketch bounds") }
        let sketch = coordinates(points)
        let minX = sketch.map(\.x).min()!, maxX = sketch.map(\.x).max()!, minY = sketch.map(\.y).min()!, maxY = sketch.map(\.y).max()!
        let spanX = max(1e-6,maxX-minX), spanY = max(1e-6,maxY-minY)
        // Reserve space for the north arrow and scale; neither masks route geometry.
        let usableW = width-68, usableH = height-96
        let scale = min(usableW/spanX,usableH/spanY)
        guard scale.isFinite, scale > 0 else { throw RouteCard.Failure.invalid("Invalid route sketch scale") }
        let ox = 34+(usableW-(maxX-minX)*scale)/2, oy = 54+(usableH-(maxY-minY)*scale)/2
        let plot = sketch.map { Point(x: ox+($0.x-minX)*scale,y: oy+(maxY-$0.y)*scale) }
        let metersPerPoint = 111_319.49/scale, target = metersPerPoint*width/3
        guard target.isFinite, target > 0 else { throw RouteCard.Failure.invalid("Invalid route scale bar") }
        let fixed = [100.0,200,250,500,1000,2000,2500,5000,10000]
        func nearest(_ candidates: [Double]) -> Double {
            candidates.dropFirst().reduce(candidates[0]) { abs($1-target) < abs($0-target) ? $1 : $0 }
        }
        var nice = nearest(fixed)
        if nice/metersPerPoint > width-24 || nice/metersPerPoint < 20 {
            let decade = pow(10,floor(log10(target)))
            nice = nearest([0.1,0.2,0.25,0.5,1,2,2.5,5,10].map { $0*decade })
        }
        let label: String
        if nice >= 1000 {
            label = nice.truncatingRemainder(dividingBy: 1000) == 0 ? String(format: "%.0f km",locale: Locale(identifier: "en_US_POSIX"),nice/1000) : String(format: "%.1f km",locale: Locale(identifier: "en_US_POSIX"),nice/1000)
        } else if nice >= 1 { label = String(format: nice.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f m" : "%.1f m",locale: Locale(identifier: "en_US_POSIX"),nice) }
        else { label = String(format: "%.2g m",locale: Locale(identifier: "en_US_POSIX"),nice) }
        return .init(points: plot,scaleBar: .init(meters: nice,lengthPoints: nice/metersPerPoint,label: label))
    }
}
