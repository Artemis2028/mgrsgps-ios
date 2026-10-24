import GridFixCore
import SwiftUI

struct TerrainPanel: View {
    @EnvironmentObject private var terrain: TerrainSession
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var field: FieldDataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @State private var centre: GeoPoint
    @State private var position: GeoPoint?
    @State private var observerMode: String
    @State private var targetMode = "centre"
    @State private var observerID = ""
    @State private var targetID = ""
    @State private var observerCoordinate: WaypointCoordinateDraft
    @State private var targetCoordinate: WaypointCoordinateDraft
    @State private var observerHeight = "2"
    @State private var targetHeight = "2"
    @State private var radius = 2000
    private var palette: FieldPalette { .init(night: night) }
    init(centre: GeoPoint,position: GeoPoint?) {
        _centre = State(initialValue: centre); _position = State(initialValue: position)
        _observerMode = State(initialValue: position == nil ? "centre" : "me")
        _observerCoordinate = State(initialValue: .init(lat: centre.lat,lon: centre.lon))
        _targetCoordinate = State(initialValue: .init(lat: centre.lat,lon: centre.lon))
    }
    private func point(_ mode: String,_ id: String,_ coordinate: WaypointCoordinateDraft) -> GeoPoint? {
        if mode == "me" { return position }
        if mode == "centre" { return centre }
        if mode == "coordinate" { return coordinate.position.map { .init(lat: $0.lat,lon: $0.lon) } }
        return waypoints.waypoints.first { $0.id == id }.map { .init(lat: $0.lat,lon: $0.lon) }
    }
    private var observer: GeoPoint? { point(observerMode,observerID,observerCoordinate) }
    private var target: GeoPoint? { point(targetMode,targetID,targetCoordinate) }
    private func height(_ text: String) -> Float? { guard let value = Float(text), value.isFinite,(0...1000).contains(value) else { return nil }; return value }
    var body: some View {
        NavigationStack {
            Form {
                Section("Observer · snapshot when opened") {
                    TerrainEndpoint(mode: $observerMode,id: $observerID,coordinate: $observerCoordinate,waypoints: waypoints.waypoints,position: position,centre: centre,prefix: "observer")
                    TextField("Height above ground (m)",text: $observerHeight).keyboardType(.decimalPad).accessibilityIdentifier("terrain-observer-height")
                    Text("Height: \(observerHeight) m above ground").font(.caption).foregroundStyle(palette.inkDim)
                }.disabled(terrain.busy)
                Section("Target") {
                    TerrainEndpoint(mode: $targetMode,id: $targetID,coordinate: $targetCoordinate,waypoints: waypoints.waypoints,position: position,centre: centre,prefix: "target")
                    TextField("Height above ground (m)",text: $targetHeight).keyboardType(.decimalPad).accessibilityIdentifier("terrain-target-height")
                    Text("Height: \(targetHeight) m above ground").font(.caption).foregroundStyle(palette.inkDim)
                }.disabled(terrain.busy)
                Section("Terrain analysis") {
                    Button("Check line of sight") {
                        hideKeyboard()
                        if let observer,let target,let a = height(observerHeight),let b = height(targetHeight) { terrain.check(observer: observer,target: target,observerHeight: a,targetHeight: b) }
                    }.disabled(terrain.busy || observer == nil || target == nil || height(observerHeight) == nil || height(targetHeight) == nil).accessibilityIdentifier("terrain-check")
                    Picker("Viewshed radius",selection: $radius) { Text("1 km").tag(1000); Text("2 km").tag(2000); Text("4 km").tag(4000) }.pickerStyle(.segmented).disabled(terrain.busy)
                    Button("Shade map from observer") {
                        hideKeyboard()
                        if let observer,let height = height(observerHeight) { terrain.shade(observer: observer,height: Double(height),radius: Double(radius)) { dismiss() } }
                    }.disabled(terrain.busy || observer == nil || height(observerHeight) == nil).accessibilityIdentifier("terrain-shade")
                    if terrain.viewshed != nil { Button("Clear map shade") { terrain.clearViewshed() }.disabled(terrain.busy).accessibilityIdentifier("terrain-clear-shade") }
                    Text("Heights must be 0–1,000 metres above ground. Uses cached or downloaded Mapzen/AWS elevation, about 10–30 m source detail. Terrain only: trees, buildings and smaller obstacles are not included. Missing data stays unknown. Standard 4/3 Earth-radius refraction is an estimate, not a visibility guarantee.").font(.footnote).foregroundStyle(palette.inkDim)
                }
                if terrain.busy {
                    Section {
                        ProgressView(value: terrain.progress).accessibilityIdentifier("terrain-progress")
                        Text(terrain.progress > 0 ? "Computing viewshed · \(Int(terrain.progress*100))%" : "Sampling elevation…")
                        Button("Cancel analysis") { terrain.cancel() }.accessibilityIdentifier("terrain-cancel")
                    }
                }
                if let error = terrain.error { Section { Text(error).foregroundStyle(palette.warn).accessibilityIdentifier("terrain-error") } }
                if let sight = terrain.sight { sightResult(sight) }
                Section("Saved-route elevation profile") {
                    let routes = field.document.graphics.filter { $0.type == "route" }
                    if routes.isEmpty { Text("Save or import a route to view its elevation profile.").font(.footnote) }
                    ForEach(routes) { route in Button(route.name) { hideKeyboard(); terrain.routeProfile(route) }.disabled(terrain.busy).accessibilityIdentifier("terrain-profile-\(route.name)") }
                }
                if let profile = terrain.profile {
                    Section(terrain.profileName) { if profile.missing < profile.elevations.count { TerrainProfileChart(profile: profile) }; profileStats(profile) }
                }
            }.scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .foregroundStyle(palette.ink).tint(palette.accent)
                .navigationTitle("Terrain visibility").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hide keyboard",action: hideKeyboard) }
                }
                .onAppear { terrain.clearSight() }
                .onDisappear { terrain.cancel() }
                .onChange(of: observerMode) { _ in terrain.clearSight() }.onChange(of: targetMode) { _ in terrain.clearSight() }
                .onChange(of: observerID) { _ in terrain.clearSight() }.onChange(of: targetID) { _ in terrain.clearSight() }
                .onChange(of: observerCoordinate.grid) { _ in terrain.clearSight() }.onChange(of: targetCoordinate.grid) { _ in terrain.clearSight() }
                .onChange(of: observerCoordinate.latitude) { _ in terrain.clearSight() }.onChange(of: targetCoordinate.latitude) { _ in terrain.clearSight() }
                .onChange(of: observerCoordinate.longitude) { _ in terrain.clearSight() }.onChange(of: targetCoordinate.longitude) { _ in terrain.clearSight() }
                .onChange(of: observerHeight) { _ in terrain.clearSight() }.onChange(of: targetHeight) { _ in terrain.clearSight() }
        }.fieldSheetAppearance()
    }
    @ViewBuilder private func sightResult(_ sight: TerrainAnalysis.Sight) -> some View {
        Section("Line of sight result") {
            let result = sight.analysis
            Text(result.status.rawValue.uppercased()).font(.title2.bold()).accessibilityIdentifier("terrain-sight-status")
            if result.status == .unknown { Text("Missing terrain prevents confirming visibility along this path.") }
            if result.status == .visible { Text("Clear through sampled terrain at these heights. Unmodelled obstacles may still block the view.") }
            if let block = sight.blockPosition {
                Text("First known obstruction: \(sight.profile.distances[result.blockIndex],specifier: "%.0f") m along path")
                Text(MGRS.parts(lat: block.lat,lon: block.lon,digits: 10)?.full ?? "Outside MGRS coverage").font(.system(.caption,design: .monospaced))
            }
            if result.minClearance.isFinite { Text("Tightest clearance: \(result.minClearance,specifier: "%.1f") m at \(result.minClearanceDistance,specifier: "%.0f") m") }
            if result.clearObserverHeight.isFinite { Text("Observer height to clear sampled terrain: \(result.clearObserverHeight,specifier: "%.1f") m AGL") }
            else { Text("Incomplete terrain: no minimum-clearance or required-height promise.").font(.footnote) }
            TerrainProfileChart(profile: sight.profile,sight: result)
            profileStats(sight.profile)
        }
    }
    @ViewBuilder private func profileStats(_ profile: TerrainAnalysis.Profile) -> some View {
        let totals = profile.gainLoss()
        if profile.missing == profile.elevations.count {
            Text("Elevation unavailable. Download elevation for this route.").foregroundStyle(palette.warn)
            Text("\(profile.total,specifier: "%.0f") m path")
        } else {
            Text("\(profile.total,specifier: "%.0f") m · climb \(totals.gain,specifier: "%.0f") m · descent \(totals.loss,specifier: "%.0f") m")
        }
        if profile.missing > 0 { Text("Climb and descent reflect known samples only; missing terrain can change these totals.").font(.footnote) }
        Text("\(profile.missing) missing samples of \(profile.elevations.count)").font(.caption).foregroundStyle(palette.inkDim).accessibilityIdentifier("terrain-missing-count")
    }
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to: nil,from: nil,for: nil) }
}

private struct TerrainEndpoint: View {
    @Binding var mode: String
    @Binding var id: String
    @Binding var coordinate: WaypointCoordinateDraft
    let waypoints: [Waypoint]
    let position: GeoPoint?
    let centre: GeoPoint
    let prefix: String
    var body: some View {
        Picker("Position source",selection: $mode) {
            if position != nil { Text("My position").tag("me") }
            Text("Map centre").tag("centre"); Text("Waypoint").tag("waypoint"); Text("Coordinate").tag("coordinate")
        }.accessibilityIdentifier("terrain-\(prefix)-source")
        if mode == "waypoint" {
            Picker("Waypoint",selection: $id) { Text("Choose waypoint").tag(""); ForEach(waypoints) { Text($0.name).tag($0.id).accessibilityIdentifier("terrain-\(prefix)-choice-\($0.name)") } }.accessibilityIdentifier("terrain-\(prefix)-waypoint")
        } else if mode == "coordinate" {
            Picker("Format",selection: Binding(get: { coordinate.format },set: { coordinate.changeFormat(to: $0) })) {
                Text("MGRS").tag(WaypointCoordinateDraft.Format.mgrs); Text("Lat / Lon").tag(WaypointCoordinateDraft.Format.decimal)
            }.pickerStyle(.segmented)
            if coordinate.format == .mgrs { TextField("MGRS",text: $coordinate.grid).textInputAutocapitalization(.characters).accessibilityIdentifier("terrain-\(prefix)-grid") }
            else { TextField("Latitude",text: $coordinate.latitude).keyboardType(.numbersAndPunctuation); TextField("Longitude",text: $coordinate.longitude).keyboardType(.numbersAndPunctuation) }
            if let error = coordinate.validationMessage { Text(error).font(.caption) }
        } else {
            let point = mode == "me" ? position : centre
            if let point { Text(MGRS.parts(lat: point.lat,lon: point.lon,digits: 10)?.full ?? "Outside MGRS coverage").font(.system(.caption,design: .monospaced)) }
        }
    }
}

struct TerrainProfileChart: View {
    let profile: TerrainAnalysis.Profile
    var sight: TerrainSight.Result?
    @Environment(\.fieldNight) private var night
    var body: some View {
        let heights = sight?.effectiveTerrain ?? profile.elevations
        let finite = (heights + (sight?.sightLine ?? [])).filter(\.isFinite)
        let low = Double(finite.min() ?? 0), high = max(low+5,Double(finite.max() ?? 5))
        VStack(alignment: .leading,spacing: 8) {
            Text(sight == nil ? "Ground elevation · metres MSL" : "Terrain and sight line · curvature-corrected metres").font(.caption)
            Canvas { context,size in
                guard profile.total > 0, heights.count >= 2 else { return }
                func point(_ i: Int,_ value: Float) -> CGPoint { .init(x: Double(profile.distances[i]/profile.total)*size.width,y: size.height-(Double(value)-low)/(high-low)*size.height) }
                var start = 0
                while start < heights.count {
                    while start < heights.count && !heights[start].isFinite { start += 1 }
                    var end = start; while end < heights.count && heights[end].isFinite { end += 1 }
                    if end-start >= 2 {
                        var line = Path(); line.move(to: point(start,heights[start])); for i in (start+1)..<end { line.addLine(to: point(i,heights[i])) }
                        var fill = line; fill.addLine(to: CGPoint(x: point(end-1,heights[end-1]).x,y: size.height)); fill.addLine(to: CGPoint(x: point(start,heights[start]).x,y: size.height)); fill.closeSubpath()
                        context.fill(fill,with: .color(FieldPalette(night: night).accent.opacity(0.22)))
                        context.stroke(line,with: .color(FieldPalette(night: night).accent),lineWidth: 2)
                    }; start = end+1
                }
                if let sight {
                    var line = Path(); line.move(to: point(0,sight.sightLine[0])); for i in 1..<sight.sightLine.count { line.addLine(to: point(i,sight.sightLine[i])) }
                    context.stroke(line,with: .color(night ? .red : .green),style: StrokeStyle(lineWidth: 2,dash: [5,3]))
                    if sight.blockIndex >= 0 { let p = point(sight.blockIndex,heights[sight.blockIndex]); context.fill(Path(ellipseIn: CGRect(x: p.x-4,y: p.y-4,width: 8,height: 8)),with: .color(.red)) }
                }
                for i in profile.legEnds.dropLast() { let x = point(i,heights[i]).x; var tick = Path(); tick.move(to: .init(x: x,y: 0)); tick.addLine(to: .init(x: x,y: size.height)); context.stroke(tick,with: .color(FieldPalette(night: night).inkDim.opacity(0.4)),style: StrokeStyle(lineWidth: 1,dash: [2,3])) }
            }.frame(height: 190).clipped().accessibilityLabel("Elevation profile. Missing samples appear as gaps.").accessibilityIdentifier("terrain-profile-chart")
            HStack { Text("\(low,specifier: "%.0f")–\(high,specifier: "%.0f") m"); Spacer(); Text("\(profile.total,specifier: "%.0f") m path") }.font(.caption.monospacedDigit())
        }
    }
}

struct RouteTerrainProfileView: View {
    let route: Backup.Graphic
    @EnvironmentObject private var terrain: TerrainSession
    @Environment(\.fieldNight) private var night
    var body: some View {
        List {
            Text("Terrain profile of the route snapshot. Elevation excludes vegetation and structures.").font(.footnote)
            if terrain.busy { ProgressView("Sampling elevation…"); Button("Cancel analysis") { terrain.cancel() } }
            if let error = terrain.error { Text(error).foregroundStyle(FieldPalette(night: night).warn) }
            if let profile = terrain.profile {
                if profile.missing < profile.elevations.count {
                    TerrainProfileChart(profile: profile)
                    let totals = profile.gainLoss()
                    Text("\(profile.total,specifier: "%.0f") m · climb \(totals.gain,specifier: "%.0f") m · descent \(totals.loss,specifier: "%.0f") m").accessibilityIdentifier("terrain-route-profile-summary")
                } else { Text("Elevation unavailable. Download elevation for this route.").foregroundStyle(FieldPalette(night: night).warn).accessibilityIdentifier("terrain-profile-unavailable") }
                Text("\(profile.missing) missing samples of \(profile.elevations.count)")
                if profile.missing > 0 { Text("Totals reflect known samples only. Download elevation for a more complete profile.").font(.footnote) }
            }
            Button("Refresh profile") { terrain.routeProfile(route) }.disabled(terrain.busy)
        }.scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent)
            .navigationTitle("Elevation profile").navigationBarTitleDisplayMode(.inline)
            .onAppear { terrain.routeProfile(route) }.onDisappear { terrain.cancel() }
            .fieldSheetAppearance()
    }
}
