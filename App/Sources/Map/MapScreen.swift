import GridFixCore
import MapLibre
import SwiftUI

/// Raster catalog, imported maps, and saved areas share one tile pipeline.
/// Field overlays stay installed while the underlying raster layer changes.
struct MapScreen: View {
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var recorder: TrackRecorder
    @EnvironmentObject private var maps: MapLayerStore
    @EnvironmentObject private var boundaries: BoundaryMonitor
    @EnvironmentObject private var lanes: NavigationLaneStore
    @EnvironmentObject private var terrain: TerrainSession
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var onNavigate: () -> Void = {}
    var onOpenCourse: () -> Void = {}
    var onOrientation: () -> Void = {}
    @State private var intervalLabel = "—"
    @State private var overlayRoutes = 0
    @State private var overlayTracks = 0
    @State private var hasFieldPoints = false
    @State private var centre = CLLocationCoordinate2D(latitude: 24.4539, longitude: 54.3773)
    @State private var selectedID: String?
    @State private var qrRequest: PositionQRRequest?
    @State private var cameraRequest: MapCameraRequest?
    @State private var editorRequest: WaypointEditorRequest?
    @State private var showingLayers = false
    @State private var showingMapToolSettings = false
    @State private var showingGoTo = false
    @State private var showingTerrain = false
    @State private var showingTools = false
    @State private var pendingTool: MapToolChoice?
    @State private var fieldFixRequest: FieldFixRequest?
    @State private var planningRequest: FieldPlanningRequest?
    @State private var viewport = MapBounds(south: 24, north: 25, west: 54, east: 55)
    @State private var zoom = 6.5
    @State private var contourLabel = ""
    @State private var showingBoundaries = false
    @State private var boundaryDraft: BoundaryDraft?
    @State private var showingGraphics = false
    @State private var graphicDraft: GraphicDraft?
    @State private var measuringArea = false
    @State private var rulerAnchor: GeoPoint?
    @State private var rulerTarget = GeoPoint(lat: 24.4539,lon: 54.3773)
    @State private var graphicError: String?
    @StateObject private var graphicMutation = FieldMutation()
    @State private var routeWaypointOffer: Backup.Graphic?
    @State private var showingRouteWaypointOffer = false
    @State private var routeWaypointError: String?
    @State private var showingLanes = false
    @State private var pendingLane: LaneMapAction?
    @State private var laneDraft: LaneEditingDraft?
    @State private var showingLaneDetails = false
    @State private var choosingLaneLine = false
    @State private var replacingLaneAction: LaneMapAction?
    @State private var confirmingLaneReplace = false

    private var chromeNight: Bool { settings.nightMode }
    private var compactMap: Bool { verticalSizeClass == .compact }
    private var activeMapTools: Set<String> {
        var active: Set<String> = []
        if boundaryDraft != nil || graphicDraft != nil || laneDraft != nil { active.insert("draw") }
        if rulerAnchor != nil { active.insert("ruler") }
        if measuringArea || terrain.viewshed != nil { active.insert("tools") }
        if recorder.phase != .idle || recorder.failure != nil || recorder.hasRecoveryNotice { active.insert("record") }
        return active
    }
    private func showsTool(_ key: String) -> Bool { !settings.hiddenMapTools.contains(key) || activeMapTools.contains(key) }
    private var palette: FieldPalette { FieldPalette(night: chromeNight) }
    private var mapInk: Color { chromeNight ? palette.ink : .black }
    private var mapInkDim: Color { chromeNight ? palette.inkDim : .black.opacity(0.65) }
    private var visible: [Waypoint] {
        WaypointMapSnapshot.visible(waypoints: store.waypoints, folders: store.folders)
    }
    private var selected: Waypoint? { visible.first { $0.id == selectedID } }

    private var mapAttribution: String {
        var text = maps.selectedMap?.attribution ?? maps.selectedLayer.attribution
        if maps.preferences.hillshade, maps.selectedMap == nil, maps.layers.contains(where: { $0.key == "hillshade" }) {
            text += " · Shading: Esri, USGS, NASA"
        }
        if maps.preferences.contours || terrain.readout?.elevation != nil || terrain.viewshed != nil { text += " · Elevation: Mapzen / AWS" }
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    var body: some View {
        ZStack {
            MapContainer(mapStore: maps, nightMode: chromeNight, fix: location.usableFix,
                         waypoints: visible, navigationID: store.selectedId,
                         document: fieldData.document, folders: store.folders, lanes: lanes.lanes, laneDraft: liveLaneDraft,
                         recordingPoints: recorder.active?.livePoints ?? [],
                         viewshed: terrain.viewshed,
                         rulerAnchor: rulerAnchor,
                         onRulerAnchor: { rulerAnchor = $0; selectedID = nil },
                         onRulerTarget: { if rulerTarget != $0 { rulerTarget = $0 } },
                         boundaryPoints: boundaryDraft?.vertices ?? boundaries.displayedArea?.vertices ?? [],
                         boundaryEditing: boundaryDraft != nil, boundarySelection: boundaryDraft?.selected,
                         onBoundaryPoint: { point in
                             guard boundaryDraft != nil, boundaryDraft!.vertices.count < 256 else { return }
                             boundaryDraft!.vertices.append(point); boundaryDraft!.selected = boundaryDraft!.vertices.count-1
                         },
                         onBoundarySelect: { boundaryDraft?.selected = $0 },
                         onBoundaryInsert: { index, point in
                             guard boundaryDraft != nil, boundaryDraft!.vertices.count < 256 else { return }
                             let position = min(index+1,boundaryDraft!.vertices.count)
                             boundaryDraft!.vertices.insert(point,at: position); boundaryDraft!.selected = position
                         },
                         onBoundaryMove: { index, point in
                             if boundaryDraft?.vertices.indices.contains(index) == true { boundaryDraft!.vertices[index] = point }
                         },
                         onBoundaryRemove: { index in
                             if boundaryDraft?.vertices.indices.contains(index) == true { boundaryDraft!.vertices.remove(at: index); boundaryDraft!.selected = nil }
                         },
                         graphicDraft: graphicDraft?.graphic, graphicSelection: graphicDraft?.selected,
                         onGraphicPoint: { if !graphicMutation.working && (laneDraft == nil || (graphicDraft?.vertices.count ?? 0) < 500) { graphicDraft?.append($0) } },
                         onGraphicSelect: { if !graphicMutation.working { graphicDraft?.selected = $0 } },
                         onGraphicInsert: { index, point in if !graphicMutation.working && (laneDraft == nil || (graphicDraft?.vertices.count ?? 0) < 500) { graphicDraft?.selected = index; graphicDraft?.insert(point) } },
                         onGraphicMove: { if !graphicMutation.working { graphicDraft?.move($0,to: $1) } },
                         onGraphicRemove: { index in if !graphicMutation.working { graphicDraft?.selected = index; graphicDraft?.removeSelected() } },
                         onGraphicPick: { guard !graphicMutation.working && laneDraft == nil else { return }; graphicMutation.clearError(); selectedID = nil; rulerAnchor = nil; measuringArea = false; graphicError = nil; graphicDraft = GraphicDraft($0) },
                         onContour: { contourLabel = $0 },
                         onOverlays: { overlayRoutes = $0; overlayTracks = $1; hasFieldPoints = $2 },
                         cameraRequest: cameraRequest,
                         onSelect: { if boundaryDraft == nil && graphicDraft == nil && laneDraft == nil { selectedID = $0 } },
                         onChange: { label, position, bounds, level in
                             intervalLabel = label; centre = position; viewport = bounds; zoom = level
                             rulerTarget = GeoPoint(lat: position.latitude,lon: position.longitude)
                             terrain.updateCentre(GeoPoint(lat: position.latitude,lon: position.longitude))
                             maps.saveCamera(lat: position.latitude, lon: position.longitude, zoom: level)
                         })
                .ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(MGRS.parts(lat: centre.latitude, lon: centre.longitude,
                                        digits: settings.mgrsDigits)?.full ?? "Outside \(settings.gridName) coverage")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .accessibilityIdentifier("map-centre-grid")
                        Text(maps.preferences.gridEnabled ? "MAP CENTRE · \(intervalLabel) GRID" : "MAP CENTRE · GRID OFF")
                            .font(.caption2.weight(.semibold)).tracking(1)
                            .foregroundStyle(mapInkDim)
                        if !compactMap, let readout = terrain.readout {
                            Text(readout.elevation.map { String(format: "ELEV %.0f m",$0) } ?? "ELEV unavailable")
                                .font(.caption2).foregroundStyle(mapInkDim).accessibilityIdentifier("map-elevation")
                            if let slope = readout.slope { Text(String(format: "SLOPE %.1f° · DEM estimate",slope)).font(.caption2).foregroundStyle(mapInkDim) }
                        }
                        if !compactMap && !contourLabel.isEmpty { Text(contourLabel).font(.caption2).foregroundStyle(mapInkDim) }
                        Text((maps.preferences.offlineOnly ? "OFFLINE ONLY · " : "") + maps.layerName)
                            .font(.caption2).foregroundStyle(mapInkDim).accessibilityIdentifier("map-layer-name")
                        if !compactMap && (overlayRoutes > 0 || overlayTracks > 0) {
                            Text("\(overlayRoutes) routes · \(overlayTracks) tracks")
                                .font(.caption2).foregroundStyle(mapInkDim).accessibilityIdentifier("map-field-overlays")
                        }
                    }
                    .padding(compactMap ? 8 : 14).fieldChrome()
                    Spacer(minLength: 0)
                    if compactMap {
                        ScrollView(.horizontal,showsIndicators: false) { HStack(spacing: 8) { mapToolButtons } }.frame(maxWidth: 420)
                    } else {
                        LazyVGrid(columns: [.init(.fixed(68)),.init(.fixed(68))],spacing: 8) { mapToolButtons }.frame(width: 144)
                    }
                }
                Spacer(minLength: 0)
                if let anchor = rulerAnchor {
                    MapRulerCard(anchor: anchor,target: rulerTarget,reset: { rulerAnchor = rulerTarget },close: { rulerAnchor = nil })
                }
                if let draft = boundaryDraft {
                    BoundaryDrawingControls(draft: Binding(get: { boundaryDraft ?? draft },set: { boundaryDraft = $0 }),
                        centre: GeoPoint(lat: centre.latitude,lon: centre.longitude),error: boundaries.error,
                        save: { if let area = boundaryDraft?.area, boundaries.save(area) { boundaryDraft = nil } },cancel: { boundaryDraft = nil; boundaries.clearError() })
                }
                if let draft = laneDraft {
                    LaneDrawingControls(draft: draft,count: graphicDraft?.vertices.count ?? 0,selected: graphicDraft?.selected != nil,busy: graphicMutation.working,error: graphicMutation.error,
                        chooseRole: switchLaneRole,
                        add: { if graphicDraft?.vertices.count ?? 0 < 500 { graphicDraft?.append(.init(lat: centre.latitude,lon: centre.longitude)) } },
                        undo: { if graphicDraft?.vertices.isEmpty == false { graphicDraft?.graphic.points.removeLast(); graphicDraft?.selected = nil } },remove: { graphicDraft?.removeSelected() },
                        useLine: { choosingLaneLine = true },drawInstead: { laneDraft?.line = .init(); loadLaneLine() },
                        review: { captureLaneLine(); showingLaneDetails = true },cancel: { laneDraft = nil; graphicDraft = nil })
                }
                if let draft = graphicDraft, laneDraft == nil {
                    GraphicDrawingControls(draft: Binding(get: { graphicDraft ?? draft },set: { graphicDraft = $0 }),measuringArea: $measuringArea,
                        centre: GeoPoint(lat: centre.latitude,lon: centre.longitude),error: graphicError ?? graphicMutation.error,saving: graphicMutation.working,
                        save: {
                            guard let draft = graphicDraft, draft.validationMessage == nil else { return }
                            graphicError = nil; routeWaypointOffer = nil
                            let isNew = draft.original == nil
                            graphicMutation.run("Saving graphic…",action: {
                                let saved = try await FieldEditAction.saveGraphic(draft.saved,original: draft.original,field: fieldData,waypoints: store)
                                if graphicDraft?.graphic.id == draft.graphic.id {
                                    graphicDraft = nil; graphicError = nil; measuringArea = false
                                    if isNew && saved.type == "route" { routeWaypointOffer = saved }
                                }
                            },completion: { presented in
                                if presented && isNew && routeWaypointOffer != nil { showingRouteWaypointOffer = true }
                            })
                        },cancel: { graphicDraft = nil; graphicError = nil; measuringArea = false })
                }
                if let waypoint = selected, boundaryDraft == nil && graphicDraft == nil && laneDraft == nil {
                    selectedCard(waypoint)
                }
                if let shade = terrain.viewshed, boundaryDraft == nil && graphicDraft == nil && laneDraft == nil {
                    Button { terrain.clearViewshed() } label: {
                        VStack(alignment: .leading,spacing: 4) {
                            Text("Viewshed · \(Int(shade.radius)) m · tap to clear").font(.caption.bold())
                            Text(chromeNight ? "Faint: seen · mid: standing · bright: masked · hatched: unknown" : "Green: seen · amber: standing · red: masked · hatched: unknown").font(.caption2)
                            if shade.missing > 0 { Text("Missing terrain: \(shade.unknownCells) unknown cells").font(.caption2) }
                        }.padding(10).fieldChrome()
                    }.buttonStyle(.plain).accessibilityIdentifier("viewshed-legend")
                }
                Text(mapAttribution)
                    .font(.system(size: 9)).foregroundStyle(chromeNight ? palette.ink : .white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.8), in: Capsule())
                    .accessibilityIdentifier("map-attribution")
                if laneDraft == nil && (!compactMap || (boundaryDraft == nil && graphicDraft == nil)) { HStack(spacing: 12) {
                    if showsTool("locate") { Button {
                        guard let fix = location.usableFix else { return }
                        cameraRequest = MapCameraRequest(action: .locate(fix.lat, fix.lon))
                    } label: {
                        Label("Locate", systemImage: "location").labelStyle(.iconOnly).frame(width: 44,height: 40)
                    }
                    .fieldGlassButton().disabled(location.usableFix == nil).accessibilityLabel("Locate") }
                    Button {
                        cameraRequest = MapCameraRequest(action: .fitData)
                    } label: {
                        Image(systemName: "viewfinder").frame(width: 44, height: 40)
                    }
                    .fieldGlassButton().disabled(visible.isEmpty && !hasFieldPoints && recorder.active?.livePoints.isEmpty != false && boundaries.displayedArea == nil && !lanes.lanes.contains(where: { $0.visible }))
                    .accessibilityLabel("Show all visible data")
                    if showsTool("record") { RecordingButton() }
                    Spacer(minLength: 0)
                    Button {
                        editorRequest = WaypointEditorRequest(lat: centre.latitude, lon: centre.longitude)
                    } label: {
                        Label("Add", systemImage: "plus").frame(minHeight: 40)
                    }
                    .fieldGlassButton().tint(palette.accent)
                    .accessibilityLabel("Add waypoint at map centre")
                } }
            }
            .disabled(graphicMutation.working)
            .padding(.horizontal, 16).padding(.top, 8)
            // The edge-to-edge UIKit map extends beneath the custom field bar.
            // Reserve its control row explicitly for the overlaid map actions.
            .padding(.bottom, 16 + (chromeNight ? FieldTabBar.controlHeight : 0))
        }
        .foregroundStyle(mapInk)
        .environment(\.colorScheme, chromeNight ? .dark : .light)
        .toolbarColorScheme(chromeNight ? .dark : .light, for: .tabBar)
        .environment(\.fieldNight, chromeNight)
        .onAppear { graphicMutation.setPresented(true); if let request = maps.focusRequest { cameraRequest = request }; receiveLaneRequest() }
        .onChange(of: maps.laneRequest?.id) { _ in receiveLaneRequest() }
        .onChange(of: graphicMutation.working) { busy in if !busy { receiveLaneRequest() } }
        .onDisappear { graphicMutation.setPresented(false) }
        .onChange(of: maps.focusRequest?.id) { _ in if let request = maps.focusRequest { cameraRequest = request } }
        .onChange(of: terrain.viewshed?.id) { _ in
            if let shade = terrain.viewshed {
                cameraRequest = MapCameraRequest(action: .showBounds(.init(south: shade.south,north: shade.north,west: shade.west,east: shade.east)))
            }
        }
        .onChange(of: maps.revision) { _ in
            Task { await terrain.sampler.invalidateFailures(); terrain.refreshCentre(.init(lat: centre.latitude,lon: centre.longitude)) }
        }
        .onChange(of: maps.preferences.offlineOnly) { _ in terrain.refreshCentre(.init(lat: centre.latitude,lon: centre.longitude)) }
        .onChange(of: maps.preferences.baseLayer) { _ in
            if let map = maps.selectedMap { cameraRequest = MapCameraRequest(action: .showBounds(map.bounds)) }
        }
        .confirmationDialog("Create navigation waypoints for this route?", isPresented: $showingRouteWaypointOffer,titleVisibility: .visible,presenting: routeWaypointOffer) { route in
            Button("Generate waypoints") {
                do { try store.replaceRouteWaypoints(routeID: route.id,name: route.name,points: route.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) },folder: route.folder) }
                catch { routeWaypointError = error.localizedDescription }
                routeWaypointOffer = nil
            }
            Button("Not now") { showingRouteWaypointOffer = false; routeWaypointOffer = nil }
        } message: { _ in Text("The route is saved. You can also generate waypoints or follow the route later from its route card.") }
        .alert("Could not generate route waypoints",isPresented: Binding(get: { routeWaypointError != nil },set: { if !$0 { routeWaypointError = nil } })) {
            Button("OK") { routeWaypointError = nil }
        } message: { Text(routeWaypointError ?? "") }
        .sheet(isPresented: $showingTools,onDismiss: runPendingTool) {
            FieldToolChooser(night: settings.nightMode) { tool in pendingTool = tool; showingTools = false }
        }
        .sheet(item: $qrRequest) { PositionQRView(request: $0, night: settings.nightMode) }
        .sheet(item: $planningRequest) { request in
            switch request.kind {
            case .sunMoon: SunMoonPlanningView(request: request)
            case .declination: DeclinationPlanningView(request: request)
            }
        }
        .sheet(item: $fieldFixRequest) { request in
            FieldFixPanel(request: request) { point in
                selectedID = nil; cameraRequest = MapCameraRequest(action: .locate(point.lat,point.lon))
            }
        }
        .sheet(isPresented: $showingTerrain) {
            TerrainPanel(centre: .init(lat: centre.latitude,lon: centre.longitude),position: location.usableFix.map { .init(lat: $0.lat,lon: $0.lon) })
        }
        .sheet(isPresented: $showingGraphics) {
            GraphicPanel(onDraw: { draft in
                graphicMutation.clearError(); selectedID = nil; rulerAnchor = nil; measuringArea = false; graphicError = nil; graphicDraft = draft
                if !draft.vertices.isEmpty { cameraRequest = MapCameraRequest(action: .showBoundary(draft.graphic.mapExtentPoints)) }
            },onShow: { graphic in cameraRequest = MapCameraRequest(action: .showBoundary(graphic.mapExtentPoints)) },onNavigate: onNavigate)
        }
        .sheet(isPresented: $showingLanes,onDismiss: runLaneRequest) {
            NavigationLaneLibraryView { pendingLane = $0; showingLanes = false }
        }
        .confirmationDialog("Replace the current unsaved drawing?",isPresented: $confirmingLaneReplace,titleVisibility: .visible) {
            Button("Replace drawing",role: .destructive) {
                boundaryDraft = nil; graphicDraft = nil; laneDraft = nil
                pendingLane = replacingLaneAction; replacingLaneAction = nil; runLaneRequest()
            }
            Button("Keep drawing",role: .cancel) { replacingLaneAction = nil }
        }
        .sheet(isPresented: $showingLaneDetails) {
            if let draft = laneDraft {
                LaneDetailsView(draft: Binding(get: { laneDraft ?? draft },set: { laneDraft = $0 }),busy: graphicMutation.working,error: graphicMutation.error,save: saveLane)
            }
        }
        .sheet(isPresented: $choosingLaneLine) {
            NavigationStack {
                List(fieldData.document.graphics.filter(NavLanes.canBeLimit)) { graphic in
                    Button(graphic.name.isEmpty ? GraphicTypes.label(graphic.type) : graphic.name) {
                        captureLaneLine(); laneDraft?.line = LaneLine(graphicId: graphic.id)
                        graphicDraft = nil; choosingLaneLine = false
                    }.accessibilityIdentifier("lane-link-"+graphic.id)
                }.navigationTitle("Use existing line").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingLaneLine = false } } }
            }.fieldSheetAppearance()
        }
        .sheet(isPresented: $showingBoundaries) {
            BoundaryPanel(onDraw: { area in
                selectedID = nil; rulerAnchor = nil; boundaries.clearError()
                boundaryDraft = area.map(BoundaryDraft.init) ?? BoundaryDraft()
                if let area { cameraRequest = MapCameraRequest(action: .showBoundary(area.vertices)) }
            },onShow: { area in boundaries.displayedID = area.id; cameraRequest = MapCameraRequest(action: .showBoundary(area.vertices)) })
        }
        .sheet(isPresented: $showingMapToolSettings) { MapToolSettingsView() }
        .sheet(isPresented: $showingGoTo) {
            MapGoToView(centre: .init(lat: centre.latitude,lon: centre.longitude)) { point in selectedID = nil; cameraRequest = .init(action: .goTo(point.lat,point.lon)) }
        }
        .sheet(isPresented: $showingLayers) {
            MapLayersView(bounds: viewport, zoom: zoom) { map in cameraRequest = MapCameraRequest(action: .showBounds(map.bounds)) }
        }
        .sheet(item: $editorRequest) { request in
            WaypointEditor(lat: request.lat, lon: request.lon) { draft in
                let waypoint = store.add(draft)
                selectedID = waypoint.id
            }
        }
    }

    @ViewBuilder private var mapToolButtons: some View {

        if showsTool("draw") {
            Button { showingLanes = true } label: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").frame(width: 44,height: 44) }
                .fieldGlassButton().accessibilityLabel("Navigation lanes").accessibilityIdentifier("map-lanes")
                .disabled(boundaryDraft != nil || graphicDraft != nil || laneDraft != nil)
            Button { showingGraphics = true } label: {
                Image(systemName: "pencil.and.outline").frame(width: 44,height: 44)
            }.fieldGlassButton().accessibilityLabel("Draw graphics and routes").accessibilityIdentifier("map-graphics")
                .disabled(boundaryDraft != nil || graphicDraft != nil || laneDraft != nil)
            Button { showingBoundaries = true } label: {
                Image(systemName: "shield.lefthalf.filled").frame(width: 44,height: 44)
            }.fieldGlassButton().accessibilityLabel("Backstops and handrails").accessibilityIdentifier("map-boundaries")
                .disabled(boundaryDraft != nil || graphicDraft != nil || laneDraft != nil)
        }
        if showsTool("layers") { Button { showingLayers = true } label: {
            Image(systemName: "square.3.layers.3d").frame(width: 44, height: 44)
        }.fieldGlassButton().accessibilityLabel("Map layers").accessibilityIdentifier("map-layers") }
        if boundaryDraft == nil && graphicDraft == nil && laneDraft == nil {
            if showsTool("tools") { Button { showingTools = true } label: { Image(systemName: "wrench.and.screwdriver").frame(width: 44,height: 44) }
                .fieldGlassButton().accessibilityLabel("Map measurements and field tools").accessibilityIdentifier("map-measure")
            Button { showingTerrain = true } label: { Image(systemName: "binoculars").frame(width: 44,height: 44) }
                .fieldGlassButton().accessibilityLabel("Terrain visibility tools").accessibilityIdentifier("map-terrain") }
        }
        if showsTool("ruler") && boundaryDraft == nil && graphicDraft == nil && laneDraft == nil {
            Button {
                if rulerAnchor != nil { rulerAnchor = nil } else { rulerAnchor = .init(lat: centre.latitude,lon: centre.longitude); rulerTarget = rulerAnchor!; selectedID = nil }
            } label: { Image(systemName: "ruler").frame(width: 44,height: 44) }
                .fieldGlassButton().accessibilityLabel(rulerAnchor == nil ? "Ruler" : "Close ruler").accessibilityIdentifier("map-ruler")
        }
        if showsTool("goto") && boundaryDraft == nil && graphicDraft == nil && laneDraft == nil {
            Button { showingGoTo = true } label: { Image(systemName: "magnifyingglass").frame(width: 44,height: 44) }
                .fieldGlassButton().accessibilityLabel("Go to coordinates").accessibilityIdentifier("map-goto")
        }
        Button { showingMapToolSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44,height: 44) }
            .fieldGlassButton().accessibilityLabel("Map buttons").accessibilityIdentifier("map-button-settings")
        Button { settings.nightMode.toggle() } label: {
            Image(systemName: chromeNight ? "moon.fill" : "moon")
                .frame(width: 44, height: 44)
        }.fieldGlassButton().accessibilityLabel("Toggle map night mode")
    }

    private var liveLaneDraft: NavLane? {
        guard var draft = laneDraft else { return nil }
        if draft.line.graphicId == nil,let graphicDraft { draft.line.points = graphicDraft.vertices }
        return draft.lane
    }
    private func receiveLaneRequest() {
        guard !graphicMutation.working,let request = maps.laneRequest else { return }
        maps.laneRequest = nil
        if case .show = request.action { pendingLane = request.action; runLaneRequest(); return }
        if graphicDraft != nil || boundaryDraft != nil || laneDraft != nil {
            replacingLaneAction = request.action; confirmingLaneReplace = true
        } else { pendingLane = request.action; runLaneRequest() }
    }
    private func captureLaneLine() {
        guard laneDraft?.line.graphicId == nil,let points = graphicDraft?.vertices else { return }
        laneDraft?.line.points = points
    }
    private func loadLaneLine() {
        guard let draft = laneDraft else { graphicDraft = nil; return }
        guard draft.line.graphicId == nil else { graphicDraft = nil; return }
        var graphic = GraphicDraft(type: "phase_line")
        graphic.graphic.name = draft.line.label.isEmpty ? draft.role.title : draft.line.label
        graphic.graphic.points = draft.line.points.map { .init(lat: $0.lat,lon: $0.lon) }
        graphicDraft = graphic
    }
    private func switchLaneRole(_ role: LaneLimit) { captureLaneLine(); laneDraft?.role = role; loadLaneLine() }
    private func runLaneRequest() {
        guard let request = pendingLane else { return }; pendingLane = nil
        switch request {
        case .show(let lane):
            let points = [lane.left,lane.right,lane.backstop].flatMap { NavLanes.points($0,graphics: fieldData.document.graphics) ?? [] }
            cameraRequest = MapCameraRequest(action: .showBoundary(points))
        case .create: beginLane(nil)
        case .edit(let lane): beginLane(lane)
        }
    }
    private func beginLane(_ lane: NavLane?) {
        selectedID = nil; rulerAnchor = nil; measuringArea = false; graphicMutation.clearError()
        laneDraft = LaneEditingDraft(lane); loadLaneLine()
        if let lane {
            cameraRequest = MapCameraRequest(action: .showBoundary([lane.left,lane.right,lane.backstop].flatMap { NavLanes.points($0,graphics: fieldData.document.graphics) ?? [] }))
        }
    }
    private func saveLane() {
        captureLaneLine()
        guard var value = laneDraft?.lane else { return }
        let original = laneDraft?.original
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.name.isEmpty {
            let targetName = value.scope == .route ? fieldData.document.graphics.first { $0.id == value.targetId }?.name : store.waypoints.first { $0.id == value.targetId }?.name
            value.name = "Lane to "+(targetName ?? "point")
        }
        let savedValue = value
        graphicMutation.run("Saving lane…",action: {
            let saved = try await lanes.save(savedValue,original: original,graphics: fieldData.document.graphics)
            do { _ = try await LibraryRestoreCommit.waypoints([],folders: [.init(name: saved.folder)],into: store) }
            catch { throw LaneSaveFolderError(message: "Lane saved. Folder settings could not be finished: \(error.localizedDescription). Retry to finish.") }
            let extent = [saved.left,saved.right,saved.backstop].flatMap { NavLanes.points($0,graphics: fieldData.document.graphics) ?? [] }
            cameraRequest = MapCameraRequest(action: .showBoundary(extent))
            showingLaneDetails = false; laneDraft = nil; graphicDraft = nil
        })
    }
    private func runPendingTool() {
        guard let tool = pendingTool else { return }
        pendingTool = nil
        switch tool {
        case .distance:
            rulerAnchor = GeoPoint(lat: centre.latitude,lon: centre.longitude); rulerTarget = rulerAnchor!; selectedID = nil
        case .area:
            rulerAnchor = nil; selectedID = nil; graphicError = nil
            graphicDraft = GraphicDraft(type: "area"); measuringArea = true
        case .resection: openFieldFix(.resection)
        case .intersection: openFieldFix(.intersection)
        case .sunMoon: openPlanning(.sunMoon)
        case .declination: openPlanning(.declination)
        case .sight: showingTerrain = true
        case .course: onOpenCourse()
        case .orientation: onOrientation()
        }
    }

    private func openPlanning(_ kind: FieldPlanningRequest.Kind) {
        rulerAnchor = nil; selectedID = nil
        planningRequest = .init(kind: kind,centre: .init(lat: centre.latitude,lon: centre.longitude))
    }

    private func openFieldFix(_ mode: FieldFix.Mode) {
        rulerAnchor = nil; selectedID = nil
        fieldFixRequest = .init(mode: mode,centre: .init(lat: centre.latitude,lon: centre.longitude),position: location.usableFix.map { .init(lat: $0.lat,lon: $0.lon) })
    }

    private func selectedCard(_ waypoint: Waypoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(waypoint.name).font(.headline)
                    Text(MGRS.parts(lat: waypoint.lat, lon: waypoint.lon, digits: settings.mgrsDigits)?.full ?? "—")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(mapInkDim)
                }
                Spacer()
                Button {
                    qrRequest = PositionQRRequest(title: waypoint.name, lat: waypoint.lat, lon: waypoint.lon, label: waypoint.name)
                } label: { Image(systemName: "qrcode").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Share waypoint as QR code").accessibilityIdentifier("map-waypoint-qr")
                Button { selectedID = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Close waypoint")
            }
            Button {
                store.select(waypoint.id)
                onNavigate()
            } label: { Label("Navigate to waypoint", systemImage: "location.north.fill").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent).tint(palette.accent).foregroundStyle(.black)
                .accessibilityIdentifier("map-navigate-waypoint")
        }
        .padding(16).fieldChrome()
    }
}

struct MapCameraRequest {
    enum Action { case locate(Double, Double), goTo(Double,Double), fitData, showBounds(MapBounds), showBoundary([GeoPoint]) }
    let id = UUID()
    let action: Action
}

private struct MapContainer: UIViewRepresentable {
    let mapStore: MapLayerStore
    let nightMode: Bool
    let fix: Fix?
    let waypoints: [Waypoint]
    let navigationID: String?
    let document: Backup.Document
    let folders: [FolderInfo]
    let lanes: [NavLane]
    let laneDraft: NavLane?
    let recordingPoints: [GeoPoint]
    let viewshed: TerrainAnalysis.Viewshed?
    let rulerAnchor: GeoPoint?
    let onRulerAnchor: (GeoPoint) -> Void
    let onRulerTarget: (GeoPoint) -> Void
    let boundaryPoints: [GeoPoint]
    let boundaryEditing: Bool
    let boundarySelection: Int?
    let onBoundaryPoint: (GeoPoint) -> Void
    let onBoundarySelect: (Int) -> Void
    let onBoundaryInsert: (Int,GeoPoint) -> Void
    let onBoundaryMove: (Int,GeoPoint) -> Void
    let onBoundaryRemove: (Int) -> Void
    let graphicDraft: Backup.Graphic?
    let graphicSelection: Int?
    let onGraphicPoint: (GeoPoint) -> Void
    let onGraphicSelect: (Int) -> Void
    let onGraphicInsert: (Int,GeoPoint) -> Void
    let onGraphicMove: (Int,GeoPoint) -> Void
    let onGraphicRemove: (Int) -> Void
    let onGraphicPick: (Backup.Graphic) -> Void
    let onContour: (String) -> Void
    let onOverlays: (Int, Int, Bool) -> Void
    let cameraRequest: MapCameraRequest?
    let onSelect: (String) -> Void
    let onChange: (String, CLLocationCoordinate2D, MapBounds, Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero)
        view.delegate = context.coordinator
        view.isPitchEnabled = false
        view.styleURL = mapStore.styleURL
        context.coordinator.maps = mapStore
        context.coordinator.hasCentred = mapStore.preferences.hasCamera
        view.logoViewPosition = .bottomLeft
        view.logoViewMargins = CGPoint(x: 12, y: 150)
        view.attributionButtonPosition = .bottomLeft
        view.attributionButtonMargins = CGPoint(x: 118, y: 150)
        let tap = UITapGestureRecognizer(target: context.coordinator,action: #selector(Coordinator.boundaryTap(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator
        for other in view.gestureRecognizers ?? [] {
            if let doubleTap = other as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired == 2 { tap.require(toFail: doubleTap) }
        }
        view.addGestureRecognizer(tap)
        let lineHold = UILongPressGestureRecognizer(target: context.coordinator,action: #selector(Coordinator.bendLine(_:)))
        lineHold.minimumPressDuration = 0.45; lineHold.delegate = context.coordinator
        context.coordinator.lineHold = lineHold; view.addGestureRecognizer(lineHold)
        let tactical = context.coordinator.tactical
        tactical.map = view; tactical.frame = view.bounds; tactical.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        view.addSubview(tactical)
        let crosshair = context.coordinator.crosshair
        crosshair.translatesAutoresizingMaskIntoConstraints = false
        crosshair.isUserInteractionEnabled = false; crosshair.accessibilityElementsHidden = true
        crosshair.layer.shadowColor = UIColor.black.cgColor; crosshair.layer.shadowRadius = 2; crosshair.layer.shadowOpacity = 0.8
        view.addSubview(crosshair)
        NSLayoutConstraint.activate([crosshair.centerXAnchor.constraint(equalTo: view.centerXAnchor),crosshair.centerYAnchor.constraint(equalTo: view.centerYAnchor),crosshair.widthAnchor.constraint(equalToConstant: 22),crosshair.heightAnchor.constraint(equalToConstant: 22)])
        view.showsUserLocation = true
        view.setCenter(CLLocationCoordinate2D(latitude: mapStore.preferences.latitude, longitude: mapStore.preferences.longitude), zoomLevel: mapStore.preferences.zoom, animated: false)
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.maps = mapStore
        // Keep a new vertex at the crosshair draggable even when it is exactly
        // at the GPS fix. The position marker returns when editing ends.
        let editing = boundaryEditing || graphicDraft != nil
        if view.showsUserLocation == editing { view.showsUserLocation = !editing }
        coordinator.crosshair.tintColor = nightMode ? .systemRed : UIColor(Blackout.accent)
        view.bringSubviewToFront(coordinator.crosshair)
        coordinator.contours.onInterval = { text in DispatchQueue.main.async { onContour(text) } }
        coordinator.onChange = onChange
        coordinator.onSelect = onSelect
        coordinator.rulerActive = rulerAnchor != nil
        coordinator.onRulerAnchor = onRulerAnchor; coordinator.onRulerTarget = onRulerTarget
        coordinator.boundaryPoints = boundaryPoints; coordinator.boundaryEditing = boundaryEditing
        coordinator.graphicEditing = graphicDraft != nil; coordinator.graphicSelection = graphicSelection; coordinator.graphicType = graphicDraft?.type
        coordinator.graphicPoints = graphicDraft?.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) } ?? []
        coordinator.onGraphicRemove = onGraphicRemove; coordinator.onBoundaryRemove = onBoundaryRemove
        coordinator.onGraphicPoint = onGraphicPoint; coordinator.onGraphicSelect = onGraphicSelect; coordinator.onGraphicMove = onGraphicMove; coordinator.onGraphicPick = onGraphicPick; coordinator.onGraphicInsert = onGraphicInsert
        coordinator.boundarySelection = boundarySelection
        // A quick pair of drawing taps must add vertices, not zoom the map.
        // Pinch/pan remain available while drawing.
        for gesture in view.gestureRecognizers ?? [] {
            if let tap = gesture as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 { tap.isEnabled = !editing }
        }
        coordinator.onBoundaryPoint = onBoundaryPoint; coordinator.onBoundarySelect = onBoundarySelect; coordinator.onBoundaryMove = onBoundaryMove; coordinator.onBoundaryInsert = onBoundaryInsert
        coordinator.boundaryOverlay.update(points: boundaryPoints,editing: boundaryEditing,selected: boundarySelection,night: nightMode,map: view)
        coordinator.laneOverlay.update(lanes: lanes,draft: laneDraft,graphics: document.graphics,folders: folders,night: nightMode)
        coordinator.graphicHandles.update(points: graphicDraft?.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) } ?? [],editing: graphicDraft != nil,selected: graphicSelection,night: nightMode,map: view,closed: graphicDraft.map { GraphicTypes.isArea($0.type) } ?? false,allowInsertion: graphicDraft.map { GraphicTypes.fixedPoints($0.type) == nil } ?? false)
        coordinator.tactical.update(document: document,folders: folders,draft: graphicDraft,night: nightMode,light: ["sat","usgs_img"].contains(mapStore.preferences.baseLayer),viewshed: viewshed,rulerAnchor: rulerAnchor)
        coordinator.overlay.nightMode = nightMode
        coordinator.overlay.enabled = mapStore.preferences.gridEnabled
        coordinator.overlay.lightLines = ["sat", "usgs_img"].contains(mapStore.preferences.baseLayer)
        coordinator.nightMode = nightMode
        if let style = view.style { coordinator.rasterLayers.update(style: style, store: mapStore, night: nightMode); coordinator.contours.refresh(map: view, store: mapStore, night: nightMode) }
        coordinator.fieldOverlay.onChange = onOverlays
        var overlayDocument = document
        if let i = overlayDocument.tracks.firstIndex(where: { $0.id == mapStore.viewedTrackID }) { overlayDocument.tracks[i].visible = true }
        coordinator.fieldOverlay.update(document: overlayDocument, folders: folders, night: nightMode)
        coordinator.liveOverlay.update(recordingPoints)
        coordinator.sync(waypoints, navigationID: navigationID, night: nightMode, in: view)
        coordinator.raiseAnnotations(in: view)
        if let request = cameraRequest, coordinator.lastRequest != request.id {
            coordinator.lastRequest = request.id
            switch request.action {
            case let .showBoundary(points):
                if let bounds = FieldMapGeometry.bounds(points), let first = points.first {
                    if bounds.south == bounds.north && bounds.west == bounds.east {
                        view.setCenter(CLLocationCoordinate2D(latitude: first.lat,longitude: first.lon),zoomLevel: 16,animated: true)
                    } else { view.setVisibleCoordinateBounds(MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: bounds.south,longitude: bounds.west),ne: CLLocationCoordinate2D(latitude: bounds.north,longitude: bounds.east)),edgePadding: UIEdgeInsets(top: 210,left: 65,bottom: 350,right: 65),animated: true,completionHandler: nil) }
                }
            case let .showBounds(bounds):
                view.setVisibleCoordinateBounds(MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.west), ne: CLLocationCoordinate2D(latitude: bounds.north, longitude: bounds.east)), edgePadding: UIEdgeInsets(top: 180, left: 30, bottom: 220, right: 30), animated: true, completionHandler: nil)
            case let .goTo(lat,lon):
                view.setCenter(CLLocationCoordinate2D(latitude: lat,longitude: lon),zoomLevel: view.zoomLevel < 14 ? 15 : view.zoomLevel,animated: true)
            case let .locate(lat, lon):
                view.setCenter(CLLocationCoordinate2D(latitude: lat, longitude: lon), zoomLevel: 14, animated: true)
            case .fitData:
                let points = waypoints.map { GeoPoint(lat: $0.lat, lon: $0.lon) } + coordinator.fieldOverlay.points + coordinator.laneOverlay.points + recordingPoints + boundaryPoints
                if let bounds = FieldMapGeometry.bounds(points) {
                    if bounds.south == bounds.north && bounds.west == bounds.east {
                        view.setCenter(CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.west), zoomLevel: 15, animated: true)
                    } else {
                        view.setVisibleCoordinateBounds(MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.west),
                                                                          ne: CLLocationCoordinate2D(latitude: bounds.north, longitude: bounds.east)),
                                                        edgePadding: UIEdgeInsets(top: 140, left: 82, bottom: 240, right: 82), animated: true, completionHandler: nil)
                    }
                }
            }
            coordinator.hasCentred = true
        } else if let fix, !coordinator.hasCentred {
            coordinator.hasCentred = true
            view.setCenter(CLLocationCoordinate2D(latitude: fix.lat, longitude: fix.lon), zoomLevel: 14, animated: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate, UIGestureRecognizerDelegate {
        let crosshair = UIImageView(image: UIImage(systemName: "plus",withConfiguration: UIImage.SymbolConfiguration(pointSize: 22,weight: .light)))
        let overlay = GridOverlay()
        let fieldOverlay = FieldOverlay()
        let laneOverlay = NavigationLaneMapOverlay()
        let liveOverlay = LiveTrackOverlay()
        let rasterLayers = RasterMapLayers()
        let contours = ContourMapOverlay()
        let boundaryOverlay = BoundaryMapOverlay()
        let graphicHandles = BoundaryMapOverlay(identifier: "graphic",drawArea: false)
        let tactical = TacticalMapOverlay(frame: .zero)
        var graphicEditing = false
        var rulerActive = false
        var onRulerAnchor: ((GeoPoint) -> Void)?
        var onRulerTarget: ((GeoPoint) -> Void)?
        var graphicType: String?
        var graphicPoints: [GeoPoint] = []
        weak var lineHold: UILongPressGestureRecognizer?
        private var lineDrag: (owner: String,index: Int)?
        var onGraphicRemove: ((Int) -> Void)?
        var onBoundaryRemove: ((Int) -> Void)?
        var graphicSelection: Int?
        var onGraphicPoint: ((GeoPoint) -> Void)?
        var onGraphicSelect: ((Int) -> Void)?
        var onGraphicInsert: ((Int,GeoPoint) -> Void)?
        var onGraphicMove: ((Int,GeoPoint) -> Void)?
        var onGraphicPick: ((Backup.Graphic) -> Void)?
        var boundaryPoints: [GeoPoint] = []
        var boundaryEditing = false
        var boundarySelection: Int?
        var onBoundaryPoint: ((GeoPoint) -> Void)?
        var onBoundarySelect: ((Int) -> Void)?
        var onBoundaryInsert: ((Int,GeoPoint) -> Void)?
        var onBoundaryMove: ((Int,GeoPoint) -> Void)?
        @objc func boundaryTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MLNMapView else { return }
            if rulerActive {
                let point = map.convert(gesture.location(in: map),toCoordinateFrom: map)
                onRulerAnchor?(.init(lat: point.latitude,lon: TerrainGeometry.wrap(point.longitude))); return
            }
            if !boundaryEditing && !graphicEditing {
                if let graphic = tactical.graphic(at: gesture.location(in: tactical)) { onGraphicPick?(graphic) }
                return
            }
            let point = map.convert(gesture.location(in: map),toCoordinateFrom: map)
            let location = GeoPoint(lat: point.latitude,lon: ((point.longitude+540).truncatingRemainder(dividingBy: 360))-180)
            if graphicEditing {
                let tap = gesture.location(in: map)
                let nearest = previous.map { waypoint -> (Waypoint,CGFloat) in
                    let position = map.convert(CLLocationCoordinate2D(latitude: waypoint.lat,longitude: waypoint.lon),toPointTo: map)
                    return (waypoint,hypot(position.x-tap.x,position.y-tap.y))
                }.filter { $0.1 < 30 }.min { $0.1 < $1.1 }
                if graphicType == "route", let waypoint = nearest?.0 { onGraphicPoint?(GeoPoint(lat: waypoint.lat,lon: waypoint.lon)) }
                else { onGraphicPoint?(location) }
            } else { onBoundaryPoint?(location) }
        }
        private func lineSegment(at touch: CGPoint,in map: MLNMapView) -> (owner: String,index: Int)? {
            let points: [GeoPoint], owner: String, closed: Bool
            if boundaryEditing { points = boundaryPoints; owner = "boundary"; closed = points.count >= 3 }
            else if graphicEditing, let type = graphicType, GraphicTypes.fixedPoints(type) == nil {
                points = graphicPoints; owner = "graphic"; closed = GraphicTypes.isArea(type) && points.count >= 3
            } else { return nil }
            guard points.count >= 2, points.count < (owner == "boundary" ? 256 : 4096) else { return nil }
            var best = CGFloat(22), result: Int?
            for i in 0..<(closed ? points.count : points.count-1) {
                let a = points[i], b = points[(i+1)%points.count]
                let lon = map.centerCoordinate.longitude+TerrainGeometry.wrap(a.lon-map.centerCoordinate.longitude)
                let p = map.convert(CLLocationCoordinate2D(latitude: a.lat,longitude: lon),toPointTo: map)
                let q = map.convert(CLLocationCoordinate2D(latitude: b.lat,longitude: lon+TerrainGeometry.wrap(b.lon-a.lon)),toPointTo: map)
                let dx = q.x-p.x, dy = q.y-p.y, length = dx*dx+dy*dy
                guard length > 0 else { continue }
                let t = min(1,max(0,((touch.x-p.x)*dx+(touch.y-p.y)*dy)/length))
                let distance = hypot(touch.x-p.x-t*dx,touch.y-p.y-t*dy)
                if distance < best { best = distance; result = i }
            }
            return result.map { (owner,$0) }
        }
        @objc func bendLine(_ gesture: UILongPressGestureRecognizer) {
            guard let map = gesture.view as? MLNMapView else { return }
            let touch = gesture.location(in: map), coordinate = map.convert(touch,toCoordinateFrom: map)
            let point = GeoPoint(lat: coordinate.latitude,lon: TerrainGeometry.wrap(coordinate.longitude))
            switch gesture.state {
            case .began:
                guard let segment = lineSegment(at: touch,in: map) else { return }
                lineDrag = (segment.owner,segment.index+1)
                if segment.owner == "graphic" { onGraphicInsert?(segment.index,point) } else { onBoundaryInsert?(segment.index,point) }
            case .changed, .ended:
                if let drag = lineDrag {
                    if drag.owner == "graphic" { onGraphicMove?(drag.index,point) } else { onBoundaryMove?(drag.index,point) }
                }
                if gesture.state == .ended { lineDrag = nil }
            case .cancelled, .failed:
                if let drag = lineDrag {
                    if drag.owner == "graphic" { onGraphicRemove?(drag.index) } else { onBoundaryRemove?(drag.index) }
                }
                lineDrag = nil
            default: break
            }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === lineHold, let map = gestureRecognizer.view as? MLNMapView else { return true }
            return lineSegment(at: gestureRecognizer.location(in: map),in: map) != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === lineHold || otherGestureRecognizer === lineHold { return false }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is MLNAnnotationView || current is UIControl { return false }
                view = current.superview
            }
            return true
        }
        var maps: MapLayerStore?
        var nightMode = false
        var hasCentred = false
        var lastRequest: UUID?
        var annotations: [String: WaypointAnnotation] = [:]
        var onSelect: ((String) -> Void)?
        var onChange: ((String, CLLocationCoordinate2D, MapBounds, Double) -> Void)?
        private var previous: [Waypoint] = []
        private var navigationID: String?
        private var night = false

        func sync(_ waypoints: [Waypoint], navigationID: String?, night: Bool, in map: MLNMapView) {
            guard previous != waypoints || self.navigationID != navigationID || self.night != night else { return }
            previous = waypoints
            self.navigationID = navigationID
            self.night = night
            let ids = Set(waypoints.map(\.id))
            var removed: [WaypointAnnotation] = [], added: [WaypointAnnotation] = []
            for id in Array(annotations.keys) where !ids.contains(id) {
                if let old = annotations.removeValue(forKey: id) { removed.append(old) }
            }
            for waypoint in waypoints {
                if let old = annotations[waypoint.id], old.waypoint == waypoint {
                    (map.view(for: old) as? WaypointMarkerView)?.configure(waypoint, selected: navigationID == waypoint.id, night: night)
                } else {
                    if let old = annotations.removeValue(forKey: waypoint.id) { removed.append(old) }
                    let annotation = WaypointAnnotation(waypoint)
                    annotations[waypoint.id] = annotation
                    added.append(annotation)
                }
            }
            // MapLibre reconciles its annotation views on each call. Individual
            // insertion repeatedly rebuilds the growing hierarchy for a large
            // library; commit the complete diff in two operations instead.
            if !removed.isEmpty { map.removeAnnotations(removed) }
            if !added.isEmpty { map.addAnnotations(added) }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if let vertex = annotation as? BoundaryVertexAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "boundary-vertex") as? BoundaryVertexView) ?? BoundaryVertexView(reuseIdentifier: "boundary-vertex")
                view.configure(index: vertex.index,selected: !vertex.isMidpoint && (vertex.owner == "graphic" ? graphicSelection : boundarySelection) == vertex.index,night: nightMode,owner: vertex.owner,isMidpoint: vertex.isMidpoint)
                view.onSelect = { [weak self] in
                    if vertex.isMidpoint { self?.insertVertex(vertex,at: vertex.coordinate) }
                    else { self?.selectVertex(vertex) }
                }
                view.onDragStart = { [weak self] in self?.selectVertex(vertex) }
                view.onDragEnd = { [weak self] point in
                    if vertex.isMidpoint { self?.insertVertex(vertex,at: point); return }
                    let p = GeoPoint(lat: point.latitude,lon: ((point.longitude+540).truncatingRemainder(dividingBy: 360))-180)
                    if vertex.owner == "graphic" { self?.onGraphicMove?(vertex.index,p) } else { self?.onBoundaryMove?(vertex.index,p) }
                }
                return view
            }
            guard let annotation = annotation as? WaypointAnnotation else { return nil }
            let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: "waypoint") as? WaypointMarkerView)
                ?? WaypointMarkerView(reuseIdentifier: "waypoint")
            marker.configure(annotation.waypoint, selected: navigationID == annotation.waypoint.id, night: night)
            return marker
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            if let vertex = annotation as? BoundaryVertexAnnotation {
                selectVertex(vertex); mapView.deselectAnnotation(vertex,animated: false); return
            }
            if rulerActive {
                let point = annotation.coordinate
                if CLLocationCoordinate2DIsValid(point) { onRulerAnchor?(.init(lat: point.latitude,lon: TerrainGeometry.wrap(point.longitude))) }
                mapView.deselectAnnotation(annotation,animated: false); return
            }
            guard let annotation = annotation as? WaypointAnnotation else { return }
            if graphicEditing && graphicType == "route" {
                onGraphicPoint?(GeoPoint(lat: annotation.waypoint.lat,lon: annotation.waypoint.lon))
            } else { onSelect?(annotation.waypoint.id) }
            // Deselect immediately so the same marker can reopen a dismissed card.
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            if let maps { rasterLayers.update(style: style, store: maps, night: nightMode) }
            overlay.install(into: style)
            fieldOverlay.install(into: style)
            laneOverlay.install(style)
            liveOverlay.install(into: style)
            contours.install(style: style)
            boundaryOverlay.install(style: style)
            graphicHandles.install(style: style)
            boundaryOverlay.update(points: boundaryPoints,editing: boundaryEditing,selected: boundarySelection,night: nightMode,map: mapView)
            redraw(mapView)
        }

        func insertVertex(_ vertex: BoundaryVertexAnnotation,at point: CLLocationCoordinate2D) {
            let p = GeoPoint(lat: point.latitude,lon: ((point.longitude+540).truncatingRemainder(dividingBy: 360))-180)
            if vertex.owner == "graphic" { onGraphicInsert?(vertex.index,p) } else { onBoundaryInsert?(vertex.index,p) }
        }
        func selectVertex(_ vertex: BoundaryVertexAnnotation) {
            guard !vertex.isMidpoint else { return }
            if vertex.owner == "graphic" { onGraphicSelect?(vertex.index) } else { onBoundarySelect?(vertex.index) }
        }
        func raiseAnnotations(in map: MLNMapView) {
            // Place the canvas immediately below native annotations, inside
            // their hosting view. Raising their outer ancestor can raise the
            // Metal basemap over the tactical canvas as well.
            if let marker = (map.annotations ?? []).compactMap({ map.view(for: $0) }).first,
               let container = marker.superview {
                let host = container === map ? map : container.superview
                let sibling = container === map ? marker : container
                if let host {
                    if tactical.superview !== host { tactical.removeFromSuperview(); tactical.frame = host.bounds }
                    host.insertSubview(tactical,belowSubview: sibling)
                }
            }
            map.bringSubviewToFront(crosshair)
        }
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            tactical.setNeedsDisplay()
            if rulerActive {
                let point = GeoPoint(lat: mapView.centerCoordinate.latitude,lon: TerrainGeometry.wrap(mapView.centerCoordinate.longitude))
                DispatchQueue.main.async { [weak self] in if self?.rulerActive == true { self?.onRulerTarget?(point) } }
            }
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) { redraw(mapView) }

        private func redraw(_ map: MLNMapView) {
            tactical.setNeedsDisplay(); raiseAnnotations(in: map)
            if let maps { contours.refresh(map: map, store: maps, night: nightMode) }
            if let style = map.style, !overlay.isInstalled { overlay.install(into: style) }
            overlay.refresh(bounds: map.visibleCoordinateBounds,
                            metersPerPoint: map.metersPerPoint(atLatitude: map.centerCoordinate.latitude),
                            viewSize: map.bounds.size, safeArea: map.safeAreaInsets)
            // MapLibre may call during updateUIView; publish on the next main turn.
            let label = overlay.intervalLabel, centre = map.centerCoordinate
            let b = map.visibleCoordinateBounds
            let bounds = MapBounds(south: b.sw.latitude, north: b.ne.latitude, west: b.sw.longitude, east: b.ne.longitude)
            let zoom = map.zoomLevel
            DispatchQueue.main.async { [weak self] in self?.onChange?(label, centre, bounds, zoom) }
        }
    }
}

private final class WaypointAnnotation: MLNPointAnnotation {
    let waypoint: Waypoint
    init(_ waypoint: Waypoint) {
        self.waypoint = waypoint
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: waypoint.lat, longitude: waypoint.lon)
        title = waypoint.name
    }
    required init?(coder: NSCoder) { fatalError("Annotations are built from the waypoint store") }
}

/// Opaque marker labels keep map imagery from interfering with grid/name text.
private final class WaypointMarkerView: MLNAnnotationView {
    private let nameLabel = UILabel()
    private let dot = UIImageView()
    private let character = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 130, height: 74)
        // Keep the centre of the 44-point symbol exactly at its coordinate.
        centerOffset = CGVector(dx: 0, dy: -13)
        nameLabel.frame = CGRect(x: 0, y: 0, width: 130, height: 26)
        nameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        nameLabel.textAlignment = .center
        nameLabel.backgroundColor = .black
        nameLabel.layer.cornerRadius = 7
        nameLabel.clipsToBounds = true
        dot.frame = CGRect(x: 43, y: 28, width: 44, height: 44)
        dot.contentMode = .scaleAspectFit
        dot.layer.shadowColor = UIColor.black.cgColor
        dot.layer.shadowOpacity = 0.8
        dot.layer.shadowRadius = 2
        character.frame = dot.frame
        character.textAlignment = .center
        character.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        character.textColor = .black
        addSubview(nameLabel); addSubview(dot); addSubview(character)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("Markers are created by MapLibre") }

    func configure(_ waypoint: Waypoint, selected: Bool, night: Bool) {
        let style = WaypointMarkerStyle(waypoint: waypoint, night: night)
        nameLabel.text = waypoint.name
        nameLabel.textColor = night ? .systemRed : .white
        dot.tintColor = style.color
        dot.image = MilitaryMarkerRenderer.image(waypoint,night: night)
        dot.layer.cornerRadius = 16
        dot.layer.borderWidth = selected ? 2 : 0
        dot.layer.borderColor = (night ? UIColor.systemRed : .white).cgColor
        character.text = nil
        accessibilityLabel = "Waypoint \(waypoint.name)"
        accessibilityIdentifier = "map-waypoint-\(waypoint.id)"
        accessibilityValue = selected ? "Navigation target" : ""
    }
}
