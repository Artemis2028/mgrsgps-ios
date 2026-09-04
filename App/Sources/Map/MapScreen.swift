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
    @State private var lineCount = 0
    @State private var nightMode = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapContainer(nightMode: nightMode,
                         follow: location.fix,
                         onChange: { intervalLabel = $0; lineCount = $1 })
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
                        #if DEBUG
                        // Temporary: distinguishes "the geometry produced
                        // nothing" from "the geometry was right and the
                        // renderer never got it". A screenshot cannot.
                        Text("\(lineCount) ln")
                            .font(Blackout.numerals(9))
                            .foregroundStyle(Blackout.inkDim)
                        #endif
                    }
                    .frame(width: 62, height: 58)
                    .background(Color.black.opacity(0.72))
                    .overlay(Rectangle().stroke(Blackout.hairline))
                }
            }
            .padding(12)
        }
        .background(Blackout.background)
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
        view.logoView.isHidden = false          // attribution stays visible
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
