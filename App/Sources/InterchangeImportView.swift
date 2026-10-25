import GridFixCore
import SwiftUI

struct TextImportRequest: Identifiable {
    let id = UUID()
    var format: TextInterchangeFormat?
    var url: URL?
}

struct InterchangeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    let request: TextImportRequest
    let knownFolders: [String]
    let onImport: (Backup.Document) -> InterchangeCoordinator.Result
    @State private var text = ""
    @State private var preview: InterchangePreview?
    @State private var message: String?
    @State private var working = false
    @State private var task: Task<Void,Never>?
    @State private var generation = UUID()
    @FocusState private var editing: Bool
    private var label: String { request.format?.label ?? "file" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 16) {
                    if let url = request.url {
                        Label(url.lastPathComponent,systemImage: "doc").font(.headline)
                        Text("Review this file before adding records to your library.")
                    } else {
                        Text("Paste \(label) to preview its \(request.format?.pasteSummary ?? "field data").").font(.subheadline)
                        TextEditor(text: $text).font(.system(.caption,design: .monospaced))
                            .frame(minHeight: 180).scrollContentBackground(.hidden)
                            .padding(8).background(FieldPalette(night: night).ink.opacity(0.06),in: RoundedRectangle(cornerRadius: 12))
                            .focused($editing).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("gpx-import-text")
                            .onChange(of: text) { _ in invalidate() }
                    }
                    if working { ProgressView("Reading and checking…") }
                    if let preview {
                        VStack(alignment: .leading,spacing: 8) {
                            Text("\(preview.format.label) preview").font(.headline)
                            Text("\(preview.document.waypoints.count) waypoints · \(preview.document.graphics.count) graphics/routes · \(preview.document.tracks.count) tracks")
                                .accessibilityIdentifier("interchange-counts")
                            if preview.skipped > 0 { Text("\(preview.skipped) invalid or unsupported entries/coordinates skipped. Check the source before importing.") }
                            if preview.recordCount == 0 { Text("No supported records found. Nothing will be imported.") }
                            Text("Existing records and settings are kept. Importing this unchanged content again adds no duplicates.")
                            Text(preview.format.importNote).font(.footnote)
                            Text("Use a GridFix backup to preserve library symbols and settings.").font(.footnote)
                        }.padding().background(FieldPalette(night: night).ink.opacity(0.06),in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let message { Text(message).font(.footnote).accessibilityIdentifier("interchange-message") }
                }.padding()
            }
            .background { FieldScreenBackground() }
            .navigationTitle("Import \(label)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Import \(label)").font(.headline).foregroundStyle(FieldPalette(night: night).ink) }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { invalidate(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let preview {
                        Button("Import") {
                            editing = false
                            let result = onImport(preview.document)
                            if result.completed { dismiss() } else { message = result.message }
                        }.disabled(preview.recordCount == 0).accessibilityIdentifier("confirm-gpx-import")
                    } else {
                        Button("Preview") { prepare() }.disabled(working || (request.url == nil && text.isEmpty))
                            .accessibilityIdentifier("preview-interchange")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hide keyboard") { editing = false } }
            }
        }
        .foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent).fieldSheetAppearance()
        .onAppear { if request.url != nil { prepare() } }
        .onDisappear { invalidate() }
    }

    private func invalidate() {
        task?.cancel(); task = nil; generation = UUID(); preview = nil; message = nil; working = false
    }
    private func prepare() {
        invalidate(); editing = false; working = true
        let token = generation, input = text, request = request, folders = knownFolders
        task = Task {
            let parser = Task.detached(priority: .userInitiated) {
                if let url = request.url { return try InterchangeFileReader.preview(url,format: request.format,knownFolders: folders) }
                return try TextInterchange.preview(Data(input.utf8),format: request.format,knownFolders: folders)
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await parser.value },onCancel: { parser.cancel() })
                guard !Task.isCancelled, generation == token else { return }
                preview = result; working = false; task = nil
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                message = error.localizedDescription; working = false; task = nil
            }
        }
    }
}
