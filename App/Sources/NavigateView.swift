import GridFixCore
import SwiftUI

/// Navigate slice — azimuth / back-azimuth / distance / ETA to the selected
/// waypoint. Honours saved units, MGRS digits, north reference, and night mode.
struct NavigateView: View {
    var onOrientation: () -> Void = {}
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var practice: PracticeSession
    @State private var showingPractice = false
    @State private var choosingTarget = false
    @State private var pendingTargetID: String?
    @StateObject private var targetMutation = FieldMutation()
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
                    header
                    if let label = targetMutation.label { ProgressView(label) }
                    if let error = targetMutation.error { Text(error).font(.footnote).foregroundStyle(palette.warn).accessibilityIdentifier("navigation-target-error") }
                    if practice.locked { Text(practice.active?.done == true ? "Save the completed course result to unlock navigation." : "Practice course navigation is locked. End the course to choose another target.").font(.caption).foregroundStyle(palette.inkDim) }
                    if let wp = target {
                        targetBlock(wp)
                    } else {
                        emptyPrompt
                    }
                    if target != nil || navigation.progress != nil {
                        Button(practice.locked ? "Stop haptic guidance" : "Stop navigation") { navigation.stop(); if !practice.locked { chooseTarget(nil) } }
                            .buttonStyle(.bordered).tint(palette.accent).accessibilityIdentifier("stop-navigation")
                    }
                    Button("Practice course") { showingPractice = true }.buttonStyle(.bordered).accessibilityIdentifier("open-practice")
                    NavigationControlsView().disabled(practice.working || (practice.locked && practice.blockedByStorage) || practice.active?.paused == true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .foregroundStyle(palette.ink)
        .environment(\.fieldNight, settings.nightMode)
        .sheet(isPresented: $choosingTarget,onDismiss: applyTargetChoice) {
            FieldChoiceSheet(title: "Navigation target",choices: store.waypoints.map { .init(id:$0.id,title:$0.name,waypoint:$0) },
                             selectedID:store.selectedId,night:settings.nightMode) { id in
                pendingTargetID = id; choosingTarget = false
            }
        }
        .sheet(isPresented: $showingPractice) { PracticeCourseView() }
        .onAppear { location.start() }
    }

    @ViewBuilder private var header: some View {
        if dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact {
            VStack(alignment:.leading,spacing:12) {
                heading
                HStack { Spacer(); headerActions }
            }
        } else { HStack { heading; Spacer(); headerActions } }
    }
    private var heading: some View {
        Text("Navigate").font(.system(.largeTitle,design:.rounded,weight:.bold))
            .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("navigation-title")
    }
    @ViewBuilder private var headerActions: some View {
        Button(action:onOrientation) { Image(systemName:"rotate.right").font(.system(size:20)).frame(width:44,height:44) }
            .fieldGlassButton().accessibilityLabel("Screen orientation").accessibilityIdentifier("screen-orientation-menu")
        Button { choosingTarget = true } label: { Image(systemName:"flag").font(.system(size:20)).frame(width:44,height:44) }
            .fieldGlassButton().disabled(store.waypoints.isEmpty || practice.locked || targetMutation.working)
            .accessibilityLabel("Choose navigation target")
    }

    private func applyTargetChoice() {
        guard let id = pendingTargetID else { return }
        pendingTargetID = nil
        // A course or library edit may have changed while the sheet closed.
        guard !practice.locked,!targetMutation.working,store.waypoints.contains(where: { $0.id == id }) else { return }
        chooseTarget(id)
    }

    private func chooseTarget(_ id: String?) {
        targetMutation.run("Saving navigation target…",action: { try await WaypointEditAction.select(id,in: store) })
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
        let mgrs = MGRS.parts(lat: wp.lat, lon: wp.lon, digits: settings.mgrsDigits)?.full ?? "—"
        let nav: Geodesy.NavInfo? = {
            guard let f = location.usableFix else { return nil }
            return Geodesy.navInfo(fromLat: f.lat, fromLon: f.lon, toLat: wp.lat, toLon: wp.lon)
        }()
        let letter = settings.northRef.letter
        let azimuth = formattedAzimuth(nav, offset: 0)
        let back = formattedAzimuth(nav, offset: 180)
        let distance = nav.map { Format.distance(meters: $0.distanceMeters, unit: settings.units) } ?? "—"
        let eta = etaText(nav: nav)
        let heading = navigationHeading()

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment:.top,spacing:10) {
                MilitaryMarker(symbol:wp.symbol,affiliation:wp.affiliation,echelon:wp.echelon,
                               rotation:wp.rotation,metadata:wp.metadata)
                    .frame(width:32,height:32).accessibilityIdentifier("navigation-target-symbol")
                VStack(alignment: .leading, spacing: 4) {
                    Text(wp.name)
                        .font(Blackout.label(22, weight: .semibold)).accessibilityIdentifier("navigation-target-name")
                    Text(mgrs)
                        .accessibilityIdentifier("navigation-target-grid")
                        .font(Blackout.numerals(16))
                        .foregroundStyle(palette.inkDim)
                }
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
            if let heading, let nav {
                let deviation = FieldMath.normalize(nav.bearingTrue - heading.degreesTrue + 180) - 180
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up").font(.system(size: 32,weight: .semibold))
                        .rotationEffect(.degrees(deviation)).frame(width: 56,height: 56)
                    VStack(alignment: .leading,spacing: 4) {
                        Text("\(heading.label) · \(formattedHeading(heading.degreesTrue)) \(letter)")
                        Text(abs(deviation) < 0.5 ? "On bearing" : "\(deviation > 0 ? "Right" : "Left") \(Format.angle(degrees: abs(deviation),unit: settings.angleUnit))")
                    }.font(Blackout.label(14))
                }.foregroundStyle(palette.accent).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("display-relative-navigation")
            } else {
                Text("Screen heading unavailable").font(Blackout.label(12)).foregroundStyle(palette.inkDim)
                    .accessibilityIdentifier("display-heading-unavailable")
            }
        }
    }

    /// Compass steering follows the screen; GPS course follows travel. Pocket
    /// cues use the separate portrait/top-edge driver regardless of this view.
    private func navigationHeading() -> MovementHeading? {
        guard let fix = location.usableFix else { return nil }
        let heading = location.usableHeading
        let decl = DeclinationService(overrideDegrees: settings.declinationOverride)
            .declination(lat: fix.lat,lon: fix.lon,heightMeters: fix.altitudeMeters ?? 0,
                         heading: heading,isCurrentPosition: true)
        let compass = FieldMath.heading(trueHeading: settings.declinationOverride == nil && (heading?.trueHeading ?? -1) >= 0 ? heading?.trueHeading : nil,
                                        magneticHeading: heading?.magneticHeading,
                                        north: .trueNorth,declinationEast: decl.degreesEast,convergence: nil)
        return MovementHeading.navigation(hasCompass: location.hasCompass,compassTrue: compass,fix: fix)
    }
    private func formattedHeading(_ value: Double) -> String {
        guard let fix = location.usableFix else { return "—" }
        let decl = DeclinationService(overrideDegrees: settings.declinationOverride)
            .declination(lat: fix.lat,lon: fix.lon,heightMeters: fix.altitudeMeters ?? 0,
                         heading: location.usableHeading,isCurrentPosition: true)
        guard let referenced = FieldMath.toNorthRef(angleTrue: value,north: settings.northRef,
                                                   declinationEast: decl.degreesEast,
                                                   convergence: UTM.gridConvergence(lat: fix.lat,lon: fix.lon)) else { return "—" }
        return Format.angle(degrees: referenced,unit: settings.angleUnit)
    }

    /// Azimuth in the saved north reference. Magnetic without a declination
    /// is a dash, not the true bearing labelled as magnetic and not 0.
    private func formattedAzimuth(_ nav: Geodesy.NavInfo?, offset: Double) -> String {
        guard let nav, let f = location.usableFix else { return "—" }
        let decl = DeclinationService(overrideDegrees: settings.declinationOverride)
            .declination(lat: f.lat, lon: f.lon, heightMeters: f.altitudeMeters ?? 0,
                         heading: location.usableHeading, isCurrentPosition: true)
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
