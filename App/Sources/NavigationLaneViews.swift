import GridFixCore
import SwiftUI

enum LaneMapAction { case create, edit(NavLane), show(NavLane) }
struct LaneMapRequest: Identifiable { let id = UUID(); let action: LaneMapAction }
struct LaneSaveFolderError: LocalizedError { let message: String; var errorDescription: String? { message } }

struct LaneEditingDraft {
    var lane: NavLane
    let original: NavLane?
    var role: LaneLimit = .left
    init(_ lane: NavLane? = nil) {
        original = lane
        self.lane = lane ?? NavLane(name: "",left: .init(),right: .init(),backstop: .init(),scope: .checkpoint,targetId: "",createdAt: Int64(Date().timeIntervalSince1970*1000))
    }
    var line: LaneLine {
        get { switch role { case .left: return lane.left; case .right: return lane.right; case .backstop: return lane.backstop } }
        set { switch role { case .left: lane.left = newValue; case .right: lane.right = newValue; case .backstop: lane.backstop = newValue } }
    }
}
extension LaneLimit {
    var title: String { switch self { case .left: return "Left limit"; case .right: return "Right limit"; case .backstop: return "Backstop" } }
}

struct NavigationLaneLibraryView: View {
    @EnvironmentObject private var lanes: NavigationLaneStore
    @EnvironmentObject private var field: FieldDataStore
    @EnvironmentObject private var waypoints: WaypointStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mutation = FieldMutation()
    @State private var deleting: NavLane?
    let action: (LaneMapAction) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Draw a left limit, right limit and backstop, or follow lines already on your map. Inside is silent; crossing gives a turn cue. This is separate from quiet-inside perimeter monitoring.").font(.footnote)
                    Button("Draw navigation lane",systemImage: "pencil.and.outline") { action(.create); dismiss() }.accessibilityIdentifier("create-nav-lane")
                    if !lanes.ready { ProgressView("Loading lanes…") }
                    if let error = lanes.error { Text(error).foregroundStyle(.red) }
                }
                ForEach(lanes.lanes) { lane in
                    Section {
                        Button { action(.show(lane)); dismiss() } label: {
                            VStack(alignment: .leading,spacing: 5) {
                                Text(lane.name.isEmpty ? "Navigation lane" : lane.name).font(.headline)
                                Text(NavLanes.limitsSummary(lane,graphics: field.document.graphics)).font(.caption)
                                Text(target(lane)).font(.caption)
                                if !lane.visible { Text("Hidden on map · guidance still enabled").font(.caption) }
                                if let problem = problem(lane) { Text(problem+" · azimuth fallback").font(.caption).foregroundStyle(.red) }
                            }.frame(maxWidth: .infinity,alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("nav-lane-"+lane.id)
                        Toggle("Visible on map",isOn: Binding(get: { lane.visible },set: { value in mutation.run("Saving visibility…",action: { try await lanes.setVisible(lane.id,value) }) }))
                        Button("Edit lane") { action(.edit(lane)); dismiss() }
                        Button("Delete lane",role: .destructive) { deleting = lane }
                    }
                }
                if let label = mutation.label { ProgressView(label) }
                if let error = mutation.error { Text(error).foregroundStyle(.red) }
            }.disabled(mutation.working).scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .navigationTitle("Navigation lanes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(mutation.working) } }
        }.fieldSheetAppearance().interactiveDismissDisabled(mutation.working)
            .onAppear { mutation.setPresented(true) }.onDisappear { mutation.setPresented(false) }
            .confirmationDialog("Delete this lane? Its linked graphics are kept.",isPresented: Binding(get: { deleting != nil },set: { if !$0 { deleting = nil } }),titleVisibility: .visible) {
                Button("Delete lane",role: .destructive) { if let lane = deleting { mutation.run("Deleting lane…",action: { try await lanes.delete(lane.id) }) }; deleting = nil }
            }
    }
    private func target(_ lane: NavLane) -> String {
        let name = lane.scope == .route ? field.document.graphics.first { $0.id == lane.targetId }?.name : waypoints.waypoints.first { $0.id == lane.targetId }?.name
        return (lane.scope == .route ? "Whole route: " : "Checkpoint: ")+(name ?? "Target deleted")
    }
    private func problem(_ lane: NavLane) -> String? { do { _ = try NavLanes.resolve(lane,graphics: field.document.graphics,waypoints:waypoints.waypoints); return nil } catch { return error.localizedDescription } }
}

struct LaneDrawingControls: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var row: AnyLayout { dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout()) }
    let draft: LaneEditingDraft
    let count: Int
    let selected: Bool
    let busy: Bool
    let error: String?
    var chooseRole: (LaneLimit) -> Void
    var add: () -> Void
    var undo: () -> Void
    var remove: () -> Void
    var useLine: () -> Void
    var drawInstead: () -> Void
    var review: () -> Void
    var cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            Text("Navigation lane · \(draft.role.title)").font(.headline)
            if dynamicType.isAccessibilitySize {
                laneRolePicker.pickerStyle(.menu)
            } else { laneRolePicker.pickerStyle(.segmented) }
            if draft.line.graphicId != nil {
                Text("Follows a saved graphic. Move that graphic to move this limit.").font(.caption)
                Button("Draw a replacement line",action: drawInstead)
            } else {
                Text("\(count) points · tap to draw; hold and drag a point or segment to reshape.").font(.caption).accessibilityIdentifier("lane-point-count")
                row {
                    Button("Add point",action: add).disabled(count >= 500).accessibilityIdentifier("lane-add-point")
                    Button("Undo",action: undo).disabled(count == 0)
                    Button("Remove point",action: remove).disabled(!selected)
                }.font(.caption)
            }
            row {
                Button("Use existing line…",action: useLine).accessibilityIdentifier("lane-use-line")
                if !dynamicType.isAccessibilitySize { Spacer() }
                Button("Review lane",action: review).accessibilityIdentifier("review-nav-lane")
                Button("Cancel",action: cancel)
            }.font(.caption)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if busy { ProgressView("Saving lane…") }
        }.padding(12).fieldChrome().disabled(busy)
    }
    private var laneRolePicker: some View {
        Picker("Lane line",selection: Binding(get: { draft.role },set: chooseRole)) {
            Text("Left").tag(LaneLimit.left); Text("Right").tag(LaneLimit.right); Text("Backstop").tag(LaneLimit.backstop)
        }.accessibilityIdentifier("lane-line-role")
    }
}

struct LaneDetailsView: View {
    @Binding var draft: LaneEditingDraft
    let busy: Bool
    let error: String?
    let save: () -> Void
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var field: FieldDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var options: [(String,String)] {
        let values = draft.lane.scope == .route ? field.document.graphics.filter { $0.type == "route" }.map { ($0.id,$0.name) } : waypoints.waypoints.filter { $0.kind != KIND_UNIT }.map { ($0.id,$0.name) }
        return values.filter { search.isEmpty || $0.1.localizedCaseInsensitiveContains(search) }
    }
    private var problem: String? {
        do { _ = try NavLanes.resolve(draft.lane,graphics: field.document.graphics,waypoints:waypoints.waypoints) }
        catch { return error.localizedDescription }
        if draft.lane.targetId.isEmpty { return "Choose a checkpoint or route." }
        if draft.lane.scope == .route && !field.document.graphics.contains(where: { $0.id == draft.lane.targetId && $0.type == "route" }) { return "Choose a saved route." }
        if draft.lane.scope == .checkpoint && !waypoints.waypoints.contains(where: { $0.id == draft.lane.targetId }) { return "Choose a saved checkpoint." }
        return nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Lane") {
                    TextField("Lane name",text: $draft.lane.name).accessibilityIdentifier("nav-lane-name")
                    TextField("Folder",text: $draft.lane.folder)
                    TextField("Left landmark",text: $draft.lane.left.label).disabled(draft.lane.left.graphicId != nil)
                    TextField("Right landmark",text: $draft.lane.right.label).disabled(draft.lane.right.graphicId != nil)
                    TextField("Backstop landmark",text: $draft.lane.backstop.label).disabled(draft.lane.backstop.graphicId != nil)
                    Text(NavLanes.limitsSummary(draft.lane,graphics: field.document.graphics)).font(.caption)
                }
                Section("Guides to") {
                    Picker("Applies to",selection: $draft.lane.scope) { Text("Checkpoint").tag(NavLane.Scope.checkpoint); Text("Whole route").tag(NavLane.Scope.route) }.pickerStyle(.segmented)
                        .onChange(of: draft.lane.scope) { _ in draft.lane.targetId = "" }
                    TextField("Search targets",text: $search)
                    ForEach(options,id: \.0) { id,name in
                        Button { draft.lane.targetId = id } label: { HStack { Text(name); Spacer(); if draft.lane.targetId == id { Image(systemName: "checkmark") } } }
                            .accessibilityIdentifier("lane-target-"+id)
                    }
                }
                if let problem { Section { Text(problem).foregroundStyle(.red) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if busy { ProgressView("Saving lane…") }
                Section { Text("Inside is silent. Distinct repeated turn patterns work while the app is open. Locked-screen crossings request iOS notifications; Focus and notification permissions apply.").font(.caption) }
            }.disabled(busy).scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .navigationTitle("Review lane").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Back to map") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save lane",action: save).disabled(problem != nil || busy).accessibilityIdentifier("save-nav-lane") }
                }
        }.fieldSheetAppearance().interactiveDismissDisabled(busy)
    }
}
