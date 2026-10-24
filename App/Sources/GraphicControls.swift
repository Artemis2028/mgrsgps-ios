import GridFixCore
import SwiftUI

struct GraphicPanel: View {
    @EnvironmentObject private var field: FieldDataStore
    @EnvironmentObject private var waypoints: WaypointStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @State private var error: String?
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
                    Text("Straight segments with draggable points and + handles for adding bends. Tactical boundaries and security lines do not trigger alerts; use Backstops & handrails for quiet-inside crossing monitoring.").font(.footnote)
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
                                var changed = graphic; changed.visible = value; perform { try field.saveGraphic(changed) }
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
                if let error { Text(error).foregroundStyle(palette.warn) }
            }.scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .foregroundStyle(palette.ink).tint(palette.accent)
                .navigationTitle("Graphics & routes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .alert("Delete graphic?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete", role: .destructive) { if let deleting { perform { try field.deleteGraphic(deleting.id) } }; deleting = nil }
                    Button("Keep", role: .cancel) { deleting = nil }
                }
        }.fieldSheetAppearance()
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}

struct GraphicDrawingControls: View {
    @Binding var draft: GraphicDraft
    let centre: GeoPoint
    let error: String?
    var save: () -> Void
    var cancel: () -> Void
    @State private var properties = false
    @Environment(\.fieldNight) private var night
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(draft.graphic.name).font(.headline).lineLimit(1)
                Spacer()
                Button("Details") { properties = true }.accessibilityIdentifier("graphic-details")
                Button("Cancel", action: cancel)
                Button("Save", action: save).disabled(draft.validationMessage != nil).accessibilityIdentifier("save-graphic")
            }
            Text(GraphicTypes.placementHint(draft.graphic.type)).font(.caption)
            HStack {
                Button("Add point") {
                    if draft.selected != nil && draft.graphic.points.count >= 2 { draft.insert(centre) } else { draft.append(centre) }
                }.disabled(!draft.canAppend).accessibilityIdentifier("graphic-add-centre")
                Button("Move here") { if let i = draft.selected { draft.move(i, to: centre) } }.disabled(draft.selected == nil).accessibilityIdentifier("graphic-move-centre")
                Button { draft.removeSelected() } label: { Image(systemName: "trash") }.disabled(draft.selected == nil).accessibilityLabel("Remove selected graphic point")
            }.font(.caption).buttonStyle(.bordered)
            Text("\(draft.graphic.points.count) points · \(draft.selected.map { "point \($0 + 1) selected" } ?? "no selection")")
                .font(.caption).accessibilityIdentifier("graphic-point-count")
            if let i = draft.selected, draft.graphic.points.indices.contains(i) {
                Text(String(format: "%.6f, %.6f", draft.graphic.points[i].lat, draft.graphic.points[i].lon)).font(.system(.caption, design: .monospaced)).accessibilityIdentifier("graphic-selected-coordinate")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(12).fieldChrome()
            .onChange(of: draft.graphic.points.count) { count in
                if count == GraphicTypes.fixedPoints(draft.graphic.type) { properties = true }
            }
            .sheet(isPresented: $properties) {
                NavigationStack {
                    Form {
                        TextField("Name", text: $draft.graphic.name).accessibilityIdentifier("graphic-name")
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
}
