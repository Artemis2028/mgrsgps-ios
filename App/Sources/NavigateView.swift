import GridFixCore
import SwiftUI

/// Navigate slice — azimuth / back-azimuth / distance / ETA to the selected
/// waypoint. Honours saved units, MGRS digits, north reference, and night mode.
struct NavigateView: View {
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var practice: PracticeSession
    @State private var showingPractice = false
    @EnvironmentObject private var navigation: NavigationSession

    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }

    private var target: Waypoint? {
        guard let id = store.selectedId else { return nil }
        return store.waypoints.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            FieldScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Navigate").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Spacer()
                        Menu {
                            ForEach(store.waypoints) { waypoint in
                                Button(waypoint.name) { store.select(waypoint.id) }
                            }
                        } label: { Image(systemName: "flag").frame(width: 44, height: 44) }
                        .fieldGlassButton().disabled(store.waypoints.isEmpty || practice.locked)
                        .accessibilityLabel("Choose navigation target")
                    }
                    if practice.locked { Text("Practice course navigation is locked. End the course to choose another target.").font(.caption).foregroundStyle(palette.inkDim) }
                    if let wp = target {
                        targetBlock(wp)
                    } else {
                        emptyPrompt
                    }
                    Button("Practice course") { showingPractice = true }.buttonStyle(.bordered).accessibilityIdentifier("open-practice")
                    NavigationControlsView().disabled(practice.blockedByStorage || practice.active?.paused == true)
                    if target != nil || navigation.progress != nil {
                        Button(practice.locked ? "Stop haptic guidance" : "Stop navigation") { navigation.stop(); store.select(nil) }
                            .buttonStyle(.bordered).tint(palette.accent)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .foregroundStyle(palette.ink)
        .environment(\.fieldNight, settings.nightMode)
        .sheet(isPresented: $showingPractice) { PracticeCourseView() }
        .onAppear { location.start() }
    }

    private var emptyPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No target selected")
                .font(Blackout.label(18, weight: .semibold))
            Text("Choose a saved waypoint using the flag above, or tap Navigate on a waypoint or map marker.")
                .font(Blackout.label(14))
                .foregroundStyle(palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func targetBlock(_ wp: Waypoint) -> some View {
        let mgrs = MGRS.string(lat: wp.lat, lon: wp.lon, digits: settings.mgrsDigits) ?? "—"
        let nav: Geodesy.NavInfo? = {
            guard let f = location.usableFix else { return nil }
            return Geodesy.navInfo(fromLat: f.lat, fromLon: f.lon, toLat: wp.lat, toLon: wp.lon)
        }()
        let letter = settings.northRef.letter
        let azimuth = formattedAzimuth(nav, offset: 0)
        let back = formattedAzimuth(nav, offset: 180)
        let distance = nav.map { Format.distance(meters: $0.distanceMeters, unit: settings.units) } ?? "—"
        let eta = etaText(nav: nav)

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(wp.name)
                    .font(Blackout.label(22, weight: .semibold))
                Text(mgrs)
                    .font(Blackout.numerals(16))
                    .foregroundStyle(palette.inkDim)
            }

            if location.usableFix == nil {
                Text("Waiting for a recent, precise position…")
                    .font(Blackout.label(14))
                    .foregroundStyle(palette.inkDim)
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
                cell(title: "Azimuth · \(letter)", value: azimuth)
                cell(title: "Back az · \(letter)", value: back)
                cell(title: "Distance", value: distance)
                cell(title: "Time to go", value: eta)
            }
        }
    }

    /// Azimuth in the saved north reference. Magnetic without a declination
    /// is a dash, not the true bearing labelled as magnetic and not 0.
    private func formattedAzimuth(_ nav: Geodesy.NavInfo?, offset: Double) -> String {
        guard let nav, let f = location.usableFix else { return "—" }
        let decl = DeclinationService(overrideDegrees: settings.declinationOverride)
            .declination(lat: f.lat, lon: f.lon, heightMeters: f.altitudeMeters ?? 0,
                         heading: location.heading, isCurrentPosition: true)
        let conv = UTM.gridConvergence(lat: f.lat, lon: f.lon)
        guard let az = FieldMath.toNorthRef(
            angleTrue: nav.bearingTrue + offset,
            north: settings.northRef,
            declinationEast: decl.degreesEast,
            convergence: conv
        ) else { return "—" }
        return Format.angle(degrees: az, unit: settings.angleUnit)
    }

    private func cell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(Blackout.label(10))
                .tracking(1.2)
                .foregroundStyle(palette.accent)
            Text(value)
                .font(Blackout.numerals(22, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .fieldContentSurface(night: settings.nightMode)
    }

    /// Arrival requires the fix's accuracy circle to fit inside the 50 m ring.
    private func etaText(nav: Geodesy.NavInfo?) -> String {
        guard let nav else { return "—" }
        if let fix = location.usableFix,
           NavigationFixPolicy.insideArrivalRadius(distanceMeters: nav.distanceMeters, accuracyMeters: fix.accuracyMeters) {
            return "HERE"
        }
        guard let speed = location.usableFix?.speedMetersPerSecond, speed > 0.4 else { return "—" }
        let secs = Int(nav.distanceMeters / speed)
        if secs >= 3600 {
            return String(format: "%d:%02d h", secs / 3600, (secs % 3600) / 60)
        }
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
