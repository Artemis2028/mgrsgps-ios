import GridFixCore
import SwiftUI

struct MapRulerCard: View {
    let anchor: GeoPoint
    let target: GeoPoint
    var reset: () -> Void
    var close: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var location: LocationService
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var body: some View {
        let fix = location.usableFix
        let reading = DeclinationService(overrideDegrees: settings.declinationOverride).declination(
            lat: fix?.lat ?? target.lat,lon: fix?.lon ?? target.lon,heightMeters: fix?.altitudeMeters ?? 0,isCurrentPosition: false)
        let value = MapMeasurement.ruler(from: anchor,to: target,northReference: settings.northRef.rawValue,declination: reading.degreesEast)
        VStack(alignment: .leading,spacing: 8) {
            HStack {
                Text("Ruler · anchor → crosshair").font(.headline)
                Spacer()
                Button("Done",action: close).accessibilityIdentifier("ruler-done")
            }
            let layout = verticalSizeClass == .compact ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading,spacing: 8))
            layout {
                Text(Format.distance(meters: value.distance,unit: settings.units)).font(.title2.monospacedDigit()).accessibilityIdentifier("ruler-distance")
                Text("AZ \(angle(value.azimuth)) \(settings.northRef.letter) · BACK \(angle(value.backAzimuth)) \(settings.northRef.letter)")
                .font(.system(.caption,design: .monospaced)).accessibilityIdentifier("ruler-bearings")
                if verticalSizeClass == .compact { Spacer(); Button("Anchor here",action: reset).accessibilityIdentifier("ruler-reset") }
            }
            if settings.northRef == .magnetic {
                Text("Magnetic: \(reading.source.rawValue) at \(fix == nil ? "crosshair" : "current position")\(reading.modelExpired ? " · model expired" : "")").font(.caption2)
            }
            if settings.northRef == .grid && !(-80...84).contains(target.lat) { Text("Extrapolated grid north outside UTM coverage").font(.caption2) }
            if verticalSizeClass != .compact { HStack {
                Text("Tap to move the anchor; pan to measure.").font(.caption)
                Spacer()
                Button("Anchor here",action: reset).font(.caption).accessibilityIdentifier("ruler-reset")
            } }
        }.padding(12).fieldChrome()
    }
    private func angle(_ degrees: Double?) -> String { degrees.map { Format.angle(degrees: $0,unit: settings.angleUnit) } ?? "—" }
}

struct MapAreaSummary: View {
    let vertices: [GeoPoint]
    var identifierPrefix = "measurement"
    var compact = false
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.fieldNight) private var night
    private var summaryLayout: AnyLayout {
        compact && verticalSizeClass == .compact ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading,spacing: 6))
    }
    var body: some View {
        if let result = MapMeasurement.polygon(vertices) {
            summaryLayout {
                Text(MapMeasurement.areaLabel(result.area)).font(compact ? .headline.monospacedDigit() : .title2.monospacedDigit()).accessibilityIdentifier("\(identifierPrefix)-area")
                Text("Perimeter \(Format.distance(meters: result.perimeter,unit: settings.units)) · \(vertices.count) corners").font(.caption.monospacedDigit()).accessibilityIdentifier("\(identifierPrefix)-perimeter")
                if !compact { Text("UTM zone \(result.zone) plane · local simple polygons. Crossing edges can cancel area; this is not a survey.").font(.caption2) }
                if result.extrapolated { Text("Extrapolated UTM outside 80°S–84°N; local accuracy unverified.").font(.caption2).foregroundStyle(FieldPalette(night: night).warn) }
            }
        } else {
            Text(vertices.count < 3 ? "Tap at least 3 corners to measure." : "Area unavailable outside map coverage.").font(.caption).accessibilityIdentifier("measurement-unavailable")
        }
    }
}
