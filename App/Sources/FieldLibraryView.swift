import GridFixCore
import SwiftUI

struct FieldLibraryView: View {
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    var onNavigate: () -> Void = {}
    @State private var routeRequest: RouteEditorRequest?
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }

    var body: some View {
        NavigationStack {
            List {
                if let failure = fieldData.loadError { Text(failure).foregroundStyle(palette.warn) }
                Section("Routes") {
                    ForEach(fieldData.document.graphics.filter { $0.type == "route" }) { route in
                        NavigationLink {
                            RouteDetailView(routeID: route.id, onNavigate: onNavigate)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.name).font(.headline)
                                Text("\(route.points.count) vertices · \(route.folder)").font(.caption).foregroundStyle(palette.inkDim)
                            }
                        }.accessibilityIdentifier("route-\(route.name)")
                    }
                    Button { routeRequest = RouteEditorRequest() } label: { Label("New route", systemImage: "plus") }
                        .accessibilityIdentifier("create-route")
                }
                Section("Saved tracks") {
                    ForEach(fieldData.document.tracks.sorted { $0.startedAt > $1.startedAt }) { track in
                        NavigationLink { TrackDetailView(trackID: track.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.name).font(.headline)
                                Text("\(track.pointCount) points · \(Format.distance(meters: track.distanceM, unit: settings.units))")
                                    .font(.caption).foregroundStyle(palette.inkDim)
                            }
                        }.accessibilityIdentifier("track-\(track.name)")
                    }
                    if fieldData.document.tracks.isEmpty { Text("Import GPX tracks or restore a backup to see saved tracks here.").font(.subheadline).foregroundStyle(palette.inkDim) }
                }
                if !fieldData.document.courseHistory.isEmpty {
                    Section("Practice history") {
                        ForEach(Array(fieldData.document.courseHistory.enumerated()), id: \.offset) { _, result in
                            VStack(alignment: .leading) {
                                Text(result.name)
                                Text("\(result.points) points · \(result.total / 1000) seconds").font(.caption).foregroundStyle(palette.inkDim)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .navigationTitle("Routes & tracks")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $routeRequest) { request in
                RouteEditor(route: request.route) { route in
                    try fieldData.saveGraphic(route); waypoints.addFolder(route.folder)
                }
            }
        }.foregroundStyle(palette.ink).tint(palette.accent)
    }
}

struct RouteEditorRequest: Identifiable {
    let id = UUID()
    var route: Backup.Graphic?
}

struct RouteEditor: View {
    @EnvironmentObject private var waypoints: WaypointStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    private let original: Backup.Graphic?
    let onSave: (Backup.Graphic) throws -> Void
    @State private var name: String
    @State private var folder: String
    @State private var points: [Backup.GraphicPoint]
    @State private var error: String?

    init(route: Backup.Graphic?, onSave: @escaping (Backup.Graphic) throws -> Void) {
        original = route; self.onSave = onSave
        _name = State(initialValue: route?.name ?? "")
        _folder = State(initialValue: route?.folder ?? Folders.defaultFolder)
        _points = State(initialValue: route?.points ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField("Name", text: $name).accessibilityIdentifier("route-name")
                    TextField("Folder", text: $folder)
                }
                Section {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        HStack {
                            Text("\(index + 1)").monospacedDigit()
                            Text(MGRS.parts(lat: point.lat, lon: point.lon, digits: 8)?.full ?? "Outside MGRS coverage")
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Button { points.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44) }
                                .disabled(index == 0).buttonStyle(.borderless).accessibilityLabel("Move vertex \(index + 1) up")
                        }
                    }.onDelete { points.remove(atOffsets: $0) }
                    Menu {
                        ForEach(waypoints.waypoints) { point in
                            Button(point.name) { points.append(Backup.GraphicPoint(lat: point.lat, lon: point.lon)) }
                        }
                    } label: { Label("Append waypoint", systemImage: "plus") }
                        .disabled(waypoints.waypoints.isEmpty)
                        .accessibilityIdentifier("append-route-waypoint")
                } header: { Text("Vertices · in travel order") } footer: { Text("At least two vertices are required. Repeated vertices can close a route. Swipe a vertex to remove it.") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .navigationTitle(original == nil ? "New route" : "Edit route").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var route = original ?? Backup.Graphic(id: UUID().uuidString.lowercased(), name: "", type: "route", points: [], createdAt: Int64(Date().timeIntervalSince1970 * 1000))
                        route.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        route.folder = Folders.canonical(folder); route.points = points
                        do { try onSave(route); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || points.count < 2)
                        .accessibilityIdentifier("save-route")
                }
            }
        }.foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent)
    }
}

struct RouteDetailView: View {
    let routeID: String
    var onNavigate: () -> Void = {}
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var routeRequest: RouteEditorRequest?
    @State private var status: String?
    private var route: Backup.Graphic? { fieldData.document.graphics.first { $0.id == routeID } }
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    private func legs(_ route: Backup.Graphic) -> [RouteCard.Leg] {
        RouteCard.legs(points: route.points.map { GeoPoint(lat: $0.lat, lon: $0.lon) }, northReference: settings.northRef.rawValue,
                       pacePer100m: settings.pacePer100m) { point in
            DeclinationService(overrideDegrees: settings.declinationOverride).declination(lat: point.lat, lon: point.lon, isCurrentPosition: false).degreesEast
        }
    }

    var body: some View {
        List {
            if let route {
                Section {
                    Toggle("Visible on map", isOn: Binding(get: { self.route?.visible ?? false }, set: { visible in
                        var changed = route; changed.visible = visible
                        perform { try fieldData.saveGraphic(changed) }
                    }))
                    Button("Edit route") { routeRequest = RouteEditorRequest(route: route) }
                    Button("Generate waypoints") { perform { try generate(route); status = "Route waypoints updated" } }
                        .accessibilityIdentifier("generate-route-waypoints")
                    ShareLink("Share route card", item: cardText(route))
                }
                Section("Route card · \(settings.northRef.letter)") {
                    ForEach(legs(route), id: \.index) { leg in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Leg \(leg.index)").font(.headline)
                            Text("AZ \(angle(leg.forward))  ·  BACK \(angle(leg.reverse))")
                                .font(.system(.subheadline, design: .monospaced))
                            Text("\(Format.distance(meters: leg.distanceMeters, unit: settings.units)) · \(leg.paces) paces")
                                .font(.subheadline)
                            Text(leg.destinationGrid).font(.system(.caption, design: .monospaced))
                            Button("Navigate to vertex \(leg.index + 1)") {
                                perform {
                                    try generate(route)
                                    guard let target = waypoints.waypoints.first(where: { $0.sourceRouteId == routeID && $0.sourceRoutePointIndex == leg.index }) else { return }
                                    waypoints.select(target.id); onNavigate()
                                }
                            }
                        }.padding(.vertical, 6)
                    }
                }
                Button("Delete route", role: .destructive) { perform { try fieldData.deleteGraphic(route.id); dismiss() } }
            }
            if let status { Text(status).font(.footnote).foregroundStyle(palette.accent) }
        }
        .scrollContentBackground(.hidden).background { FieldScreenBackground() }
        .foregroundStyle(palette.ink).tint(palette.accent)
        .navigationTitle(route?.name ?? "Route")
        .sheet(item: $routeRequest) { request in RouteEditor(route: request.route) { changed in
            try fieldData.saveGraphic(changed); waypoints.addFolder(changed.folder)
        } }
    }
    private func generate(_ route: Backup.Graphic) throws {
        try waypoints.replaceRouteWaypoints(routeID: route.id, name: route.name, points: route.points.map { GeoPoint(lat: $0.lat, lon: $0.lon) }, folder: route.folder)
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
    private func angle(_ value: Double?) -> String { value.map { Format.angle(degrees: $0, unit: settings.angleUnit) } ?? "—" }
    private func cardText(_ route: Backup.Graphic) -> String {
        ([route.name, "North: \(settings.northRef.letter)"] + legs(route).map {
            "Leg \($0.index): \(angle($0.forward)), back \(angle($0.reverse)), \(Format.distance(meters: $0.distanceMeters, unit: settings.units)), \($0.paces) paces, \($0.destinationGrid)"
        }).joined(separator: "\n")
    }
}

struct TrackDetailView: View {
    let trackID: String
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var export: GPXDocumentFile?
    private var track: Backup.TrackMeta? { fieldData.document.tracks.first { $0.id == trackID } }
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    var body: some View {
        List {
            if let track {
                Text("\(track.pointCount) points")
                Text(Format.distance(meters: track.distanceM, unit: settings.units))
                Text("Folder: \(track.folder)")
                Toggle("Visible on map", isOn: Binding(get: { self.track?.visible ?? false }, set: { visible in
                    perform { try fieldData.setTrackVisible(trackID, visible: visible) }
                }))
                Button("Export GPX") {
                    perform { export = GPXDocumentFile(text: GPX.build(waypoints: [], tracks: [.init(name: track.name, points: try fieldData.points(for: trackID))])) }
                }
                Button("Delete track", role: .destructive) { perform { try fieldData.deleteTrack(trackID); dismiss() } }
            }
            if let status { Text(status).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background { FieldScreenBackground() }
        .foregroundStyle(palette.ink).tint(palette.accent)
        .navigationTitle(track?.name ?? "Track")
        .fileExporter(isPresented: Binding(get: { export != nil }, set: { if !$0 { export = nil } }), document: export,
                      contentType: .gridFixGPX, defaultFilename: "track") { result in
            if case let .failure(error) = result { status = error.localizedDescription }
            export = nil
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
}
