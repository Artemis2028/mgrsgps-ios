import GridFixCore
import SwiftUI

struct GPXPasteImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    let onImport: (Backup.Document) -> Void
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a GPX document to import its waypoints, routes, and tracks.").font(.subheadline)
                TextEditor(text: $text).font(.system(.caption, design: .monospaced))
                    .accessibilityIdentifier("gpx-import-text").autocorrectionDisabled().textInputAutocapitalization(.never)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding().background { FieldScreenBackground() }
            .navigationTitle("Import GPX").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        do { let document = try GPX.parse(text); onImport(document); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(text.isEmpty).accessibilityIdentifier("confirm-gpx-import")
                }
            }
        }.foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent).fieldSheetAppearance()
    }
}
