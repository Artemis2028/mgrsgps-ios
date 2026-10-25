import GridFixCore
import SwiftUI

struct FieldLibraryView: View {
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    var onNavigate: () -> Void = {}
    var onShowMap: () -> Void = {}
    @State private var showingPractice = false
    @State private var routeRequest: RouteEditorRequest?
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }

    var body: some View {
        NavigationStack {
            List {
                if let failure = fieldData.loadError { Text(failure).foregroundStyle(palette.warn) }
                Button("Practice course") { showingPractice = true }.accessibilityIdentifier("library-practice")
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
                    HStack { Text("Track recording"); Spacer(); RecordingButton() }
                    ForEach(fieldData.document.tracks.sorted { $0.startedAt > $1.startedAt }) { track in
                        NavigationLink { TrackDetailView(trackID: track.id,onShowMap: onShowMap) } label: {
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
            .sheet(isPresented: $showingPractice) { PracticeCourseView() }
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
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var waypoints: WaypointStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    private let original: Backup.Graphic?
    let onSave: (Backup.Graphic) throws -> Void
    @State private var name: String
    @State private var folder: String
    @State private var points: [Backup.GraphicPoint]
    @State private var error: String?
    @FocusState private var focusedField: String?

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
                        .focused($focusedField, equals: "name").submitLabel(.done)
                    TextField("Folder", text: $folder)
                        .focused($focusedField, equals: "folder").submitLabel(.done)
                }
                Section {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        HStack {
                            Text("\(index + 1)").monospacedDigit()
                            Text(MGRS.parts(lat: point.lat, lon: point.lon, digits: 8)?.full ?? "Outside \(settings.gridName) coverage")
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Button { points.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44) }
                                .disabled(index == 0).buttonStyle(.borderless).accessibilityLabel("Move vertex \(index + 1) up")
                        }.accessibilityIdentifier("route-vertex-\(index)")
                    }.onDelete { points.remove(atOffsets: $0) }
                    Menu {
                        ForEach(waypoints.waypoints) { point in
                            Button(point.name) { points.append(Backup.GraphicPoint(lat: point.lat, lon: point.lon)) }.accessibilityIdentifier("route-append-choice-" + point.name)
                        }
                    } label: { Label("Append waypoint", systemImage: "plus") }
                        .disabled(waypoints.waypoints.isEmpty)
                        .accessibilityIdentifier("append-route-waypoint")
                } header: { Text("Vertices · in travel order") } footer: { Text("At least two vertices are required. Repeated vertices can close a route. Swipe a vertex to remove it.") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .onSubmit { focusedField = nil }
            .navigationTitle(original == nil ? "New route" : "Edit route").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hide keyboard") { focusedField = nil }
                }
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
    @EnvironmentObject private var navigation: NavigationSession
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var routeRequest: RouteEditorRequest?
    @State private var status: String?
    private var route: Backup.Graphic? { fieldData.document.graphics.first { $0.id == routeID } }
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    private struct Prepared { let request: RouteCardRequest; let report: RouteCard.Report }
    @State private var prepared: Prepared?
    @State private var reportError: String?
    @State private var pdfRequest: RoutePDFPreviewRequest?
    @State private var pdfTask: Task<Void,Never>?
    @State private var pdfGeneration = UUID()
    @State private var buildingPDF = false
    private var input: RouteCardRequest? { route.map { RouteCardRequest(route: $0,settings: settings) } }
    private var ready: RouteCard.Report? { prepared?.request == input ? prepared?.report : nil }

    var body: some View {
        List {
            if let route {
                Section {
                    Toggle("Visible on map", isOn: Binding(get: { self.route?.visible ?? false }, set: { visible in
                        var changed = route; changed.visible = visible
                        perform { try fieldData.saveGraphic(changed) }
                    }))
                    Button("Edit route") { routeRequest = RouteEditorRequest(route: route) }
                    Button("Follow route automatically") { navigation.follow(route); if navigation.error == nil { onNavigate() } }
                        .disabled(navigation.running || navigation.preparing).accessibilityIdentifier("follow-route")
                    if let error = navigation.error { Text(error).font(.footnote).foregroundStyle(palette.warn) }
                    Button("Generate waypoints") { perform { try generate(route); status = "Route waypoints updated" } }
                        .accessibilityIdentifier("generate-route-waypoints")
                    NavigationLink("Elevation profile") { RouteTerrainProfileView(route: route) }.accessibilityIdentifier("route-terrain-profile")
                    if let ready { ShareLink("Share route card",item: ready.shareText).accessibilityIdentifier("share-route-card") }
                    Button(buildingPDF ? "Preparing PDF…" : "Strip map PDF") { preparePDF() }
                        .disabled(buildingPDF || ready == nil).accessibilityIdentifier("prepare-strip-map-pdf")
                    if buildingPDF { ProgressView("Preparing complete route card") }
                    if let reportError { Text(reportError).font(.footnote).foregroundStyle(palette.warn) }
                }
                Section("Route card · \(settings.northRef.letter)") {
                    if let ready {
                        Text("START  "+ready.startGrid).font(.system(.caption,design: .monospaced)).accessibilityIdentifier("route-card-start")
                        ForEach(ready.rows,id: \.index) { leg in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Leg \(leg.index)").font(.headline)
                                Text("AZ \(leg.azimuth)  ·  BACK \(leg.backAzimuth)")
                                    .font(.system(.subheadline, design: .monospaced))
                                Text("\(leg.distance) · \(leg.paces) paces")
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
                        Text("TOTAL  \(ready.totalDistance) · \(ready.totalPaces) paces").font(.headline).accessibilityIdentifier("route-card-total")
                        Text("Pace \(ready.configuration.pacePer100m)/100 m · \(ready.dtg)").font(.caption)
                        Text("Azimuth from leg start; back-azimuth from leg end.").font(.footnote)
                        ForEach(Array(ready.notes.enumerated()),id: \.offset) { _,note in Text(note).font(.footnote).foregroundStyle(palette.warn) }
                    } else if reportError == nil { ProgressView("Calculating route card") }
                }
                Button("Delete route", role: .destructive) { perform { try fieldData.deleteGraphic(route.id); dismiss() } }
            }
            if let status { Text(status).font(.footnote).foregroundStyle(palette.accent) }
        }
        .scrollContentBackground(.hidden).background { FieldScreenBackground() }
        .foregroundStyle(palette.ink).tint(palette.accent)
        .navigationTitle(route?.name ?? "Route")
        .task(id: input) { await prepareReport() }
        .onDisappear { cancelPDF() }
        .onChange(of: scenePhase) { phase in if phase != .active { cancelPDF() } }
        .sheet(item: $pdfRequest) { RoutePDFPreview(request: $0) }
        .sheet(item: $routeRequest) { request in RouteEditor(route: request.route) { changed in
            try fieldData.saveGraphic(changed); waypoints.addFolder(changed.folder)
        } }
    }
    private func generate(_ route: Backup.Graphic) throws {
        try waypoints.replaceRouteWaypoints(routeID: route.id, name: route.name, points: route.points.map { GeoPoint(lat: $0.lat, lon: $0.lon) }, folder: route.folder)
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
    private func prepareReport() async {
        guard let request = input else { prepared = nil; return }
        reportError = nil
        let worker = Task.detached(priority: .userInitiated) { try RouteCardOutput.report(request) }
        do {
            let report = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
            guard !Task.isCancelled, input == request else { return }
            prepared = .init(request: request,report: report)
        } catch {
            guard !Task.isCancelled, input == request else { return }
            reportError = "Route card unavailable: "+error.localizedDescription
        }
    }
    private func cancelPDF() { pdfTask?.cancel(); pdfTask = nil; pdfGeneration = UUID(); buildingPDF = false }
    private func preparePDF() {
        guard let request = input, !buildingPDF else { return }
        cancelPDF(); buildingPDF = true; reportError = nil
        let token = pdfGeneration
        pdfTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                let report = try RouteCardOutput.report(request)
                return (report,try StripMapPDF.render(report))
            }
            do {
                let (report,data) = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                guard !Task.isCancelled, pdfGeneration == token else { return }
                buildingPDF = false; pdfTask = nil
                guard request.matches(route), input == request else { reportError = "The route or settings changed. Export again for the current route."; return }
                prepared = .init(request: request,report: report)
                pdfRequest = .init(name: report.name,data: data)
            } catch {
                guard !Task.isCancelled, pdfGeneration == token else { return }
                buildingPDF = false; pdfTask = nil; reportError = "PDF failed: "+error.localizedDescription
            }
        }
    }
}

struct TrackDetailView: View {
    let trackID: String
    var onShowMap: () -> Void = {}
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var maps: MapLayerStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var export: GPXDocumentFile?
    @State private var confirmingDelete = false
    @State private var backtracking = false
    @State private var backtrackWork: Task<Void,Never>?
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
                Button(backtracking ? "Building backtrack…" : "Create backtrack route") {
                    backtracking = true
                    backtrackWork = Task {
                        do {
                            let route = try await TrackBacktrackAction.create(track: track,field: fieldData,waypoints: waypoints)
                            backtracking = false; backtrackWork = nil
                            maps.focusRequest = MapCameraRequest(action: .showBoundary(route.mapExtentPoints)); onShowMap()
                        } catch {
                            backtracking = false; backtrackWork = nil
                            if !(error is CancellationError) { status = error.localizedDescription }
                        }
                    }
                }.disabled(backtracking || track.pointCount < 2).accessibilityIdentifier("track-create-backtrack")
                Text("Backtracking creates a reversed route, targeting 20 m shape detail and at most 64 vertices. Review it before following; navigation and haptics do not start automatically.").font(.footnote)
                Button("Delete track", role: .destructive) { confirmingDelete = true }
            }
            if let status { Text(status).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background { FieldScreenBackground() }
        .foregroundStyle(palette.ink).tint(palette.accent)
        .navigationTitle(track?.name ?? "Track")
        .onDisappear { backtrackWork?.cancel(); backtrackWork = nil; backtracking = false }
        .alert("Delete \(track?.name ?? "track")?",isPresented: $confirmingDelete) {
            Button("Delete",role: .destructive) { perform { try fieldData.deleteTrack(trackID); dismiss() } }
            Button("Cancel",role: .cancel) {}
        } message: { Text("The finished track and its saved point log will be removed.") }
        .fileExporter(isPresented: Binding(get: { export != nil }, set: { if !$0 { export = nil } }), document: export,
                      contentType: .gridFixGPX, defaultFilename: "track") { result in
            if case let .failure(error) = result { status = error.localizedDescription }
            export = nil
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
}
