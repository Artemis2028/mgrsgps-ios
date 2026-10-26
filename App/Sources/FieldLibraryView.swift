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
                    _ = try await FieldEditAction.saveGraphic(route,original: request.route,field: fieldData,waypoints: waypoints)
                }.id(request.id)
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
    let onSave: (Backup.Graphic) async throws -> Void
    @State private var name: String
    @State private var draftID: String
    @State private var folder: String
    @State private var points: [Backup.GraphicPoint]
    @StateObject private var mutation = FieldMutation()
    @FocusState private var focusedField: String?

    init(route: Backup.Graphic?, onSave: @escaping (Backup.Graphic) async throws -> Void) {
        original = route; self.onSave = onSave
        _draftID = State(initialValue: route?.id ?? UUID().uuidString.lowercased())
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
                if let label = mutation.label { ProgressView(label) }
                if let error = mutation.error { Text(error).foregroundStyle(.red) }
            }
            .disabled(mutation.working)
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .onSubmit { focusedField = nil }
            .navigationTitle(original == nil ? "New route" : "Edit route").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hide keyboard") { focusedField = nil }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(mutation.working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var route = original ?? Backup.Graphic(id: draftID, name: "", type: "route", points: [], createdAt: Int64(Date().timeIntervalSince1970 * 1000))
                        route.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        route.folder = Folders.canonical(folder); route.points = points
                        focusedField = nil
                        mutation.run("Saving route…",action: { try await onSave(route) },completion: { if $0 { dismiss() } })
                    }.disabled(mutation.working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || points.count < 2)
                        .accessibilityIdentifier("save-route")
                }
            }
        }.foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent)
            .interactiveDismissDisabled(mutation.working)
            .onAppear { mutation.setPresented(true) }.onDisappear { mutation.setPresented(false) }
    }
}

struct RouteDetailView: View {
    let routeID: String
    var onNavigate: () -> Void = {}
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var lanes: NavigationLaneStore
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var navigation: NavigationSession
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var routeRequest: RouteEditorRequest?
    @State private var status: String?
    @StateObject private var mutation = FieldMutation()
    private var route: Backup.Graphic? { fieldData.document.graphics.first { $0.id == routeID } }
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    private struct Prepared { let request: RouteCardRequest; let report: RouteCard.Report }
    @State private var prepared: Prepared?
    @State private var reportError: String?
    @State private var pdfRequest: RoutePDFPreviewRequest?
    @State private var pdfTask: Task<Void,Never>?
    @State private var pdfGeneration = UUID()
    @State private var buildingPDF = false
    @State private var followingRequested = false
    private var input: RouteCardRequest? {
        guard lanes.ready else { return nil }
        return route.map { RouteCardRequest(route: $0,settings: settings,lanes: lanes.lanes,waypoints: waypoints.waypoints,graphics: fieldData.document.graphics) }
    }
    private var ready: RouteCard.Report? { prepared?.request == input ? prepared?.report : nil }

    var body: some View {
        List {
            if let route {
                Section {
                    Toggle("Visible on map", isOn: Binding(get: { self.route?.visible ?? false }, set: { visible in
                        mutation.run("Saving visibility…",action: { try await FieldEditAction.apply(.setGraphicVisible(route.id,visible),to: fieldData) })
                    }))
                    Button("Edit route") { routeRequest = RouteEditorRequest(route: route) }
                    Button("Follow route automatically") {
                        followingRequested = true; navigation.follow(route)
                        if navigation.error != nil { followingRequested = false }
                    }.disabled(navigation.running || navigation.preparing).accessibilityIdentifier("follow-route")
                    if followingRequested && navigation.preparing {
                        ProgressView("Preparing navigation…")
                        Button("Cancel start") { navigation.pause(); followingRequested = false }.accessibilityIdentifier("cancel-route-start")
                    }
                    Button("Generate waypoints") { status = nil; mutation.run("Generating route waypoints…",action: { try await generate(route); status = "Route waypoints updated" }) }
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
                                if let limits = leg.limits { Text(limits).font(.caption).accessibilityIdentifier("route-card-limits-\(leg.index)") }
                                Button("Navigate to vertex \(leg.index + 1)") {
                                    var targetID: String?
                                    mutation.run("Preparing route waypoint…",action: {
                                        try await generate(route)
                                        targetID = waypoints.waypoints.first(where: { $0.sourceRouteId == routeID && $0.sourceRoutePointIndex == leg.index })?.id
                                        guard let targetID else { throw WaypointStore.EditFailure.removed }
                                        try await WaypointEditAction.select(targetID,in: waypoints)
                                    },completion: { visible in
                                        guard visible, targetID != nil else { return }
                                        onNavigate()
                                    })
                                }
                            }.padding(.vertical, 6)
                        }
                        Text("TOTAL  \(ready.totalDistance) · \(ready.totalPaces) paces").font(.headline).accessibilityIdentifier("route-card-total")
                        Text("Pace \(ready.configuration.pacePer100m)/100 m · \(ready.dtg)").font(.caption)
                        Text("Azimuth from leg start; back-azimuth from leg end.").font(.footnote)
                        ForEach(Array(ready.notes.enumerated()),id: \.offset) { _,note in Text(note).font(.footnote).foregroundStyle(palette.warn) }
                    } else if let error = lanes.error, !lanes.ready { Text(error).foregroundStyle(palette.warn) }
                    else if reportError == nil { ProgressView("Calculating route card") }
                }
                Button("Delete route", role: .destructive) {
                    mutation.run("Deleting route…",action: { try await FieldEditAction.apply(.deleteGraphic(route.id),to: fieldData) },completion: { if $0 { dismiss() } })
                }
            }
        }
        .disabled(mutation.working)
        .safeAreaInset(edge: .top,spacing: 0) { routeMessages }
        .onAppear { mutation.setPresented(true) }
        .scrollContentBackground(.hidden).background { FieldScreenBackground() }
        .foregroundStyle(palette.ink).tint(palette.accent)
        .navigationTitle(route?.name ?? "Route").navigationBarTitleDisplayMode(.inline)
        .task(id: input) { await prepareReport() }
        .onDisappear { followingRequested = false; mutation.setPresented(false); cancelPDF() }
        .onChange(of: navigation.running) { running in
            if running && followingRequested { followingRequested = false; onNavigate() }
        }
        .onChange(of: navigation.error) { error in if error != nil { followingRequested = false } }
        .onChange(of: scenePhase) { phase in if phase != .active { cancelPDF() } }
        .sheet(item: $pdfRequest) { RoutePDFPreview(request: $0) }
        .sheet(item: $routeRequest) { request in RouteEditor(route: request.route) { changed in
            _ = try await FieldEditAction.saveGraphic(changed,original: request.route,field: fieldData,waypoints: waypoints)
        }.id(request.id) }
    }
    @ViewBuilder private var routeMessages: some View {
        if mutation.label != nil || mutation.error != nil || navigation.error != nil || status != nil {
            VStack(alignment: .leading,spacing: 8) {
                if let label = mutation.label { ProgressView(label).tint(palette.accent) }
                if let error = mutation.error { Text(error).font(.footnote).foregroundStyle(palette.warn).accessibilityIdentifier("route-mutation-error") }
                if let error = navigation.error { Text(error).font(.footnote).foregroundStyle(palette.warn).accessibilityIdentifier("route-follow-error") }
                if let status { Text(status).font(.footnote).foregroundStyle(palette.accent) }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestLibraryWriteFailure"),
                   mutation.error != nil || navigation.error != nil {
                    Button("Repair test storage") {
                        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mgrsgps-ui-tests/waypoints-v1.json")
                        if (try? FileManager.default.contentsOfDirectory(atPath: file.path))?.isEmpty == true { try? FileManager.default.removeItem(at: file) }
                    }.frame(minHeight: 44).accessibilityIdentifier("route-repair-test-storage")
                }
                #endif
            }.frame(maxWidth: .infinity,alignment: .leading).padding(12).background(palette.background)
        }
    }

    private func generate(_ route: Backup.Graphic) async throws {
        try await RouteWaypointAction.generate(route,to: waypoints,field: fieldData)
    }
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
                guard request.matches(route), input == request else { reportError = "The route, lane limits or settings changed. Export again for the current route."; return }
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
    @StateObject private var mutation = FieldMutation()
    @State private var export: FieldExportDocumentFile?
    @StateObject private var exportTransfer = FieldExportTransfer()
    @State private var showingProtectedExport = false
    @State private var protectedPassword: String?
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
                    mutation.run("Saving visibility…",action: { try await FieldEditAction.apply(.setTrackVisible(trackID,visible),to: fieldData) })
                }))
                Button("Export GPX") { prepareExport() }
                Button("Export protected GPX") { showingProtectedExport = true }
                    .accessibilityIdentifier("track-protected-export")
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
            if let label = mutation.label { ProgressView(label).tint(palette.accent) }
            if let error = mutation.error { Text(error).foregroundStyle(palette.warn) }
            if let status { Text(status).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background { FieldScreenBackground() }
        .foregroundStyle(palette.ink).tint(palette.accent)
        .navigationTitle(track?.name ?? "Track")
        .disabled(exportTransfer.format != nil || mutation.working)
        .safeAreaInset(edge: .top) {
            if exportTransfer.format != nil {
                HStack {
                    ProgressView().tint(palette.accent)
                    Text("Preparing GPX…").font(.footnote)
                    Spacer()
                    Button("Cancel") { exportTransfer.cancel(); status = "Export cancelled" }
                        .frame(minHeight: 44).accessibilityIdentifier("field-export-cancel")
                }.padding(.horizontal,16).foregroundStyle(palette.ink).tint(palette.accent).accessibilityIdentifier("field-export-progress")
            }
        }
        .onAppear { mutation.setPresented(true) }
        .onDisappear { mutation.setPresented(false); exportTransfer.cancel(); backtrackWork?.cancel(); backtrackWork = nil; backtracking = false }
        .alert("Delete \(track?.name ?? "track")?",isPresented: $confirmingDelete) {
            Button("Delete",role: .destructive) { mutation.run("Deleting track…",action: { try await FieldEditAction.apply(.deleteTrack(trackID),to: fieldData) },completion: { if $0 { dismiss() } }) }
            Button("Cancel",role: .cancel) {}
        } message: { Text("The finished track and its saved point log will be removed.") }
        .sheet(isPresented: $showingProtectedExport,onDismiss: {
            guard let password = protectedPassword else { return }; protectedPassword = nil
            prepareExport(password: password)
        }) {
            BackupPasswordSheet(exporting: true,interchange: true) { password in
                protectedPassword = password; showingProtectedExport = false
            }
        }
        .background {
            if let export {
                FieldFileExportPresentation(document: export,onDismiss: { self.export = nil }) { result in
                    if case let .failure(error) = result { status = error.localizedDescription }
                    self.export = nil
                }
            }
        }
    }
    private func prepareExport(password: String? = nil) {
        guard let current = track,export == nil else { return }; status = nil
        exportTransfer.start(.track(current,fieldData.document.trackFiles[trackID] ?? Data()),password: password) { result in
            switch result {
            case .success(let prepared): export = FieldExportDocumentFile(prepared)
            case .failure(let error): status = "Export failed: " + error.localizedDescription
            }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
}
