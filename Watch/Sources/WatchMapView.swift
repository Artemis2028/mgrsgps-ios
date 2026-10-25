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
    @State private var following = true
    @State private var hasCentered = false
    @State private var showInfo = false
    @State private var appliedFixture = false
    private var showsNames: Bool { (region?.span.latitudeDelta ?? 0.006) <= 0.0015 }
    private var accent: Color { night ? .red : Color(red: 1, green: 0.698, blue: 0) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let fresh = usable(at: timeline.date)
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                ForEach(model.mapSnapshot?.waypoints ?? []) { point in
                    Annotation(point.name, coordinate: coordinate(point.coordinate)) {
                        WatchMapMarker(point: point, night: night, showName: showsNames || point.id == model.snapshot.target?.id)
                    }.annotationTitles(.hidden)
                }
                ForEach(model.mapSnapshot?.laneOverlays ?? []) { lane in laneContent(lane) }
                ForEach(model.mapSnapshot?.features ?? [], id: \.renderID) { feature in
                    featureContent(feature)
                }
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
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                if camera.positionedByUser { following = false }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-watchUITesting") {
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
        .onAppear { if following { if usable(at: Date()) { recenter() } else { fitOverlay() } } }
        .onChange(of: model.mapSnapshot?.updatedAt) { _, _ in
            if following && !usable(at: Date()) { fitOverlay() }
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
        let points = (model.mapSnapshot?.waypoints.map(\.coordinate) ?? []) + (model.mapSnapshot?.features.flatMap(\.points) ?? []) + (model.mapSnapshot?.laneOverlays.flatMap(\.outline) ?? [])
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

    private func mapInfo(at date: Date) -> some View {
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
                Text("Watch CoreLocation: " + model.status)
                if let fix = model.fix {
                    Text(String(format: "±%.0f m · ", fix.horizontalAccuracy) + WatchFixPolicy.ageLabel(date.timeIntervalSince(fix.timestamp)))
                }
                Text("L/R = lane side limits · BS = backstop. Shading is a cached phone lane, not a watch crossing detector.")
                Text("F = displayed fence · TRK = track · R = route · RG = range ring · A = area. Zoom closer for names.")
                if let snapshot = model.mapSnapshot {
                    ForEach(snapshot.waypoints) { point in Text("Waypoint: " + point.name + " · " + MilitarySymbols.label(point.symbol)) }
                    ForEach(snapshot.laneOverlays) { lane in Text("Lane: " + lane.name + " · L: " + lane.leftLabel + " · R: " + lane.rightLabel + " · BS: " + lane.backstopLabel) }
                    ForEach(snapshot.features, id: \.renderID) { feature in Text(GraphicTypes.label(feature.type) + ": " + feature.name) }
                }
                Text("Pan to browse. +/− zoom around the viewed center; location recenters on a fresh watch fix. Native map gestures are supported.")
                Text("Apple basemap may require a connection; offline cache is not guaranteed. Phone offline packs, MGRS grid, terrain, contours and viewsheds are not transferred.")
                Text("NATO unit PNGs are bundled. Task points use named badges with stored rotation; basic points use SF glyphs, and unknown keys use a question-mark glyph. Labels remain upright. Imported MilGPS shapes, characters and colors are preserved. Typed field paths/areas, sectors and range rings are drawn; tactical decorative teeth/arrows are not reproduced. No boundary alerts run on watch.")
                Text("Overlay cap: 48 KiB, 150 waypoints / 64 field items. Lines ≤160 vertices; large lines simplified. Areas ≤256 vertices, retained in full or omitted. Track files over 2 MiB and coordinates beyond 85° latitude and dateline-crossing areas/sectors are omitted.")
                Button("Position grid") { showInfo = false; showPosition() }
                Button("Close map") { showInfo = false; closeMap() }
                Button("Done") { showInfo = false }
            }.font(.system(size: 12)).foregroundStyle(accent).padding(.horizontal, 6)
        }.background(.black)
    }
}

private struct WatchMapMarker: View {
    var point: WatchMapSnapshot.Point
    var night: Bool
    var showName: Bool
    private var tint: Color {
        if night { return .red }
        switch point.importedColor?.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "cyan": return .cyan
        case "magenta": return .pink
        default: return point.affiliation == "hostile" ? .red : point.affiliation == "friendly" ? .cyan : .orange
        }
    }
    var body: some View {
        glyph.frame(width: 28, height: 28)
            .rotationEffect(.degrees(point.symbol.hasPrefix("task_") ? (point.rotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) : 0))
            .foregroundStyle(tint).background(.black.opacity(0.6))
            .overlay(alignment: .top) {
                if !point.echelon.isEmpty { Text(["tm": "Ø", "sqd": "•", "sec": "••", "plt": "•••", "co": "I", "bn": "II", "rgt": "III", "bde": "X", "div": "XX", "corps": "XXX", "army": "XXXX"][point.echelon] ?? point.echelon.uppercased()).font(.system(size: 7, weight: .bold)).foregroundStyle(tint).offset(y: -9) }
            }
            .overlay(alignment: .bottom) {
                if showName { Text(point.name).font(.system(size: 8, weight: .semibold)).lineLimit(1).fixedSize().foregroundStyle(tint).padding(1).background(.black.opacity(0.7)).offset(y: 12) }
            }
            .accessibilityLabel(point.name + ", " + MilitarySymbols.label(point.symbol))
    }
    @ViewBuilder private var glyph: some View {
            if let image = WatchSymbolImages.image(point.symbol, night: night) {
                Image(uiImage: image).resizable().renderingMode(.original).scaledToFit().frame(width: 28, height: 28)
            } else if let imported = MilGpsSymbols.decode(point.importedCode) {
                ZStack {
                    Image(systemName: shape(imported.shape)).font(.system(size: 22))
                    if let character = imported.character { Text(character).font(.system(size: 10, weight: .bold)).foregroundStyle(.black) }
                }.frame(width: 28, height: 28)
            } else if point.symbol.hasPrefix("task_") {
                Text(MilitarySymbols.label(point.symbol)).font(.system(size: 9, weight: .bold)).frame(maxWidth: 50)
                    .padding(3).overlay(Rectangle().stroke(tint))
            } else {
                Image(systemName: ["flag": "flag.fill", "dot": "circle.fill", "square": "square.fill", "triangle": "triangle.fill", "diamond": "diamond.fill", "cross": "xmark", "target": "scope", "star": "star.fill", "home": "house.fill", "danger": "exclamationmark.triangle", "water": "drop.fill", "camp": "tent", "vehicle": "car", "antenna": "antenna.radiowaves.left.and.right", "medic": "cross.case"][point.symbol] ?? "questionmark.square.dashed")
                    .font(.system(size: 20)).frame(width: 24, height: 24)
            }
    }
    private func shape(_ shape: MilGpsShape) -> String {
        switch shape { case .cross: return "plus"; case .circle: return "circle.fill"; case .triangle: return "triangle.fill"; case .square: return "square.fill"; case .star: return "star.fill" }
    }
}

@MainActor
private enum WatchSymbolImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.countLimit = 128; cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
    static func image(_ key: String, night: Bool) -> UIImage? {
        guard key.hasPrefix("nato_"), key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        let cacheKey = "\(key)|\(night)" as NSString
        if let value = cache.object(forKey: cacheKey) { return value }
        guard let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "MilitarySymbols"), let input = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        let width = input.width, height = input.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard ok else { return nil }
        // Same transform as the phone's MilitaryMarkerRenderer.unitImage: opaque black
        // symbol strokes become transparent, preserving internal marks in red night mode.
        for i in stride(from: 0, to: bytes.count, by: 4) {
            if bytes[i] < 40 && bytes[i + 1] < 40 && bytes[i + 2] < 40 {
                bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0
            } else if night {
                let red = 0.35 * Double(bytes[i]), green = 0.5 * Double(bytes[i + 1]), blue = 0.15 * Double(bytes[i + 2])
                bytes[i] = UInt8(min(255, red + green + blue + 30)); bytes[i + 1] = 0; bytes[i + 2] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let output = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let image = UIImage(cgImage: output)
        cache.setObject(image, forKey: cacheKey, cost: width * height * 4)
        return image
    }
}
