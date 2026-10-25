import GridFixCore
import SwiftUI

struct LibraryFolderRequest: Identifiable {
    let id = UUID()
    var original: String?
}

struct LibraryFolderEditor: View {
    let original: String?
    let folders: [FolderInfo]
    var save: (String) throws -> Void
    @State private var name: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    init(original: String?,folders: [FolderInfo],save: @escaping (String) throws -> Void) {
        self.original = original; self.folders = folders; self.save = save; _name = State(initialValue: original ?? "")
    }
    private var merged: String? { folders.first { $0.name != original && $0.name.caseInsensitiveCompare(Folders.canonical(name)) == .orderedSame }?.name }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name",text: $name).submitLabel(.done).accessibilityIdentifier("library-folder-name")
                if let hint = Folders.reservedHint(name) { Text(hint).font(.footnote) }
                if let merged { Text("Merges into \(merged)").font(.footnote) }
                if original != nil { Text("Waypoints, graphics and finished tracks move with the folder. Base is permanent.").font(.footnote) }
                if let error { Text(error).foregroundStyle(FieldPalette(night: night).warn) }
            }.scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent)
                .navigationTitle(original == nil ? "New folder" : "Rename folder").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(original == nil ? "Create" : "Rename") {
                            do { try save(name); dismiss() } catch { self.error = error.localizedDescription }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == original).accessibilityIdentifier("library-folder-save")
                    }
                }
        }.fieldSheetAppearance()
    }
}

struct LibraryTrackFolderPicker: View {
    let track: Backup.TrackMeta
    let folders: [FolderInfo]
    var move: (String) async throws -> Void
    @StateObject private var mutation = FieldMutation()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    var body: some View {
        NavigationStack {
            List {
                ForEach(folders) { folder in
                    Button {
                        mutation.run("Moving track…",action: { try await move(folder.name) },completion: { if $0 { dismiss() } })
                    } label: {
                        HStack {
                            Text(folder.name == track.folder ? "\(folder.name) (current)" : folder.name)
                            Spacer()
                        }.frame(maxWidth: .infinity,minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(folder.name == track.folder).accessibilityIdentifier("move-track-to-\(folder.name)")
                }
                if let label = mutation.label { ProgressView(label) }
                if let error = mutation.error { Text(error).foregroundStyle(FieldPalette(night: night).warn) }
            }.disabled(mutation.working).scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent)
                .navigationTitle("Move \(track.name)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(mutation.working) } }
        }.fieldSheetAppearance().interactiveDismissDisabled(mutation.working)
            .onAppear { mutation.setPresented(true) }.onDisappear { mutation.setPresented(false) }
    }
}
