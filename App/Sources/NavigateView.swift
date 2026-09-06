import GridFixCore
import SwiftUI

/// First Navigate slice — azimuth / back-azimuth / distance / ETA to the
/// selected waypoint, same field math Android's Glance navigate face uses.
struct NavigateView: View {
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var location: LocationService

    private var target: Waypoint? {
        guard let id = store.selectedId else { return nil }
        return store.waypoints.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Blackout.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                SectionLabel(text: "Navigate")
                if let wp = target {
                    targetBlock(wp)
                } else {
                    emptyPrompt
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(Blackout.ink)
        .onAppear { location.start() }
    }

    private var emptyPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No target selected")
                .font(Blackout.label(18, weight: .semibold))
            Text("Pick a waypoint on the Waypoints tab (swipe Nav), then come back here for azimuth, distance and ETA.")
                .font(Blackout.label(14))
                .foregroundStyle(Blackout.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func targetBlock(_ wp: Waypoint) -> some View {
        let mgrs = MGRS.string(lat: wp.lat, lon: wp.lon, digits: 8) ?? "—"
        let nav: Geodesy.NavInfo? = {
            guard let f = location.fix else { return nil }
            return Geodesy.navInfo(fromLat: f.lat, fromLon: f.lon, toLat: wp.lat, toLon: wp.lon)
        }()
        let azimuth = nav.map { Format.angle(degrees: $0.bearingTrue, unit: .degrees) } ?? "—"
        let back = nav.map {
            Format.angle(degrees: ($0.bearingTrue + 180.0).truncatingRemainder(dividingBy: 360.0), unit: .degrees)
        } ?? "—"
        let distance = nav.map { Format.distance(meters: $0.distanceMeters, unit: .metric) } ?? "—"
        let eta = etaText(nav: nav)

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(wp.name)
                    .font(Blackout.label(22, weight: .semibold))
                Text(mgrs)
                    .font(Blackout.numerals(16))
                    .foregroundStyle(Blackout.inkDim)
            }

            if location.fix == nil {
                Text("Waiting for a fix…")
                    .font(Blackout.label(14))
                    .foregroundStyle(Blackout.inkDim)
            } else {
                Text(distance)
                    .font(Blackout.numerals(48, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 14) {
                cell(title: "Azimuth · T", value: azimuth)
                cell(title: "Back az · T", value: back)
                cell(title: "Distance", value: distance)
                cell(title: "Time to go", value: eta)
            }
        }
    }

    private func cell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(Blackout.label(10))
                .tracking(1.2)
                .foregroundStyle(Blackout.accent)
            Text(value)
                .font(Blackout.numerals(22, weight: .semibold))
                .foregroundStyle(Blackout.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Blackout.hairline, lineWidth: 1)
        )
    }

    /// ETA stub: HERE under 50 m, mm:ss / h:mm when speed is known, else em dash.
    private func etaText(nav: Geodesy.NavInfo?) -> String {
        guard let nav else { return "—" }
        if nav.distanceMeters < 50 { return "HERE" }
        guard let speed = location.fix?.speedMetersPerSecond, speed > 0.4 else { return "—" }
        let secs = Int(nav.distanceMeters / speed)
        if secs >= 3600 {
            return String(format: "%d:%02d h", secs / 3600, (secs % 3600) / 60)
        }
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
