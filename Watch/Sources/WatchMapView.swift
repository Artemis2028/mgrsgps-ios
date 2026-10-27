import SwiftUI
import MapKit
import GridFixCore
import UIKit

struct WatchMapView: View {
    @ObservedObject var model: WatchModel
    var night: Bool
    var showPosition: () -> Void = {}
    var closeMap: () -> Void = {}
    @State private var camera: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var visibleMapRect: MKMapRect?
    @State private var following = true
    @State private var hasCentered = false
    @State private var showInfo = false
    @State private var appliedFixture = false
    private var showsNames: Bool { (region?.span.latitudeDelta ?? 0.006) <= 0.0015 }
    private var accent: Color { night ? .red : Color(red: 1, green: 0.698, blue: 0) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let fresh = usable(at: timeline.date)
            MapReader { proxy in
                Map(position: $camera, interactionModes: [.pan, .zoom]) {
                    ForEach(model.mapSnapshot?.waypoints ?? []) { point in
                        Annotation(point.name, coordinate: coordinate(point.coordinate)) {
                            WatchMapMarker(point: point, night: night, showName: showsNames || point.id == model.snapshot.target?.id)
                        }.annotationTitles(.hidden)
                    }
                    ForEach(model.mapSnapshot?.laneOverlays ?? []) { lane in laneContent(lane) }
                    ForEach(model.mapSnapshot?.features ?? [], id: \.renderID) { feature in
                        if feature.kind != "graphic" { featureContent(feature) }
                    }
                    ForEach(model.remoteItems(at:timeline.date)) { item in remoteContent(item) }
                    if fresh, let fix = model.fix {
                        Annotation("Watch location", coordinate: fix.coordinate, anchor: .center) {
                            Circle().fill(night ? .red : .cyan).frame(width: 9, height: 9)
                                .overlay(Circle().stroke(.black, lineWidth: 2))
                                .accessibilityLabel("Fresh watch location")
                        }.annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
                .colorMultiply(night ? .red : .white)
                .overlay {
                    WatchTacticalGraphicLayer(features:model.mapSnapshot?.features ?? [],proxy:proxy,mapRect:visibleMapRect,night:night,showsNames:showsNames,ownLocation:fresh ? model.fix?.coordinate : nil)
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    region = context.region
                    visibleMapRect = context.rect
                    if camera.positionedByUser { following = false }
                    #if DEBUG
                    let args = ProcessInfo.processInfo.arguments
                    if !appliedFixture,args.contains("-watchUITesting"),args.contains("-watchMapOverlayPan") {
                        appliedFixture = true; following = false
                        camera = .region(.init(center:.init(latitude:context.region.center.latitude+0.0007,
                                                            longitude:TerrainGeometry.wrap(context.region.center.longitude+0.0007)),
                                               span:.init(latitudeDelta:context.region.span.latitudeDelta*0.75,
                                                          longitudeDelta:context.region.span.longitudeDelta*0.75)))
                    }
                    if args.contains("-watchUITesting") {
                        NSLog("GridFix map center %.6f %.6f span %.6f follow %@", context.region.center.latitude, context.region.center.longitude, context.region.span.latitudeDelta, following ? "yes" : "no")
                    }
                    #endif
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        Button { showInfo = true } label: {
                            Image(systemName: "info.circle").frame(width: 28, height: 24)
                                .background(.black.opacity(0.65), in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("Map sync, limits and basemap details")
                        Text(fresh ? (following ? "WATCH FIX" : "BROWSING") : model.usable(at: timeline.date) ? "OUTSIDE MAP RANGE" : "NO FRESH FIX")
                            .font(.system(size: 8, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                            .padding(3).background(.black.opacity(0.65), in: Capsule())
                    }.padding(.leading, 2).foregroundStyle(accent)
                }
                .overlay(alignment: .trailing) {
                    VStack(spacing: 0) {
                        mapButton("plus.magnifyingglass", label: "Zoom in") { zoom(0.5) }
                        mapButton("minus.magnifyingglass", label: "Zoom out") { zoom(2) }
                        mapButton("location.fill", label: "Recenter on fresh watch location") { recenter() }.disabled(!fresh)
                    }.foregroundStyle(accent).padding(.trailing, 2)
                }
            }
        }
        .onAppear { if following { if usable(at: Date()) { recenter() } else { fitOverlay() } } }
        .onChange(of: model.mapSnapshot?.updatedAt) { _, _ in
            if following && !usable(at: Date()) { fitOverlay() }
        }
        .onChange(of:model.takScene.snapshot?.revision) { _,_ in
            if following && !usable(at:Date()) { fitOverlay() }
        }
        .onChange(of: model.fix?.timestamp) { _, _ in
            if following { recenter() }
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if !appliedFixture, usable(at: Date()), args.contains("-watchUITesting") {
                appliedFixture = true
                if args.contains("-watchMapPan"), let fix = model.fix {
                    following = false
                    camera = .region(MKCoordinateRegion(center: .init(latitude: fix.coordinate.latitude + 0.003, longitude: fix.coordinate.longitude + 0.003), span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006)))
                }
                if args.contains("-watchMapZoom") { zoom(0.5) }
                if args.contains("-watchMapRecenter") { recenter() }
            }
            #endif
        }
        .sheet(isPresented: $showInfo) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in mapInfo(at: timeline.date) }
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-watchUITesting"), args.contains("-watchMapInfo") { showInfo = true }
            #endif
        }
    }

    private func usable(at date: Date) -> Bool {
        model.usable(at: date) && model.fix.map { abs($0.coordinate.latitude) <= 85 } == true
    }
    private func coordinate(_ point: GeoPoint) -> CLLocationCoordinate2D { .init(latitude: point.lat, longitude: point.lon) }
    private func mapButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 32, height: 32)
                .background(.black.opacity(0.65), in: Circle()).frame(width: 44, height: 44).contentShape(Rectangle())
        }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
    private func recenter() {
        guard usable(at: Date()), let fix = model.fix else { return }
        following = true
        let span = hasCentered ? (camera.region?.span ?? region?.span ?? MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)) : MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        hasCentered = true
        camera = .region(MKCoordinateRegion(center: fix.coordinate, span: span))
    }
    private func fitOverlay() {
        var points: [GeoPoint] = model.remoteItems(at: Date()).flatMap(\.points)
        if let snapshot = model.mapSnapshot {
            points.append(contentsOf: snapshot.waypoints.map(\.coordinate))
            for feature in snapshot.features { points.append(contentsOf: feature.points) }
            for lane in snapshot.laneOverlays { points.append(contentsOf: lane.outline) }
        }
        guard let bounds = FieldMapGeometry.bounds(points) else { return }
        camera = .region(MKCoordinateRegion(center: .init(latitude: (bounds.south + bounds.north) / 2,
                                                         longitude: TerrainGeometry.wrap((bounds.west + bounds.east) / 2)),
                                            span: .init(latitudeDelta: min(150, max(0.003, (bounds.north - bounds.south) * 1.3)),
                                                        longitudeDelta: min(300, max(0.003, (bounds.east - bounds.west) * 1.3)))))
    }
    private func zoom(_ factor: Double) {
        guard let region = camera.positionedByUser ? region : (camera.region ?? region) else { return }
        following = false
        camera = .region(MKCoordinateRegion(center: region.center, span: .init(latitudeDelta: min(150, max(0.0002, region.span.latitudeDelta * factor)), longitudeDelta: min(300, max(0.0002, region.span.longitudeDelta * factor)))))
    }
    private func color(_ affiliation: String, track: Bool = false) -> Color {
        if night { return .red }
        switch affiliation {
        case "friendly": return .cyan
        case "hostile": return .red
        case "neutral": return .green
        case "unknown": return .yellow
        default: return track ? .green : .orange
        }
    }

    @MapContentBuilder private func remoteContent(_ item: WatchTAKSnapshot.Item) -> some MapContent {
        let tint = color(item.affiliation)
        if let first = item.points.first {
            if item.points.count == 1 {
                Annotation("TAK · " + item.name,coordinate:coordinate(first)) {
                    VStack(spacing:1) {
                        Image(systemName:item.contact ? "circle.fill" : "diamond.fill").font(.system(size:12))
                            .overlay(Image(systemName:item.contact ? "circle" : "diamond").font(.system(size:12)).foregroundStyle(.black))
                        Text("TAK" + (showsNames ? " · " + item.name : "")).font(.system(size:8,weight:.bold,design:.monospaced)).lineLimit(2).frame(maxWidth:80)
                    }.foregroundStyle(tint).padding(2).background(.black.opacity(0.75))
                        .accessibilityLabel("TAK " + (item.contact ? "contact: " : "marker: ") + item.name)
                }.annotationTitles(.hidden)
            } else {
                if item.closed { MapPolygon(coordinates:item.points.map(coordinate)).foregroundStyle(tint.opacity(0.15)).stroke(tint,lineWidth:2) }
                else { MapPolyline(coordinates:item.points.map(coordinate)).stroke(tint,lineWidth:2) }
                Annotation("TAK · " + item.name,coordinate:coordinate(first)) {
                    Text("TAK" + (showsNames ? " · " + item.name : "")).font(.system(size:8,weight:.bold,design:.monospaced)).lineLimit(2).frame(maxWidth:80).foregroundStyle(tint).padding(2).background(.black.opacity(0.75))
                }.annotationTitles(.hidden)
            }
        }
    }

    @MapContentBuilder private func laneContent(_ lane: WatchLaneOverlay) -> some MapContent {
        MapPolygon(coordinates: lane.outline.map(coordinate)).foregroundStyle((night ? Color.red : Color.green).opacity(0.12))
        ForEach([0,1,2],id: \.self) { role in
            let points = role == 0 ? lane.left : role == 1 ? lane.right : lane.backstop
            let tint: Color = night || role == 2 ? .red : .orange
            MapPolyline(coordinates: points.map(coordinate)).stroke(tint,style: StrokeStyle(lineWidth: 2,dash: role == 2 ? [] : [4,3]))
            Annotation(lane.name,coordinate: coordinate(WatchLaneOverlay.labelPoint(points)),anchor: role == 0 ? .trailing : role == 1 ? .leading : .bottom) {
                Text((role == 0 ? "L" : role == 1 ? "R" : "BS") + (showsNames ? " · " + (role == 0 ? lane.leftLabel : role == 1 ? lane.rightLabel : lane.backstopLabel) : ""))
                    .font(.system(size: 8,weight: .bold,design: .monospaced)).lineLimit(2).frame(maxWidth: 65)
                    .foregroundStyle(tint).padding(2).background(.black.opacity(0.75))
            }.annotationTitles(.hidden)
        }
    }

    @MapContentBuilder private func featureContent(_ feature: WatchMapSnapshot.Feature) -> some MapContent {
        let points = feature.points
        let tint = color(feature.affiliation, track: feature.kind == "track")
        if let first = points.first {
            if feature.type == "ring", points.count >= 2 {
                MapCircle(center: coordinate(first), radius: Geodesy.greatCircleMeters(first.lat, first.lon, points[1].lat, points[1].lon))
                    .foregroundStyle(tint.opacity(0.05)).stroke(tint, lineWidth: 1.5)
            } else if feature.type == "sector", let sector = WatchMapGeometry.sectorOutline(points) {
                MapPolygon(coordinates: sector.map(coordinate)).foregroundStyle(tint.opacity(0.15)).stroke(tint, lineWidth: 1.5)
            } else if feature.isArea {
                MapPolygon(coordinates: points.map(coordinate)).foregroundStyle(tint.opacity(0.15)).stroke(tint, lineWidth: 1.5)
            } else {
                ForEach(Array(FieldMapGeometry.lineSegments(points).enumerated()), id: \.offset) { _, segment in
                    if segment.count >= 2 {
                        MapPolyline(coordinates: segment.map(coordinate)).stroke(tint, style: StrokeStyle(lineWidth: feature.kind == "track" ? 2.5 : 1.5, dash: feature.kind == "boundary" ? [4, 3] : []))
                    }
                }
            }
            Annotation(feature.name, coordinate: coordinate(first)) {
                VStack(spacing: 0) {
                    Text(feature.kind == "track" ? "TRK" : feature.kind == "boundary" ? "F" : feature.type == "ring" ? "RG" : feature.type == "route" ? "R" : feature.isArea ? "A" : String(feature.type.prefix(3)).uppercased())
                        .font(.system(size: 7, weight: .bold))
                    if showsNames { Text(feature.name).font(.system(size: 8)).lineLimit(1).frame(maxWidth: 60) }
                }.foregroundStyle(tint).padding(2).background(.black.opacity(0.75))
            }.annotationTitles(.hidden)
        }
    }

    private func laneInfo(_ lane: WatchLaneOverlay) -> String {
        let left = "L: \(lane.leftLabel)"
        let right = "R: \(lane.rightLabel)"
        let backstop = "BS: \(lane.backstopLabel)"
        return ["Lane: \(lane.name)",left,right,backstop].joined(separator: " · ")
    }

    private func mapInfo(at date: Date) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("PHONE MAP OVERLAY").font(.headline)
                Text(model.mapSyncStatus)
                Text(model.reachable ? "Phone app reachable" : "Phone app not reachable")
                if let snapshot = model.mapSnapshot {
                    Text("Cached sync · " + WatchFixPolicy.ageLabel(date.timeIntervalSince(snapshot.updatedAt)))
                    Text("\(snapshot.waypoints.count) waypoints · \(snapshot.features.count) items · \(snapshot.laneOverlays.count) lanes")
                    Text("\(snapshot.omittedItems) omitted · \(snapshot.simplifiedItems) simplified")
                }
                Text("TAK REMOTE LAYER").font(.headline).id("takDetails")
                if let remote = model.takScene.snapshot {
                    Text(!remote.enabled ? "Hidden on phone" : remote.connected ? "Phone reported connected · cached scene" : "Phone reported disconnected · cached scene")
                    Text("Sync · " + WatchFixPolicy.ageLabel(date.timeIntervalSince1970-Double(remote.at)/1000))
                    Text("\(model.remoteItems(at:date).count) unexpired · \(remote.omitted) omitted")
                    ForEach(model.remoteItems(at:date)) { item in
                        Text("TAK " + (item.contact ? "contact" : item.points.count == 1 ? "marker" : item.closed ? "area" : "line") + ": " + item.name)
                    }
                } else { Text("No phone TAK scene yet") }
                Text("Remote items expire at their TAK stale time. Phone visibility and deletes replace this separate read-only layer. No watch server connection, sharing or editing.")
                Text("Watch CoreLocation: " + model.status)
                if let fix = model.fix {
                    Text(String(format: "±%.0f m · ", fix.horizontalAccuracy) + WatchFixPolicy.ageLabel(date.timeIntervalSince(fix.timestamp)))
                }
                Text("L/R = lane side limits · BS = backstop. Shading is a cached phone lane, not a watch crossing detector.")
                Text("F = displayed fence · TRK = track. Tactical symbols and route leg numbers match the phone. Simplified routes omit leg numbers because one displayed segment may span several original legs. Zoom closer for names.")
                if let snapshot = model.mapSnapshot {
                    ForEach(snapshot.waypoints) { point in Text("Waypoint: " + point.name + " · " + MilitarySymbols.label(point.symbol)) }
                    ForEach(snapshot.laneOverlays) { lane in
                        Text(laneInfo(lane))
                    }
                    ForEach(snapshot.features, id: \.renderID) { feature in Text(GraphicTypes.label(feature.type) + ": " + feature.name) }
                }
                Text("Pan to browse. +/− zoom around the viewed center; location recenters on a fresh watch fix. Native map gestures are supported.")
                Text("Apple basemap may require a connection; offline cache is not guaranteed. Phone offline packs, MGRS grid, terrain, contours and viewsheds are not transferred.")
                Text("NATO unit PNGs and mission-task artwork match the phone. Directional tasks rotate; S/G/C letter badges and labels stay upright. Basic affiliation frames, echelon marks and imported MilGPS shapes, characters and colors use the shared artwork. Unknown keys use a question-mark glyph. All 30 phone tactical control measures share its drawing code: attack arrows, wire/obstacle marks, screen/guard/cover badges, numbered route legs, areas, sectors and range rings. The Legal control stays clear of artwork. No boundary alerts run on watch.")
                Text("Remote cap: 8 KiB / 64 items / 384 vertices, at most 128 per drawing. Whole drawings are omitted, never simplified. Local overlay cap: 48 KiB, 150 waypoints / 64 field items. Lines ≤160 vertices; large lines simplified. Areas ≤256 vertices, retained in full or omitted. Track files over 2 MiB and coordinates beyond 85° latitude and dateline-crossing areas/sectors are omitted.")
                Button("Position grid") { showInfo = false; showPosition() }
                Button("Close map") { showInfo = false; closeMap() }
                Button("Done") { showInfo = false }
            }.font(.system(size: 12)).foregroundStyle(accent).padding(.horizontal, 6)
        }.background(.black)
        #if DEBUG
        .task {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-watchUITesting"),args.contains("-watchTAKInfo") {
                try? await Task.sleep(nanoseconds:200_000_000)
                proxy.scrollTo("takDetails",anchor:.top)
            }
        }
        #endif
        }
    }
}

private struct WatchMapMarker: View {
    var point: WatchMapSnapshot.Point
    var night: Bool
    var showName: Bool
    private var tint: Color { Color(uiColor: MilitaryMarkerRenderer.color(point.affiliation,night: night,imported: point.importedColor)) }
    var body: some View {
        Image(uiImage: MilitaryMarkerRenderer.image(symbol: point.symbol,affiliation: point.affiliation,
                                                    echelon: point.echelon,rotation: point.rotation,night: night,
                                                    metadata: .init(color: point.importedColor,milgpsSymbolCode: point.importedCode)))
            .resizable().scaledToFit().frame(width: 28,height: 28)
            .background(.black.opacity(0.6))
            .overlay(alignment: .bottom) {
                if showName { Text(point.name).font(.system(size: 8, weight: .semibold)).lineLimit(1).fixedSize().foregroundStyle(tint).padding(1).background(.black.opacity(0.7)).offset(y: 12) }
            }
            .accessibilityLabel(point.name + ", " + MilitarySymbols.label(point.symbol))
    }
}
