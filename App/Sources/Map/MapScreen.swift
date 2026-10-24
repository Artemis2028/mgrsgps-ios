import GridFixCore
import MapLibre
import SwiftUI

/// The current basemap is still MapLibre's demonstration style. Production
/// basemaps and offline packs are tracked separately from waypoint overlays.
struct MapScreen: View {
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var recorder: TrackRecorder
    var onNavigate: () -> Void = {}
    @State private var intervalLabel = "—"
    @State private var overlayRoutes = 0
    @State private var overlayTracks = 0
    @State private var hasFieldPoints = false
    @State private var nightMode = false
    @State private var centre = CLLocationCoordinate2D(latitude: 24.4539, longitude: 54.3773)
    @State private var selectedID: String?
    @State private var cameraRequest: MapCameraRequest?
    @State private var editorRequest: WaypointEditorRequest?

    private var chromeNight: Bool { settings.nightMode || nightMode }
    private var palette: FieldPalette { FieldPalette(night: chromeNight) }
    private var mapInk: Color { chromeNight ? palette.ink : .black }
    private var mapInkDim: Color { chromeNight ? palette.inkDim : .black.opacity(0.65) }
    private var visible: [Waypoint] {
        WaypointMapSnapshot.visible(waypoints: store.waypoints, folders: store.folders)
    }
    private var selected: Waypoint? { visible.first { $0.id == selectedID } }

    var body: some View {
        ZStack {
            MapContainer(nightMode: chromeNight, fix: location.usableFix,
                         waypoints: visible, navigationID: store.selectedId,
                         document: fieldData.document, folders: store.folders,
                         recordingPoints: recorder.active?.livePoints ?? [],
                         onOverlays: { overlayRoutes = $0; overlayTracks = $1; hasFieldPoints = $2 },
                         cameraRequest: cameraRequest,
                         onSelect: { selectedID = $0 },
                         onChange: { label, position in
                             intervalLabel = label
                             centre = position
                         })
                .ignoresSafeArea()
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .light)).foregroundStyle(palette.accent)
                .shadow(color: .black, radius: 2).allowsHitTesting(false).accessibilityHidden(true)
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(MGRS.parts(lat: centre.latitude, lon: centre.longitude,
                                        digits: settings.mgrsDigits)?.full ?? "Outside MGRS coverage")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .accessibilityIdentifier("map-centre-grid")
                        Text("MAP CENTRE · \(intervalLabel) GRID")
                            .font(.caption2.weight(.semibold)).tracking(1)
                            .foregroundStyle(mapInkDim)
                        if overlayRoutes > 0 || overlayTracks > 0 {
                            Text("\(overlayRoutes) routes · \(overlayTracks) tracks")
                                .font(.caption2).foregroundStyle(mapInkDim).accessibilityIdentifier("map-field-overlays")
                        }
                    }
                    .padding(14).fieldChrome()
                    Spacer(minLength: 0)
                    Button { nightMode.toggle() } label: {
                        Image(systemName: chromeNight ? "moon.fill" : "moon")
                            .frame(width: 44, height: 44)
                    }.fieldGlassButton().accessibilityLabel("Toggle map night mode")
                }
                Spacer(minLength: 0)
                if let waypoint = selected {
                    selectedCard(waypoint)
                }
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
                    .fieldGlassButton().disabled(visible.isEmpty && !hasFieldPoints && recorder.active?.livePoints.isEmpty != false)
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
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        }
        .foregroundStyle(mapInk)
        .environment(\.colorScheme, chromeNight ? .dark : .light)
        .toolbarColorScheme(chromeNight ? .dark : .light, for: .tabBar)
        .environment(\.fieldNight, chromeNight)
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
    enum Action { case locate(Double, Double), fitData }
    let id = UUID()
    let action: Action
}

private struct MapContainer: UIViewRepresentable {
    let nightMode: Bool
    let fix: Fix?
    let waypoints: [Waypoint]
    let navigationID: String?
    let document: Backup.Document
    let folders: [FolderInfo]
    let recordingPoints: [GeoPoint]
    let onOverlays: (Int, Int, Bool) -> Void
    let cameraRequest: MapCameraRequest?
    let onSelect: (String) -> Void
    let onChange: (String, CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero)
        view.delegate = context.coordinator
        view.styleURL = URL(string: "https://demotiles.maplibre.org/style.json")
        view.logoViewPosition = .bottomLeft
        view.logoViewMargins = CGPoint(x: 12, y: 150)
        view.attributionButtonPosition = .bottomLeft
        view.attributionButtonMargins = CGPoint(x: 118, y: 150)
        view.showsUserLocation = true
        view.setCenter(CLLocationCoordinate2D(latitude: 24.4539, longitude: 54.3773), zoomLevel: 13, animated: false)
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        coordinator.onSelect = onSelect
        coordinator.overlay.nightMode = nightMode
        coordinator.fieldOverlay.onChange = onOverlays
        coordinator.fieldOverlay.update(document: document, folders: folders, night: nightMode)
        coordinator.liveOverlay.update(recordingPoints)
        coordinator.sync(waypoints, navigationID: navigationID, night: nightMode, in: view)
        if let request = cameraRequest, coordinator.lastRequest != request.id {
            coordinator.lastRequest = request.id
            switch request.action {
            case let .locate(lat, lon):
                view.setCenter(CLLocationCoordinate2D(latitude: lat, longitude: lon), zoomLevel: 14, animated: true)
            case .fitData:
                let points = waypoints.map { GeoPoint(lat: $0.lat, lon: $0.lon) } + coordinator.fieldOverlay.points + recordingPoints
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
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        let overlay = GridOverlay()
        let fieldOverlay = FieldOverlay()
        let liveOverlay = LiveTrackOverlay()
        var hasCentred = false
        var lastRequest: UUID?
        var annotations: [String: WaypointAnnotation] = [:]
        var onSelect: ((String) -> Void)?
        var onChange: ((String, CLLocationCoordinate2D) -> Void)?
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
            guard let annotation = annotation as? WaypointAnnotation else { return nil }
            let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: "waypoint") as? WaypointMarkerView)
                ?? WaypointMarkerView(reuseIdentifier: "waypoint")
            marker.configure(annotation.waypoint, selected: navigationID == annotation.waypoint.id, night: night)
            return marker
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let annotation = annotation as? WaypointAnnotation else { return }
            onSelect?(annotation.waypoint.id)
            // Deselect immediately so the same marker can reopen a dismissed card.
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            overlay.install(into: style)
            fieldOverlay.install(into: style)
            liveOverlay.install(into: style)
            redraw(mapView)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) { redraw(mapView) }

        private func redraw(_ map: MLNMapView) {
            if let style = map.style, !overlay.isInstalled { overlay.install(into: style) }
            overlay.refresh(bounds: map.visibleCoordinateBounds,
                            metersPerPoint: map.metersPerPoint(atLatitude: map.centerCoordinate.latitude),
                            viewSize: map.bounds.size, safeArea: map.safeAreaInsets)
            // MapLibre may call during updateUIView; publish on the next main turn.
            let label = overlay.intervalLabel, centre = map.centerCoordinate
            DispatchQueue.main.async { [weak self] in self?.onChange?(label, centre) }
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
        frame = CGRect(x: 0, y: 0, width: 130, height: 62)
        centerOffset = CGVector(dx: 0, dy: -17)
        nameLabel.frame = CGRect(x: 0, y: 0, width: 130, height: 26)
        nameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        nameLabel.textAlignment = .center
        nameLabel.backgroundColor = .black
        nameLabel.layer.cornerRadius = 7
        nameLabel.clipsToBounds = true
        dot.frame = CGRect(x: 49, y: 30, width: 32, height: 32)
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
        dot.image = UIImage(systemName: style.symbolName)
        dot.layer.cornerRadius = 16
        dot.layer.borderWidth = selected ? 2 : 0
        dot.layer.borderColor = (night ? UIColor.systemRed : .white).cgColor
        character.text = style.character
        accessibilityLabel = "Waypoint \(waypoint.name)"
        accessibilityIdentifier = "map-waypoint-\(waypoint.id)"
        accessibilityValue = selected ? "Navigation target" : ""
    }
}
