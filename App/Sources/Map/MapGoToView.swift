import GridFixCore
import SwiftUI

/// Reuses the waypoint coordinate parser without creating a waypoint or guide.
struct MapGoToView: View {
    let show: (GeoPoint) -> Void
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var coordinate = WaypointCoordinateDraft()
    @FocusState private var focused: Bool
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    init(centre: GeoPoint,show: @escaping (GeoPoint) -> Void) {
        self.show = show
        var draft = WaypointCoordinateDraft()
        if let parts = MGRS.parts(lat: centre.lat,lon: centre.lon,digits: 10) { draft.grid = parts.gzd + " " + parts.square + " " }
        _coordinate = State(initialValue: draft)
    }
    private var mapPosition: WaypointCoordinateDraft.Position? {
        guard let point = coordinate.position,abs(point.lat) <= 85.05112878 else { return nil }
        return point
    }
    private var validationMessage: String? {
        coordinate.validationMessage ?? (mapPosition == nil ? "Map coverage ends at 85.05° north and south. Choose a position within that range." : nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Coordinate format",selection: Binding(get: { coordinate.format },set: { coordinate.changeFormat(to: $0) })) {
                        Text(settings.gridName).tag(WaypointCoordinateDraft.Format.mgrs)
                        Text("Lat / Lon").tag(WaypointCoordinateDraft.Format.decimal)
                    }.pickerStyle(.segmented).accessibilityIdentifier("map-goto-format")
                    if coordinate.format == .mgrs {
                        Text(settings.gridName + " grid").font(.caption)
                        TextField("Zone, square, easting and northing",text: $coordinate.grid).textInputAutocapitalization(.characters).autocorrectionDisabled().focused($focused).accessibilityIdentifier("map-goto-grid")
                    } else {
                        Text("Latitude").font(.caption)
                        TextField("Latitude",text: $coordinate.latitude).keyboardType(.numbersAndPunctuation).focused($focused).accessibilityIdentifier("map-goto-latitude")
                        Text("Longitude").font(.caption)
                        TextField("Longitude",text: $coordinate.longitude).keyboardType(.numbersAndPunctuation).focused($focused).accessibilityIdentifier("map-goto-longitude")
                    }
                    if let message = validationMessage { Text(message).font(.footnote).foregroundStyle(palette.inkDim) }
                }.listRowBackground(settings.nightMode ? Color.black : Color(white: 0.12))
                Button("Show on map") {
                    guard let point = mapPosition else { return }
                    focused = false; show(.init(lat: point.lat,lon: point.lon)); dismiss()
                }.disabled(mapPosition == nil).frame(minHeight: 44).accessibilityIdentifier("map-goto-show")
                    .listRowBackground(settings.nightMode ? Color.black : Color(white: 0.12))
            }.foregroundStyle(palette.ink).scrollContentBackground(.hidden).background(palette.background)
                .navigationTitle("Go to").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false }.accessibilityIdentifier("map-goto-keyboard-done") }
                }
        }.tint(palette.accent).fieldSheetAppearance()
    }
}
