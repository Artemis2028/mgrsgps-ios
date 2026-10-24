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
    var onNavigate: () -> Void = {}
    @State private var intervalLabel = "—"
    @State private var overlayRoutes = 0
    @State private var overlayTracks = 0
    @State private var hasFieldPoints = false
    @State private var centre = CLLocationCoordinate2D(latitude: 24.4539, longitude: 54.3773)
    @State private var selectedID: String?
    @State private var cameraRequest: MapCameraRequest?
    @State private var editorRequest: WaypointEditorRequest?
    @State private var showingLayers = false
    @State private var viewport = MapBounds(south: 24, north: 25, west: 54, east: 55)
    @State private var zoom = 6.5
    @State private var contourLabel = ""
    @State private var showingBoundaries = false
    @State private var boundaryDraft: BoundaryDraft?
    @State private var showingGraphics = false
    @State private var graphicDraft: GraphicDraft?
    @State private var graphicError: String?
    @State private var routeWaypointOffer: Backup.Graphic?
    @State private var showingRouteWaypointOffer = false
    @State private var routeWaypointError: String?

    private var chromeNight: Bool { settings.nightMode }
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
        if maps.preferences.contours { text += " · Elevation: Mapzen / AWS" }
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    var body: some View {
        ZStack {
            MapContainer(mapStore: maps, nightMode: chromeNight, fix: location.usableFix,
                         waypoints: visible, navigationID: store.selectedId,
                         document: fieldData.document, folders: store.folders,
                         recordingPoints: recorder.active?.livePoints ?? [],
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
                         graphicDraft: graphicDraft?.graphic, graphicSelection: graphicDraft?.selected,
                         onGraphicPoint: { graphicDraft?.append($0) },
                         onGraphicSelect: { graphicDraft?.selected = $0 },
                         onGraphicInsert: { index, point in graphicDraft?.selected = index; graphicDraft?.insert(point) },
                         onGraphicMove: { graphicDraft?.move($0,to: $1) },
                         onGraphicPick: { selectedID = nil; graphicError = nil; graphicDraft = GraphicDraft($0) },
                         onContour: { contourLabel = $0 },
                         onOverlays: { overlayRoutes = $0; overlayTracks = $1; hasFieldPoints = $2 },
                         cameraRequest: cameraRequest,
                         onSelect: { if boundaryDraft == nil && graphicDraft == nil { selectedID = $0 } },
                         onChange: { label, position, bounds, level in
                             intervalLabel = label; centre = position; viewport = bounds; zoom = level
                             maps.saveCamera(lat: position.latitude, lon: position.longitude, zoom: level)
                         })
                .ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(MGRS.parts(lat: centre.latitude, lon: centre.longitude,
                                        digits: settings.mgrsDigits)?.full ?? "Outside MGRS coverage")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .accessibilityIdentifier("map-centre-grid")
                        Text(maps.preferences.gridEnabled ? "MAP CENTRE · \(intervalLabel) GRID" : "MAP CENTRE · GRID OFF")
                            .font(.caption2.weight(.semibold)).tracking(1)
                            .foregroundStyle(mapInkDim)
                        if !contourLabel.isEmpty { Text(contourLabel).font(.caption2).foregroundStyle(mapInkDim) }
                        Text((maps.preferences.offlineOnly ? "OFFLINE ONLY · " : "") + maps.layerName)
                            .font(.caption2).foregroundStyle(mapInkDim).accessibilityIdentifier("map-layer-name")
                        if overlayRoutes > 0 || overlayTracks > 0 {
                            Text("\(overlayRoutes) routes · \(overlayTracks) tracks")
                                .font(.caption2).foregroundStyle(mapInkDim).accessibilityIdentifier("map-field-overlays")
                        }
                    }
                    .padding(14).fieldChrome()
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        Button { showingGraphics = true } label: {
                            Image(systemName: "pencil.and.outline").frame(width: 44,height: 44)
                        }.fieldGlassButton().accessibilityLabel("Draw graphics and routes").accessibilityIdentifier("map-graphics")
                            .disabled(boundaryDraft != nil || graphicDraft != nil)
                        Button { showingBoundaries = true } label: {
                            Image(systemName: "shield.lefthalf.filled").frame(width: 44,height: 44)
                        }.fieldGlassButton().accessibilityLabel("Backstops and handrails").accessibilityIdentifier("map-boundaries")
                            .disabled(boundaryDraft != nil || graphicDraft != nil)
                        Button { showingLayers = true } label: {
                            Image(systemName: "square.3.layers.3d").frame(width: 44, height: 44)
                        }.fieldGlassButton().accessibilityLabel("Map layers").accessibilityIdentifier("map-layers")
                        Button { settings.nightMode.toggle() } label: {
                            Image(systemName: chromeNight ? "moon.fill" : "moon")
                                .frame(width: 44, height: 44)
                        }.fieldGlassButton().accessibilityLabel("Toggle map night mode")
                    }
                }
                Spacer(minLength: 0)
                if let draft = boundaryDraft {
                    BoundaryDrawingControls(draft: Binding(get: { boundaryDraft ?? draft },set: { boundaryDraft = $0 }),
                        centre: GeoPoint(lat: centre.latitude,lon: centre.longitude),error: boundaries.error,
                        save: { if let area = boundaryDraft?.area, boundaries.save(area) { boundaryDraft = nil } },cancel: { boundaryDraft = nil; boundaries.clearError() })
                }
                if let draft = graphicDraft {
                    GraphicDrawingControls(draft: Binding(get: { graphicDraft ?? draft },set: { graphicDraft = $0 }),
                        centre: GeoPoint(lat: centre.latitude,lon: centre.longitude),error: graphicError,
                        save: {
                            guard let draft = graphicDraft, draft.validationMessage == nil else { return }
                            do {
                                let isNew = !fieldData.document.graphics.contains { $0.id == draft.graphic.id }
                                try fieldData.saveGraphic(draft.saved); store.addFolder(draft.saved.folder)
                                graphicDraft = nil; graphicError = nil
                                if isNew && draft.graphic.type == "route" { routeWaypointOffer = draft.saved; showingRouteWaypointOffer = true }
                            }
                            catch { graphicError = error.localizedDescription }
                        },cancel: { graphicDraft = nil; graphicError = nil })
                }
                if let waypoint = selected, boundaryDraft == nil && graphicDraft == nil {
                    selectedCard(waypoint)
                }
                Text(mapAttribution)
                    .font(.system(size: 9)).foregroundStyle(chromeNight ? palette.ink : .white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.8), in: Capsule())
                    .accessibilityIdentifier("map-attribution")
                HStack(spacing: 12) {
                    Button {
                        guard let fix = location.usableFix else { return }
                        cameraRequest = MapCameraRequest(action: .locate(fix.lat, fix.lon))
                    } label: {
                        Label("Locate", systemImage: "location").frame(minHeight: 40)
                    }
                    .fieldGlassButton().disabled(location.usableFix == nil)
                    Button {
                        cameraRequest = MapCameraRequest(action: .fitData)
                    } label: {
                        Image(systemName: "viewfinder").frame(width: 44, height: 40)
                    }
                    .fieldGlassButton().disabled(visible.isEmpty && !hasFieldPoints && recorder.active?.livePoints.isEmpty != false && boundaries.displayedArea == nil)
                    .accessibilityLabel("Show all visible data")
                    RecordingButton()
                    Spacer(minLength: 0)
                    Button {
                        editorRequest = WaypointEditorRequest(lat: centre.latitude, lon: centre.longitude)
                    } label: {
                        Label("Add", systemImage: "plus").frame(minHeight: 40)
                    }
                    .fieldGlassButton().tint(palette.accent)
                    .accessibilityLabel("Add waypoint at map centre")
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
            // The edge-to-edge UIKit map extends beneath the custom field bar.
            // Reserve its control row explicitly for the overlaid map actions.
            .padding(.bottom, 16 + (chromeNight ? FieldTabBar.controlHeight : 0))
        }
        .foregroundStyle(mapInk)
        .environment(\.colorScheme, chromeNight ? .dark : .light)
        .toolbarColorScheme(chromeNight ? .dark : .light, for: .tabBar)
        .environment(\.fieldNight, chromeNight)
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
        .sheet(isPresented: $showingGraphics) {
            GraphicPanel(onDraw: { draft in
                selectedID = nil; graphicError = nil; graphicDraft = draft
                if !draft.vertices.isEmpty { cameraRequest = MapCameraRequest(action: .showBoundary(draft.graphic.mapExtentPoints)) }
            },onShow: { graphic in cameraRequest = MapCameraRequest(action: .showBoundary(graphic.mapExtentPoints)) },onNavigate: onNavigate)
        }
        .sheet(isPresented: $showingBoundaries) {
            BoundaryPanel(onDraw: { area in
                selectedID = nil; boundaries.clearError()
                boundaryDraft = area.map(BoundaryDraft.init) ?? BoundaryDraft()
                if let area { cameraRequest = MapCameraRequest(action: .showBoundary(area.vertices)) }
            },onShow: { area in boundaries.displayedID = area.id; cameraRequest = MapCameraRequest(action: .showBoundary(area.vertices)) })
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

    private func selectedCard(_ waypoint: Waypoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(waypoint.name).font(.headline)
                    Text(MGRS.parts(lat: waypoint.lat, lon: waypoint.lon, digits: settings.mgrsDigits)?.full ?? "—")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(mapInkDim)
                }
                Spacer()
                Button { selectedID = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
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

private struct MapCameraRequest {
    enum Action { case locate(Double, Double), fitData, showBounds(MapBounds), showBoundary([GeoPoint]) }
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
    let recordingPoints: [GeoPoint]
    let boundaryPoints: [GeoPoint]
    let boundaryEditing: Bool
    let boundarySelection: Int?
    let onBoundaryPoint: (GeoPoint) -> Void
    let onBoundarySelect: (Int) -> Void
    let onBoundaryInsert: (Int,GeoPoint) -> Void
    let onBoundaryMove: (Int,GeoPoint) -> Void
    let graphicDraft: Backup.Graphic?
    let graphicSelection: Int?
    let onGraphicPoint: (GeoPoint) -> Void
    let onGraphicSelect: (Int) -> Void
    let onGraphicInsert: (Int,GeoPoint) -> Void
    let onGraphicMove: (Int,GeoPoint) -> Void
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
        coordinator.boundaryPoints = boundaryPoints; coordinator.boundaryEditing = boundaryEditing
        coordinator.graphicEditing = graphicDraft != nil; coordinator.graphicSelection = graphicSelection; coordinator.graphicType = graphicDraft?.type
        coordinator.onGraphicPoint = onGraphicPoint; coordinator.onGraphicSelect = onGraphicSelect; coordinator.onGraphicMove = onGraphicMove; coordinator.onGraphicPick = onGraphicPick; coordinator.onGraphicInsert = onGraphicInsert
        coordinator.boundarySelection = boundarySelection
        // A quick pair of drawing taps must add vertices, not zoom the map.
        // Pinch/pan remain available while drawing.
        for gesture in view.gestureRecognizers ?? [] {
            if let tap = gesture as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 { tap.isEnabled = !editing }
        }
        coordinator.onBoundaryPoint = onBoundaryPoint; coordinator.onBoundarySelect = onBoundarySelect; coordinator.onBoundaryMove = onBoundaryMove; coordinator.onBoundaryInsert = onBoundaryInsert
        coordinator.boundaryOverlay.update(points: boundaryPoints,editing: boundaryEditing,selected: boundarySelection,night: nightMode,map: view)
        coordinator.graphicHandles.update(points: graphicDraft?.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) } ?? [],editing: graphicDraft != nil,selected: graphicSelection,night: nightMode,map: view,closed: graphicDraft.map { GraphicTypes.isArea($0.type) } ?? false,allowInsertion: graphicDraft.map { GraphicTypes.fixedPoints($0.type) == nil } ?? false)
        coordinator.tactical.update(document: document,folders: folders,draft: graphicDraft,night: nightMode,light: ["sat","usgs_img"].contains(mapStore.preferences.baseLayer))
        coordinator.overlay.nightMode = nightMode
        coordinator.overlay.enabled = mapStore.preferences.gridEnabled
        coordinator.overlay.lightLines = ["sat", "usgs_img"].contains(mapStore.preferences.baseLayer)
        coordinator.nightMode = nightMode
        if let style = view.style { coordinator.rasterLayers.update(style: style, store: mapStore, night: nightMode); coordinator.contours.refresh(map: view, store: mapStore, night: nightMode) }
        coordinator.fieldOverlay.onChange = onOverlays
        coordinator.fieldOverlay.update(document: document, folders: folders, night: nightMode)
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
            case let .locate(lat, lon):
                view.setCenter(CLLocationCoordinate2D(latitude: lat, longitude: lon), zoomLevel: 14, animated: true)
            case .fitData:
                let points = waypoints.map { GeoPoint(lat: $0.lat, lon: $0.lon) } + coordinator.fieldOverlay.points + recordingPoints + boundaryPoints
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
        let liveOverlay = LiveTrackOverlay()
        let rasterLayers = RasterMapLayers()
        let contours = ContourMapOverlay()
        let boundaryOverlay = BoundaryMapOverlay()
        let graphicHandles = BoundaryMapOverlay(identifier: "graphic",drawArea: false)
        let tactical = TacticalMapOverlay(frame: .zero)
        var graphicEditing = false
        var graphicType: String?
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
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
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
            for id in Array(annotations.keys) where !ids.contains(id) {
                if let old = annotations.removeValue(forKey: id) { map.removeAnnotation(old) }
            }
            for waypoint in waypoints {
                if let old = annotations[waypoint.id], old.waypoint == waypoint {
                    (map.view(for: old) as? WaypointMarkerView)?.configure(waypoint, selected: navigationID == waypoint.id, night: night)
                } else {
                    if let old = annotations.removeValue(forKey: waypoint.id) { map.removeAnnotation(old) }
                    let annotation = WaypointAnnotation(waypoint)
                    annotations[waypoint.id] = annotation
                    map.addAnnotation(annotation)
                }
            }
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
        func mapViewRegionIsChanging(_ mapView: MLNMapView) { tactical.setNeedsDisplay() }
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
