import GridFixCore
import SwiftUI

struct GraphicPanel: View {
    @EnvironmentObject private var field: FieldDataStore
    @EnvironmentObject private var waypoints: WaypointStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @StateObject private var mutation = FieldMutation()
    @State private var deleting: Backup.Graphic?
    var onDraw: (GraphicDraft) -> Void
    var onShow: (Backup.Graphic) -> Void
    var onNavigate: () -> Void = {}
    private var palette: FieldPalette { .init(night: night) }
    var body: some View {
        NavigationStack {
            List {
                Section("Draw on map") {
                    NavigationLink("Choose graphic type") {
                        List(GraphicTypes.all, id: \.key) { type in
                            Button(type.label) { dismiss(); onDraw(GraphicDraft(type: type.key)) }
                                .accessibilityIdentifier("draw-graphic-\(type.key)")
                        }.navigationTitle("Graphic type").fieldSheetAppearance()
                    }.accessibilityIdentifier("choose-graphic-type")
                    Text("Draw straight segments, then hold and drag a point or line to reshape it. The + handles also add points. Tactical boundaries and security lines do not trigger alerts; use Backstops & handrails for quiet-inside crossing monitoring.").font(.footnote)
                }
                Section("Saved graphics & routes") {
                    if field.document.graphics.isEmpty { Text("No graphics saved") }
                    ForEach(field.document.graphics) { graphic in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(graphic.name).font(.headline)
                            Text("\(GraphicTypes.label(graphic.type)) · \(graphic.points.count) points · \(graphic.folder)").font(.caption).foregroundStyle(palette.inkDim)
                            if graphic.type == "route" {
                                NavigationLink("Route card & navigation") {
                                    RouteDetailView(routeID: graphic.id,onNavigate: { dismiss(); onNavigate() })
                                }.accessibilityIdentifier("graphic-route-card-\(graphic.name)")
                            }
                            Toggle("Visible on map", isOn: Binding(get: { field.document.graphics.first { $0.id == graphic.id }?.visible ?? false }, set: { value in
                                mutation.run("Saving visibility…",action: { try await FieldEditAction.apply(.setGraphicVisible(graphic.id,value),to: field) })
                            })).accessibilityIdentifier("graphic-visible-\(graphic.name)")
                            HStack {
                                Button("Show") { onShow(graphic); dismiss() }.accessibilityIdentifier("show-graphic-\(graphic.name)")
                                Button("Edit") { dismiss(); onDraw(GraphicDraft(graphic)) }.accessibilityIdentifier("edit-graphic-\(graphic.name)")
                                Spacer()
                                Button(role: .destructive) { deleting = graphic } label: { Image(systemName: "trash") }.accessibilityLabel("Delete graphic \(graphic.name)")
                            }.buttonStyle(.borderless)
                        }.padding(.vertical, 4)
                    }
                }
                if let label = mutation.label { ProgressView(label).tint(palette.accent) }
                if let error = mutation.error { Text(error).foregroundStyle(palette.warn) }
            }.disabled(mutation.working).scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .foregroundStyle(palette.ink).tint(palette.accent)
                .navigationTitle("Graphics & routes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(mutation.working) } }
                .alert("Delete graphic?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete", role: .destructive) { if let deleting { mutation.run("Deleting graphic…",action: { try await FieldEditAction.apply(.deleteGraphic(deleting.id),to: field) }) }; deleting = nil }
                    Button("Keep", role: .cancel) { deleting = nil }
                }
        }.fieldSheetAppearance().interactiveDismissDisabled(mutation.working)
            .onAppear { mutation.setPresented(true) }.onDisappear { mutation.setPresented(false) }
    }
}

struct GraphicDrawingControls: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var compact: Bool { verticalSizeClass == .compact && !dynamicType.isAccessibilitySize }
    private var row: AnyLayout { dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout()) }
    @Binding var draft: GraphicDraft
    @Binding var measuringArea: Bool
    let centre: GeoPoint
    let error: String?
    var saving = false
    var save: () -> Void
    var cancel: () -> Void
    @State private var properties = false
    @State private var measureResults = false
    @State private var convertMeasurement = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.fieldNight) private var night
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                HStack(alignment: .center,spacing: 16) {
                    VStack(alignment: .leading,spacing: 6) {
                        editorHeader
                        if measuringArea { MapAreaSummary(vertices: draft.vertices,compact: true) }
                    }
                    pointActions
                }
            } else {
                editorHeader
            }
            if measuringArea && !compact { MapAreaSummary(vertices: draft.vertices,compact: true) }
            if !compact { Text(GraphicTypes.placementHint(draft.graphic.type)).font(.caption) }
            if !compact { pointActions }
            if !compact { Text("\(draft.graphic.points.count) points · \(draft.selected.map { "point \($0 + 1) selected" } ?? "no selection")")
                .font(.caption).accessibilityIdentifier("graphic-point-count")
            }
            if !compact && !measuringArea, let i = draft.selected, draft.graphic.points.indices.contains(i) {
                Text(String(format: "%.6f, %.6f", draft.graphic.points[i].lat, draft.graphic.points[i].lon)).font(.system(.caption, design: .monospaced)).accessibilityIdentifier("graphic-selected-coordinate")
            }
            if saving { ProgressView("Saving graphic…") }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.disabled(saving).padding(compact ? 8 : 12).fieldChrome()
            .sheet(isPresented: $measureResults,onDismiss: {
                if convertMeasurement { convertMeasurement = false; properties = true }
            }) {
                NavigationStack {
                    Form {
                        MapAreaSummary(vertices: draft.vertices,identifierPrefix: "measurement-result")
                        Button("Save as area") { convertMeasurement = true; measuringArea = false; measureResults = false }.disabled(MapMeasurement.polygon(draft.vertices) == nil).accessibilityIdentifier("measurement-save-area")
                        Button("Keep measuring") { measureResults = false }
                        Button("Done",action: cancel)
                    }.scrollContentBackground(.hidden).background { FieldScreenBackground() }
                        .foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent)
                        .navigationTitle("Area measurement").navigationBarTitleDisplayMode(.inline)
                }.fieldSheetAppearance()
            }
            .onChange(of: draft.graphic.points.count) { count in
                if count == GraphicTypes.fixedPoints(draft.graphic.type) { properties = true }
            }
            .sheet(isPresented: $properties) {
                NavigationStack {
                    Form {
                        TextField("Name (optional)", text: $draft.graphic.name).accessibilityIdentifier("graphic-name")
                        TextField("Folder", text: $draft.graphic.folder).accessibilityIdentifier("graphic-folder")
                        Picker("Affiliation", selection: $draft.graphic.affiliation) { ForEach(MilitarySymbols.affiliations) { Text($0.label).tag($0.key) } }
                        if draft.graphic.type == "boundary" { Picker("Echelon", selection: $draft.graphic.echelon) { ForEach(MilitarySymbols.echelons) { Text($0.label).tag($0.key) } } }
                        Toggle("Visible on map", isOn: $draft.graphic.visible)
                        if let message = draft.validationMessage { Text(message).font(.caption) }
                    }.scrollContentBackground(.hidden).background { FieldScreenBackground() }
                        .foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent)
                        .navigationTitle("Graphic details").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { properties = false } } }
                }.fieldSheetAppearance()
            }
    }
    private var editorHeader: some View {
        row {
                Text(measuringArea ? "Area measurement" : draft.graphic.name).font(.headline).lineLimit(dynamicType.isAccessibilitySize ? nil : 1)
                if !dynamicType.isAccessibilitySize { Spacer() }
                if measuringArea {
                    Button("Done",action: cancel).accessibilityIdentifier("measurement-done")
                    Button("Results") { measureResults = true }.disabled(draft.graphic.points.count < 3).accessibilityIdentifier("measurement-results")
                } else {
                    Button("Details") { properties = true }.accessibilityIdentifier("graphic-details")
                    Button("Cancel", action: cancel)
                    Button("Save", action: save).disabled(draft.validationMessage != nil).accessibilityIdentifier("save-graphic")
                }
            }
    }
    private var pointActions: some View {
        row {
                Button("Add point") {
                    if draft.selected != nil && draft.graphic.points.count >= 2 { draft.insert(centre) } else { draft.append(centre) }
                }.disabled(!draft.canAppend).accessibilityIdentifier("graphic-add-centre")
                Button("Move here") { if let i = draft.selected { draft.move(i, to: centre) } }.disabled(draft.selected == nil).accessibilityIdentifier("graphic-move-centre")
                Button { draft.removeSelected() } label: { Image(systemName: "trash") }.disabled(draft.selected == nil).accessibilityLabel("Remove selected graphic point")
                if measuringArea {
                    Button("Undo") { if !draft.graphic.points.isEmpty { draft.graphic.points.removeLast(); draft.selected = nil } }
                        .disabled(draft.graphic.points.isEmpty).accessibilityIdentifier("measurement-undo")
                }
            }.font(.caption).buttonStyle(.bordered)
    }
}
