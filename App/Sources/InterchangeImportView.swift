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
    let onImport: (Backup.Document) async throws -> InterchangeCoordinator.Result
    @State private var text = ""
    @State private var preview: InterchangePreview?
    @State private var message: String?
    @State private var working = false
    @StateObject private var importCommit = InterchangeCommit()
    private var importing: Bool { importCommit.importing }
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
                            .disabled(importing).focused($editing).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("gpx-import-text")
                            .onChange(of: text) { _ in invalidate() }
                    }
                    if working || importing {
                        ProgressView(importing ? "Importing records…" : "Reading and checking…")
                            .accessibilityIdentifier("interchange-progress")
                    }
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
                    if let message = importCommit.failure ?? message { Text(message).font(.footnote).accessibilityIdentifier("interchange-message") }
                }.padding()
            }
            .background { FieldScreenBackground() }
            .navigationTitle("Import \(label)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Import \(label)").font(.headline).foregroundStyle(FieldPalette(night: night).ink) }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { invalidate(); dismiss() }.disabled(importing) }
                ToolbarItem(placement: .confirmationAction) {
                    if let preview {
                        Button("Import") {
                            commit(preview)
                        }.disabled(importing || preview.recordCount == 0).accessibilityIdentifier("confirm-gpx-import")
                    } else {
                        Button("Preview") { prepare() }.disabled(working || (request.url == nil && text.isEmpty))
                            .accessibilityIdentifier("preview-interchange")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hide keyboard") { editing = false } }
            }
        }
        .foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent).fieldSheetAppearance()
        .onAppear { importCommit.setPresented(true); if request.url != nil { prepare() } }
        .interactiveDismissDisabled(importing)
        .onDisappear { importCommit.setPresented(false); invalidate() }
    }

    private func invalidate() {
        // Preparation may be cancelled. Once confirmed, retain the owned task
        // through disappearance so ordered publication can finish and report.
        guard !importing else { return }
        importCommit.clearFailure()
        task?.cancel(); task = nil; generation = UUID(); preview = nil; message = nil; working = false
    }
    private func commit(_ preview: InterchangePreview) {
        guard !working, preview.recordCount > 0 else { return }
        editing = false; message = nil
        importCommit.start(preview.document,apply: onImport) { result in
            if result.completed { dismiss() } else { message = result.message }
        }
    }

    private func prepare() {
        guard !importing else { return }
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
