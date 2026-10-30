import GridFixCore
import SwiftUI

struct MapAreaRenameView: View {
    @EnvironmentObject private var maps: MapLayerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @State private var name: String
    @State private var working = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    let map: SavedMap
    init(map: SavedMap) { self.map = map; _name = State(initialValue: map.name) }
    private var palette: FieldPalette { .init(night: night) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Area name", text: $name, prompt: Text("Area name").foregroundColor(palette.inkDim))
                    .focused($focused).submitLabel(.done).onSubmit { focused = false }
                    .accessibilityIdentifier("offline-area-name")
                    .onChange(of: name) { value in if value.count > 80 { name = String(value.prefix(80)) } }
                Text("Renames this saved area without moving or downloading its tiles.").font(.footnote).foregroundStyle(palette.inkDim)
                if let failure { Text(failure).foregroundStyle(palette.warn).accessibilityIdentifier("offline-rename-error") }
                if working { ProgressView("Saving…").tint(palette.accent) }
            }.foregroundStyle(palette.ink).scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .navigationTitle("Rename area").navigationBarTitleDisplayMode(.inline).tint(palette.accent)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Rename area").font(.headline).foregroundStyle(palette.ink) }
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working).accessibilityIdentifier("offline-area-rename-cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            focused = false; working = true; failure = nil
                            Task {
                                if await maps.rename(map, name: name) { dismiss() }
                                else { failure = maps.message ?? "Unable to rename this area" }
                                working = false
                            }
                        }.disabled(working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("offline-area-rename-save")
                    }
                }
        }.interactiveDismissDisabled(working).fieldSheetAppearance()
    }
}
