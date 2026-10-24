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
                        Text(request.format == .csv ? "Paste CSV to preview its waypoints." : "Paste \(label) to preview its waypoints, routes and tracks.").font(.subheadline)
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
                            Text(preview.format == .geojson ? "Lines become routes and outer polygon rings become areas. Polygon holes and original tactical types are not retained." : preview.format == .csv ? "CSV carries waypoint coordinates, folders and supported metadata." : "GPX carries waypoints, routes and separate continuous track segments.").font(.footnote)
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
                let bytes = try request.url.map { try InterchangeFileReader.read($0,limit: request.format?.byteLimit ?? 32*1024*1024) } ?? Data(input.utf8)
                return try TextInterchange.preview(bytes,format: request.format,filename: request.url?.lastPathComponent ?? "",knownFolders: folders)
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
