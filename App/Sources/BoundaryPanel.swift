import GridFixCore
import SwiftUI

struct BoundaryDraft: Equatable {
    var id = UUID().uuidString
    var name = "Boundary"
    var vertices: [GeoPoint] = []
    var selected: Int?
    init() {}
    init(_ area: BoundaryArea) { id = area.id; name = area.name; vertices = area.vertices }
    var area: BoundaryArea { BoundaryArea(id: id,name: name,vertices: vertices) }
}

struct BoundaryPanel: View {
    @EnvironmentObject private var monitor: BoundaryMonitor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @State private var deleting: BoundaryArea?
    var onDraw: (BoundaryArea?) -> Void
    var onShow: (BoundaryArea) -> Void
    private var palette: FieldPalette { FieldPalette(night: night) }
    var body: some View {
        NavigationStack {
            List {
                Section("Backstops & handrails") {
                    Button("Draw boundary") { dismiss(); onDraw(nil) }
                        .disabled(monitor.running || monitor.preparing || monitor.writing || monitor.loadFailed).accessibilityIdentifier("draw-boundary")
                }
                Section("Monitoring") {
                    Text(monitor.running && !monitor.hasFreshFix ? "Waiting for an accurate, fresh location" : monitor.status)
                        .accessibilityIdentifier("boundary-status")
                    if monitor.running || monitor.preparing {
                        Text(monitor.activeArea?.name ?? "Preparing monitoring…").font(.headline)
                        Text("\(monitor.crossingCount) exits this session").accessibilityIdentifier("boundary-crossings")
                        Text(monitor.alertStatus).font(.footnote).foregroundStyle(palette.inkDim)
                        Button("Stop monitoring",role: .destructive) { monitor.stop() }.accessibilityIdentifier("stop-boundary")
                    }
                }
                if monitor.writing { ProgressView("Saving boundaries…").tint(palette.accent).accessibilityIdentifier("boundary-saving") }
                if let error = monitor.error { Text(error).foregroundStyle(palette.warn).accessibilityIdentifier("boundary-error") }
                Section("Saved boundaries") {
                    if monitor.areas.isEmpty { Text("No boundaries saved").foregroundStyle(palette.inkDim) }
                    ForEach(monitor.areas) { area in
                        VStack(alignment: .leading,spacing: 10) {
                            Text(area.name).font(.headline)
                            Text("\(area.vertices.count) points · closed perimeter").font(.caption).foregroundStyle(palette.inkDim)
                            HStack {
                                Button("Show") { onShow(area); dismiss() }.disabled(monitor.running && monitor.activeID != area.id)
                                Button("Edit") { dismiss(); onDraw(area) }.disabled(monitor.running || monitor.preparing || monitor.writing)
                                Spacer()
                                Button("Monitor") { monitor.start(area) }.disabled(monitor.running || monitor.preparing || monitor.writing || monitor.loadFailed)
                                    .accessibilityIdentifier("monitor-boundary-\(area.name)")
                                Button(role: .destructive) { deleting = area } label: { Image(systemName: "trash") }
                                    .disabled(monitor.running || monitor.preparing || monitor.writing).accessibilityLabel("Delete boundary \(area.name)")
                            }.buttonStyle(.borderless)
                        }.padding(.vertical,6)
                    }
                }
                Section {
                    DisclosureGroup("Boundary help") {
                        Text("Draw a closed perimeter. Move its points or add points along a side to make bends.")
                        Text("Monitoring stays quiet inside. A confirmed exit triggers one alert; returning inside re-arms it. Heading does not affect crossings.")
                        Text("Start with Precise Location while the app is open. Background location continues while locked when iOS permits. Focus and notification settings can silence locked-screen alerts.")
                        Text("Force quit or termination stops monitoring. Reopen the app and start again.")
                        Button("Open iOS settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }.accessibilityIdentifier("boundary-help")
                }
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .foregroundStyle(palette.ink).tint(palette.accent)
            .navigationTitle("Boundaries").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Delete boundary?",isPresented: Binding(get: { deleting != nil },set: { if !$0 { deleting = nil } })) {
                Button("Delete",role: .destructive) { if let deleting { Task { await monitor.delete(deleting) } }; deleting = nil }
                Button("Keep",role: .cancel) { deleting = nil }
            }
        }.fieldSheetAppearance()
    }
}

struct BoundaryDrawingControls: View {
    @FocusState private var nameFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var row: AnyLayout { dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout()) }
    @Binding var draft: BoundaryDraft
    let centre: GeoPoint
    let error: String?
    var saving = false
    var save: () -> Void
    var cancel: () -> Void
    private func normal(_ point: GeoPoint) -> GeoPoint { GeoPoint(lat: point.lat,lon: ((point.lon+540).truncatingRemainder(dividingBy: 360))-180) }
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            row {
                TextField("Boundary name",text: $draft.name).focused($nameFocused).disabled(saving).textFieldStyle(.roundedBorder).submitLabel(.done).onSubmit { nameFocused = false }.accessibilityIdentifier("boundary-name")
                Button("Cancel",action: cancel).accessibilityIdentifier("cancel-boundary")
                Button(saving ? "Saving…" : "Save",action: save).disabled(saving || draft.vertices.count < 3).accessibilityIdentifier("save-boundary")
            }
            row {
                Button("Add point") {
                    guard draft.vertices.count < 256 else { return }
                    let index = draft.selected.map { min($0+1,draft.vertices.count) } ?? draft.vertices.count
                    draft.vertices.insert(normal(centre),at: index); draft.selected = index
                }.accessibilityIdentifier("boundary-add-centre")
                Button("Move here") { if let i = draft.selected, draft.vertices.indices.contains(i) { draft.vertices[i] = normal(centre) } }
                    .disabled(draft.selected == nil).accessibilityIdentifier("boundary-move-centre")
                Button { if let i = draft.selected, draft.vertices.indices.contains(i) { draft.vertices.remove(at: i); draft.selected = nil } }
                    label: { Image(systemName: "trash") }.disabled(draft.selected == nil).accessibilityLabel("Remove selected boundary point")
            }.font(.caption).buttonStyle(.bordered).disabled(saving)
            Text("\(draft.vertices.count) points · \(draft.selected.map { "point \($0+1) selected" } ?? "no selection")")
                .font(.caption).accessibilityIdentifier("boundary-point-count")
            if let i = draft.selected, draft.vertices.indices.contains(i) {
                Text(String(format: "%.6f, %.6f",draft.vertices[i].lat,draft.vertices[i].lon))
                    .font(.system(.caption,design: .monospaced)).accessibilityIdentifier("boundary-selected-coordinate")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("boundary-draw-error") }
        }.padding(12).fieldChrome()
            .toolbar {
                ToolbarItemGroup(placement:.keyboard) {
                    Spacer()
                    Button("Done") { nameFocused = false }.accessibilityIdentifier("boundary-name-keyboard-done")
                }
            }
    }
}
