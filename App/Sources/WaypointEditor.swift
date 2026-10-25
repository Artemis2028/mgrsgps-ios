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
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var waypoints: WaypointStore
    private let waypoint: Waypoint?
    private let onSave: (WaypointDraft) -> Void
    private enum InputField: Hashable { case name, folder, grid, latitude, longitude, designation, azimuth, distance }
    @FocusState private var focusedInput: InputField?
    @State private var name: String
    @State private var folder: String
    @State private var coordinate: WaypointCoordinateDraft
    @State private var symbol: String
    @State private var affiliation: String
    @State private var echelon: String
    @State private var designation: String
    @State private var kind: String
    @State private var rotation: Double
    @State private var markerMetadata: WaypointMetadata?
    @State private var projecting = false
    @State private var projectionBases: [ProjectionBase] = []
    @State private var projectionBaseID = ""
    @State private var projectionAzimuth = ""
    @State private var projectionDistance = ""
    @State private var projectionDate = Date()
    private struct ProjectionBase: Identifiable { let id: String; let name: String; let point: GeoPoint }
    private struct ProjectionPreview { var result: WaypointProjection.Result?; var error: String?; var reading: DeclinationReading? }
    private var secondaryInk: Color { night ? palette.ink : palette.inkDim }
    private var selectedPosition: GeoPoint? {
        projecting ? projectionPreview.result?.point : coordinate.position.map { .init(lat: $0.lat,lon: $0.lon) }
    }
    private var projectionPreview: ProjectionPreview {
        guard let base = projectionBases.first(where: { $0.id == projectionBaseID }) else { return .init(error: "Choose a base point.") }
        var reading: DeclinationReading?
        do {
            let result = try WaypointProjection.project(base: base.point,azimuth: projectionAzimuth,distance: projectionDistance,
                                                        angleUnit: settings.angleUnit,northReference: settings.northRef.rawValue) { point in
                let value = DeclinationService(overrideDegrees: settings.declinationOverride).declination(lat: point.lat,lon: point.lon,date: projectionDate,isCurrentPosition: false)
                reading = value; return value.degreesEast
            }
            return .init(result: result,reading: reading)
        } catch { return .init(error: projectionAzimuth.isEmpty && projectionDistance.isEmpty ? nil : error.localizedDescription) }
    }
    private var palette: FieldPalette { FieldPalette(night: night) }
    private var rowBackground: Color { night ? .black : Color(uiColor: .secondarySystemGroupedBackground) }

    init(waypoint: Waypoint? = nil, lat: Double? = nil, lon: Double? = nil,
         onSave: @escaping (WaypointDraft) -> Void) {
        self.waypoint = waypoint
        self.onSave = onSave
        _name = State(initialValue: waypoint?.name ?? "")
        _folder = State(initialValue: waypoint?.folder ?? Folders.defaultFolder)
        _symbol = State(initialValue: waypoint?.symbol ?? DEFAULT_SYMBOL)
        _affiliation = State(initialValue: waypoint?.affiliation ?? "none")
        _echelon = State(initialValue: waypoint?.echelon ?? "")
        _designation = State(initialValue: waypoint?.designation ?? "")
        _kind = State(initialValue: waypoint?.kind ?? KIND_WP)
        _rotation = State(initialValue: waypoint?.rotation ?? 0)
        _markerMetadata = State(initialValue: waypoint?.metadata)
        _coordinate = State(initialValue: WaypointCoordinateDraft(lat: waypoint?.lat ?? lat, lon: waypoint?.lon ?? lon))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Waypoint") {
                    TextField("Name", text: $name, prompt: Text("Name").foregroundColor(secondaryInk)).focused($focusedInput,equals: .name).accessibilityIdentifier("waypoint-name")
                    TextField("Folder", text: $folder, prompt: Text("Folder").foregroundColor(secondaryInk)).focused($focusedInput,equals: .folder).accessibilityIdentifier("waypoint-folder")
                    if let hint = Folders.reservedHint(folder) {
                        Text(hint).font(.footnote).foregroundStyle(palette.warn)
                    }
                }
                .listRowBackground(rowBackground)
                Section {
                    Picker("Position method",selection: Binding(get: { projecting },set: { value in
                        focusedInput = nil
                        if value { beginProjection() } else { projecting = false }
                    })) { Text("Coordinate").tag(false); Text("Project").tag(true) }
                        .pickerStyle(.segmented).accessibilityIdentifier("waypoint-position-method")
                    if projecting { projectionFields } else {
                        Picker("Coordinate format", selection: Binding(
                            get: { coordinate.format },
                            set: { coordinate.changeFormat(to: $0) }
                        )) {
                            ForEach(WaypointCoordinateDraft.Format.allCases, id: \.self) { format in
                                Text(format == .mgrs ? settings.gridName : format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        if coordinate.format == .mgrs {
                            TextField("40R BN 34125 07001", text: $coordinate.grid, prompt: Text("40R BN 34125 07001").foregroundColor(secondaryInk)).focused($focusedInput,equals: .grid)
                                .textInputAutocapitalization(.characters)
                                .font(.system(.body, design: .monospaced))
                                .accessibilityLabel("\(settings.gridName) coordinate")
                                .accessibilityIdentifier("waypoint-mgrs")
                        } else {
                            LabeledContent("Latitude") {
                                TextField("−90 … 90", text: $coordinate.latitude, prompt: Text("−90 … 90").foregroundColor(secondaryInk)).focused($focusedInput,equals: .latitude)
                                    .accessibilityIdentifier("waypoint-latitude")
                                    .accessibilityLabel("Latitude")
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                            }
                            LabeledContent("Longitude") {
                                TextField("−180 … 180", text: $coordinate.longitude, prompt: Text("−180 … 180").foregroundColor(secondaryInk)).focused($focusedInput,equals: .longitude)
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
                    }
                } header: {
                    Text("Position · WGS84")
                } footer: {
                    if projecting {
                        Text("Distance is in metres, up to 200 km. Base coordinates are captured when Project is selected. Saving uses the projected coordinate.").foregroundStyle(secondaryInk)
                    } else if let message = coordinate.validationMessage {
                        Text(message).foregroundStyle(palette.warn)
                    } else if coordinate.format == .mgrs {
                        Text("A typed grid resolves to the centre of its cell. An unchanged recorded position keeps its original precision.")
                    }
                }
                .listRowBackground(rowBackground)
                if let p = selectedPosition {
                    Section("Coordinate preview") {
                        Text(MGRS.parts(lat: p.lat, lon: p.lon, digits: 10)?.full ?? "Outside \(settings.gridName) coverage")
                            .font(.system(.body, design: .monospaced)).accessibilityIdentifier("waypoint-coordinate-preview")
                        Text(Format.latLon(lat: p.lat, lon: p.lon, format: .decimalDegrees))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(secondaryInk)
                    }
                    .listRowBackground(rowBackground)
                }
                Section("Symbol & unit") {
                    NavigationLink {
                        MilitarySymbolPicker(symbol: $symbol,affiliation: $affiliation)
                    } label: {
                        HStack {
                            MilitaryMarker(symbol: symbol,affiliation: affiliation,echelon: echelon,rotation: rotation,metadata: markerMetadata ?? .init()).frame(width: 48,height: 48)
                            Text(MilitarySymbols.label(symbol)); Spacer()
                        }
                    }.accessibilityIdentifier("choose-military-symbol")
                        .simultaneousGesture(TapGesture().onEnded { focusedInput = nil })
                    Picker("Record type",selection: $kind) { Text("Waypoint").tag(KIND_WP); Text("Unit").tag(KIND_UNIT) }
                        .onChange(of: kind) { value in
                            if value == KIND_UNIT && !symbol.hasPrefix("nato_") { symbol = "nato_f_unit"; if affiliation == "none" { affiliation = "friendly" } }
                            else if value == KIND_WP && symbol.hasPrefix("nato_") { symbol = "flag" }
                        }
                    Picker("Affiliation",selection: $affiliation) { ForEach(MilitarySymbols.affiliations) { Text($0.label).tag($0.key) } }
                        .onChange(of: affiliation) { value in
                            if let function = MilitarySymbols.function(symbol), value != "none" { symbol = "nato_\(MilitarySymbols.affiliationCode(value))_\(function)" }
                        }
                    Picker("Echelon",selection: $echelon) { ForEach(MilitarySymbols.echelons) { Text($0.label).tag($0.key) } }.accessibilityIdentifier("unit-echelon")
                    TextField("Unit designation",text: $designation,prompt: Text("Unit designation").foregroundColor(secondaryInk)).focused($focusedInput,equals: .designation).accessibilityIdentifier("unit-designation")
                    if symbol.hasPrefix("task_") { Slider(value: $rotation,in: 0...360,step: 5); Text("Task rotation: \(Int(rotation))°") }
                    if markerMetadata?.color != nil || markerMetadata?.milgpsSymbolCode != nil {
                        ImportedMarkerEditor(metadata: Binding(get: { markerMetadata ?? .init() },set: { markerMetadata = $0 }))
                    }
                    if let elevation = markerMetadata?.elevationMeters { Text("Elevation: \(elevation, specifier: "%.1f") m").font(.caption) }
                }.listRowBackground(rowBackground)
            }
            .autocorrectionDisabled()
            .onSubmit { focusedInput = nil }
            .foregroundStyle(palette.ink)
            .scrollContentBackground(.hidden)
            .background { FieldScreenBackground() }
            .navigationTitle(waypoint == nil ? "New waypoint" : "Edit waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedInput = nil }.accessibilityIdentifier("waypoint-keyboard-done") }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedPosition == nil)
                        .accessibilityIdentifier("waypoint-save")
                }
            }
            .tint(palette.accent)
        }.fieldSheetAppearance()
        .onChange(of: symbol) { value in
            focusedInput = nil
            if markerMetadata != nil { markerMetadata?.color = nil; markerMetadata?.milgpsSymbolCode = nil }
            kind = value.hasPrefix("nato_") ? KIND_UNIT : KIND_WP
        }
    }

    private var projectionFields: some View {
        let preview = projectionPreview
        return Group {
            Menu {
                ForEach(projectionBases) { base in
                    Button(base.name) { focusedInput = nil; projectionBaseID = base.id }.accessibilityIdentifier("projection-base-"+base.name)
                }
            } label: {
                HStack { Text("From: "+(projectionBases.first { $0.id == projectionBaseID }?.name ?? "Choose base")); Spacer(); Image(systemName: "chevron.up.chevron.down") }
            }.accessibilityIdentifier("projection-base")
            LabeledContent("Azimuth (\(settings.angleUnit == .mils ? "mils" : "degrees") \(settings.northRef.letter))") {
                TextField("0",text: $projectionAzimuth).keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing).focused($focusedInput,equals: .azimuth).accessibilityIdentifier("projection-azimuth")
            }
            LabeledContent("Distance (m)") {
                TextField("0",text: $projectionDistance).keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing).focused($focusedInput,equals: .distance).accessibilityIdentifier("projection-distance")
            }
            Text("\(settings.northRef.title) north · \(settings.angleUnit == .mils ? "NATO mils" : "degrees")").font(.caption).foregroundStyle(secondaryInk)
            if let reading = preview.reading {
                Text("Magnetic: "+reading.display+" · "+reading.source.rawValue).font(.caption).foregroundStyle(secondaryInk)
                if reading.modelExpired { Text("The magnetic model is past its validity period; this bearing uses an extrapolation.").font(.footnote).foregroundStyle(palette.warn) }
            }
            if let error = preview.error { Text(error).foregroundStyle(palette.warn).accessibilityIdentifier("projection-error") }
            else if preview.result == nil { Text("Enter azimuth and distance from the base point.").foregroundStyle(secondaryInk) }
        }
    }
    private func beginProjection() {
        var bases: [ProjectionBase] = []
        if let point = coordinate.position { bases.append(.init(id: "entered",name: "Entered position",point: .init(lat: point.lat,lon: point.lon))) }
        if let fix = location.usableFix { bases.append(.init(id: "me",name: "My position",point: .init(lat: fix.lat,lon: fix.lon))) }
        bases += waypoints.waypoints.map { .init(id: "wp:"+$0.id,name: $0.name,point: .init(lat: $0.lat,lon: $0.lon)) }
        projectionBases = bases
        if !bases.contains(where: { $0.id == projectionBaseID }) { projectionBaseID = bases.first?.id ?? "" }
        projectionDate = Date(); projecting = true
    }
    private func save() {
        guard let position = selectedPosition else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(WaypointDraft(name: trimmed, lat: position.lat, lon: position.lon, folder: folder,
                             symbol: symbol, affiliation: affiliation, echelon: echelon,
                             designation: designation, kind: kind, rotation: rotation, metadata: markerMetadata))
        dismiss()
    }
}
