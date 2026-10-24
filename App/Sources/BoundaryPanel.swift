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
                    Text("Draw the perimeter of the area you want to stay inside. Straight sides and end backstops join at movable points; add points to make bends.")
                    Text("Quiet anywhere inside. One buzz on a confirmed exit, then quiet outside until you return inside and re-arm. Your heading does not matter.").font(.footnote).foregroundStyle(palette.inkDim)
                    Button("Draw boundary") { dismiss(); onDraw(nil) }
                        .disabled(monitor.running || monitor.preparing || monitor.loadFailed).accessibilityIdentifier("draw-boundary")
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
                    Text("Start while the app is open with Precise Location. Monitoring continues with background location while locked when iOS permits. Locked-screen alerts use notification sound/haptic settings; Focus or notification settings can silence them. Force quit or termination stops monitoring; reopen and start again.")
                        .font(.footnote).foregroundStyle(palette.inkDim)
                    Button("Open iOS settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
                if let error = monitor.error { Text(error).foregroundStyle(palette.warn).accessibilityIdentifier("boundary-error") }
                Section("Saved boundaries") {
                    if monitor.areas.isEmpty { Text("No boundaries saved").foregroundStyle(palette.inkDim) }
                    ForEach(monitor.areas) { area in
                        VStack(alignment: .leading,spacing: 10) {
                            Text(area.name).font(.headline)
                            Text("\(area.vertices.count) points · closed perimeter").font(.caption).foregroundStyle(palette.inkDim)
                            HStack {
                                Button("Show") { onShow(area); dismiss() }.disabled(monitor.running && monitor.activeID != area.id)
                                Button("Edit") { dismiss(); onDraw(area) }.disabled(monitor.running || monitor.preparing)
                                Spacer()
                                Button("Monitor") { monitor.start(area) }.disabled(monitor.running || monitor.preparing || monitor.loadFailed)
                                    .accessibilityIdentifier("monitor-boundary-\(area.name)")
                                Button(role: .destructive) { deleting = area } label: { Image(systemName: "trash") }
                                    .disabled(monitor.running || monitor.preparing).accessibilityLabel("Delete boundary \(area.name)")
                            }.buttonStyle(.borderless)
                        }.padding(.vertical,6)
                    }
                }
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .foregroundStyle(palette.ink).tint(palette.accent)
            .navigationTitle("Boundaries").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Delete boundary?",isPresented: Binding(get: { deleting != nil },set: { if !$0 { deleting = nil } })) {
                Button("Delete",role: .destructive) { if let deleting { monitor.delete(deleting) }; deleting = nil }
                Button("Keep",role: .cancel) { deleting = nil }
            }
        }.fieldSheetAppearance()
    }
}

struct BoundaryDrawingControls: View {
    @Binding var draft: BoundaryDraft
    let centre: GeoPoint
    let error: String?
    var save: () -> Void
    var cancel: () -> Void
    private func normal(_ point: GeoPoint) -> GeoPoint { GeoPoint(lat: point.lat,lon: ((point.lon+540).truncatingRemainder(dividingBy: 360))-180) }
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            HStack {
                TextField("Boundary name",text: $draft.name).textFieldStyle(.roundedBorder).submitLabel(.done).onSubmit { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to: nil,from: nil,for: nil) }.accessibilityIdentifier("boundary-name")
                Button("Cancel",action: cancel).accessibilityIdentifier("cancel-boundary")
                Button("Save",action: save).disabled(draft.vertices.count < 3).accessibilityIdentifier("save-boundary")
            }
            Text("Tap to draw. Hold and drag a point or line to reshape it.")
                .font(.caption)
            HStack {
                Button("Add point") {
                    guard draft.vertices.count < 256 else { return }
                    let index = draft.selected.map { min($0+1,draft.vertices.count) } ?? draft.vertices.count
                    draft.vertices.insert(normal(centre),at: index); draft.selected = index
                }.accessibilityIdentifier("boundary-add-centre")
                Button("Move here") { if let i = draft.selected, draft.vertices.indices.contains(i) { draft.vertices[i] = normal(centre) } }
                    .disabled(draft.selected == nil).accessibilityIdentifier("boundary-move-centre")
                Button { if let i = draft.selected, draft.vertices.indices.contains(i) { draft.vertices.remove(at: i); draft.selected = nil } }
                    label: { Image(systemName: "trash") }.disabled(draft.selected == nil).accessibilityLabel("Remove selected boundary point")
            }.font(.caption).buttonStyle(.bordered)
            Text("\(draft.vertices.count) points · \(draft.selected.map { "point \($0+1) selected" } ?? "no selection")")
                .font(.caption).accessibilityIdentifier("boundary-point-count")
            if let i = draft.selected, draft.vertices.indices.contains(i) {
                Text(String(format: "%.6f, %.6f",draft.vertices[i].lat,draft.vertices[i].lon))
                    .font(.system(.caption,design: .monospaced)).accessibilityIdentifier("boundary-selected-coordinate")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("boundary-draw-error") }
        }.padding(12).fieldChrome()
    }
}
