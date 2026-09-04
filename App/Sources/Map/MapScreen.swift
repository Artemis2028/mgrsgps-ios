import GridFixCore
import MapLibre
import SwiftUI

/// The map, with the MGRS grid on it.
///
/// The basemap here is MapLibre's keyless demo style — enough to prove the
/// grid draws and to make a CI screenshot worth looking at. It is a low-detail
/// world map and is **not** the shipping basemap; roadmap B replaces it with
/// self-hosted OpenStreetMap vector tiles plus our own terrain, which is also
/// what makes worldwide offline download possible.
struct MapScreen: View {
    @EnvironmentObject private var location: LocationService
    @State private var intervalLabel = "—"
    @State private var nightMode = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapContainer(nightMode: nightMode,
                         follow: location.fix,
                         onChange: { label, _ in intervalLabel = label })
                .ignoresSafeArea()

            // Bottom right and square, the way Rafael asked for it on Android:
            // the top left is vital real estate when the vertical dimension is
            // short, and this readout only needs to be glanceable.
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    nightMode.toggle()
                } label: {
                    Text(nightMode ? "NIGHT" : "DAY")
                        .font(Blackout.label(10))
                        .tracking(1.2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.72))
                        .foregroundStyle(nightMode ? Blackout.night : Blackout.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        Text("GRID")
                            .font(Blackout.label(9))
                            .tracking(1.4)
                            .foregroundStyle(Blackout.inkDim)
                        Text(intervalLabel)
                            .font(Blackout.numerals(15, weight: .semibold))
                            .foregroundStyle(nightMode ? Blackout.night : Blackout.ink)
                    }
                    .frame(width: 62, height: 46)
                    .background(Color.black.opacity(0.72))
                    .overlay(Rectangle().stroke(Blackout.hairline))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Blackout.background)
        .ignoresSafeArea()
    }
}

private struct MapContainer: UIViewRepresentable {
    let nightMode: Bool
    let follow: Fix?
    let onChange: (String, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero)
        // Delegate first. Setting styleURL can complete before a delegate
        // assigned afterwards is in place, and a missed didFinishLoading means
        // the overlay is never installed while everything else looks fine.
        view.delegate = context.coordinator
        view.styleURL = URL(string: "https://demotiles.maplibre.org/style.json")
        // Attribution is a licence obligation, not decoration, and has to stay
        // visible AND tappable. MapLibre's default puts the (i) button
        // bottom-right, which is where the grid chip lives — Rafael's call on
        // Android, because top-left is vital real estate on a short screen. So
        // the button moves left beside the logo, the arrangement MapLibre uses
        // on Android anyway, and both sit clear of the floating tab bar.
        //
        // This stops being cosmetic once roadmap B serves our own
        // OpenStreetMap tiles: ODbL requires the credit, and a chip covering
        // half of it is then a licence problem.
        view.logoView.isHidden = false
        view.logoViewPosition = .bottomLeft
        view.logoViewMargins = CGPoint(x: 8, y: 86)
        view.attributionButtonPosition = .bottomLeft
        view.attributionButtonMargins = CGPoint(x: 148, y: 86)
        view.showsUserLocation = true
        view.setCenter(CLLocationCoordinate2D(latitude: 24.4539, longitude: 54.3773),
                       zoomLevel: 13, animated: false)
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        context.coordinator.overlay.nightMode = nightMode
        if let f = follow, !context.coordinator.hasCentred {
            context.coordinator.hasCentred = true
            view.setCenter(CLLocationCoordinate2D(latitude: f.lat, longitude: f.lon),
                           zoomLevel: 14, animated: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        let overlay = GridOverlay()
        var hasCentred = false

        init(onChange: @escaping (String, Int) -> Void) {
            super.init()
            overlay.onChange = onChange
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            overlay.install(into: style)
            redraw(mapView)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            redraw(mapView)
        }

        private func redraw(_ mapView: MLNMapView) {
            // Belt and braces: install here too, in case the camera moved
            // before didFinishLoading arrived.
            if let style = mapView.style, !overlay.isInstalled {
                overlay.install(into: style)
            }
            let bounds = mapView.visibleCoordinateBounds
            let metersPerPoint = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
            overlay.refresh(bounds: bounds, metersPerPoint: metersPerPoint)
        }
    }
}
