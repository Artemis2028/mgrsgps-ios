import GridFixCore
import SwiftUI

/// Each presentation owns an immutable payload, rather than reading several
/// parent @State values while SwiftUI is creating the sheet.
struct WaypointEditorRequest: Identifiable {
    let id = UUID()
    var waypoint: Waypoint?
    var lat: Double?
    var lon: Double?
}

struct WaypointEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @EnvironmentObject private var location: LocationService
    private let waypoint: Waypoint?
    private let onSave: (WaypointDraft) -> Void
    @State private var name: String
    @State private var folder: String
    @State private var coordinate: WaypointCoordinateDraft
    private var palette: FieldPalette { FieldPalette(night: night) }
    private var rowBackground: Color { night ? .black : Color(uiColor: .secondarySystemGroupedBackground) }

    init(waypoint: Waypoint? = nil, lat: Double? = nil, lon: Double? = nil,
         onSave: @escaping (WaypointDraft) -> Void) {
        self.waypoint = waypoint
        self.onSave = onSave
        _name = State(initialValue: waypoint?.name ?? "")
        _folder = State(initialValue: waypoint?.folder ?? Folders.defaultFolder)
        _coordinate = State(initialValue: WaypointCoordinateDraft(lat: waypoint?.lat ?? lat, lon: waypoint?.lon ?? lon))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Waypoint") {
                    TextField("Name", text: $name).accessibilityIdentifier("waypoint-name")
                    TextField("Folder", text: $folder).accessibilityIdentifier("waypoint-folder")
                    if let hint = Folders.reservedHint(folder) {
                        Text(hint).font(.footnote).foregroundStyle(palette.warn)
                    }
                }
                .listRowBackground(rowBackground)
                Section {
                    Picker("Coordinate format", selection: Binding(
                        get: { coordinate.format },
                        set: { coordinate.changeFormat(to: $0) }
                    )) {
                        ForEach(WaypointCoordinateDraft.Format.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    if coordinate.format == .mgrs {
                        TextField("40R BN 34125 07001", text: $coordinate.grid)
                            .textInputAutocapitalization(.characters)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityLabel("MGRS coordinate")
                            .accessibilityIdentifier("waypoint-mgrs")
                    } else {
                        LabeledContent("Latitude") {
                            TextField("−90 … 90", text: $coordinate.latitude)
                                .accessibilityIdentifier("waypoint-latitude")
                                .accessibilityLabel("Latitude")
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Longitude") {
                            TextField("−180 … 180", text: $coordinate.longitude)
                                .accessibilityIdentifier("waypoint-longitude")
                                .accessibilityLabel("Longitude")
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Button {
                        guard let fix = location.usableFix else { return }
                        coordinate = WaypointCoordinateDraft(lat: fix.lat, lon: fix.lon)
                    } label: {
                        Label("Use current position", systemImage: "location")
                    }
                    .disabled(location.usableFix == nil)
                } header: {
                    Text("Position · WGS84")
                } footer: {
                    if let message = coordinate.validationMessage {
                        Text(message).foregroundStyle(palette.warn)
                    } else if coordinate.format == .mgrs {
                        Text("A typed grid resolves to the centre of its cell. An unchanged recorded position keeps its original precision.")
                    }
                }
                .listRowBackground(rowBackground)
                if let p = coordinate.position {
                    Section("Coordinate preview") {
                        Text(MGRS.parts(lat: p.lat, lon: p.lon, digits: 10)?.full ?? "Outside MGRS coverage")
                            .font(.system(.body, design: .monospaced))
                        Text(Format.latLon(lat: p.lat, lon: p.lon, format: .decimalDegrees))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(palette.inkDim)
                    }
                    .listRowBackground(rowBackground)
                }
            }
            .autocorrectionDisabled()
            .foregroundStyle(palette.ink)
            .scrollContentBackground(.hidden)
            .background { FieldScreenBackground() }
            .navigationTitle(waypoint == nil ? "New waypoint" : "Edit waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinate.position == nil)
                        .accessibilityIdentifier("waypoint-save")
                }
            }
            .tint(palette.accent)
        }
    }

    private func save() {
        guard let position = coordinate.position else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(WaypointDraft(name: trimmed, lat: position.lat, lon: position.lon, folder: folder,
                             symbol: waypoint?.symbol ?? DEFAULT_SYMBOL,
                             affiliation: waypoint?.affiliation ?? "none", echelon: waypoint?.echelon ?? "",
                             designation: waypoint?.designation ?? "", kind: waypoint?.kind ?? KIND_WP,
                             rotation: waypoint?.rotation ?? 0, metadata: waypoint?.metadata))
        dismiss()
    }
}
