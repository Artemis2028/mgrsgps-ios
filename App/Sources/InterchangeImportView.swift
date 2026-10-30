import GridFixCore
import SwiftUI

struct TextImportRequest: Identifiable {
    let id = UUID()
    var format: TextInterchangeFormat?
    var url: URL?
}

struct InterchangeImportView: View {
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var field: FieldDataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    let request: TextImportRequest
    let knownFolders: [String]
    var onRestoreBackup: ((Backup.Document) async -> String)? = nil
    let onImport: (Backup.Document) async throws -> InterchangeCoordinator.Result
    private struct DuplicateReview: Sendable {
        let total:Int
        let count:Int
        let all:Backup.Document
        let filtered:Backup.Document
    }
    @State private var requiresPassword = false
    @State private var password = ""
    @State private var backupPreview: Backup.Document?
    @StateObject private var backupMutation = FieldMutation()
    @State private var duplicateReview:DuplicateReview?
    @State private var text = ""
    @State private var preview: InterchangePreview?
    @State private var message: String?
    @State private var working = false
    @StateObject private var importCommit = InterchangeCommit()
    private var importing: Bool { importCommit.importing || backupMutation.working }
    @State private var task: Task<Void,Never>?
    @State private var generation = UUID()
    @FocusState private var editing: Bool
    private var label: String { backupPreview != nil ? "backup" : (preview?.format.label ?? request.format?.label ?? "file") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 16) {
                    if let url = request.url {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "doc").accessibilityHidden(true)
                            Text(url.lastPathComponent)
                                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("interchange-filename")
                        }.font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Paste \(label)").font(.subheadline)
                        TextEditor(text: $text).font(.system(.caption,design: .monospaced))
                            .frame(minHeight: 180).scrollContentBackground(.hidden)
                            .padding(8).background(FieldPalette(night: night).ink.opacity(0.06),in: RoundedRectangle(cornerRadius: 12))
                            .disabled(importing).focused($editing).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("gpx-import-text")
                            .onChange(of: text) { _ in invalidate() }
                    }
                    if requiresPassword {
                        VStack(alignment: .leading,spacing: 8) {
                            Text("Password").font(.caption)
                            SecureField("Password",text: $password).textContentType(.password)
                                .foregroundStyle(FieldPalette(night: night).ink)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("interchange-password")
                        }.padding().background(FieldPalette(night: night).ink.opacity(0.06),in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let backup = backupPreview {
                        VStack(alignment: .leading,spacing: 8) {
                            Text("MGRS GPS backup preview").font(.headline)
                            Text("\(backup.waypoints.count) waypoints · \(backup.graphics.count) graphics/routes · \(backup.tracks.count) tracks")
                                .accessibilityIdentifier("backup-import-counts")
                            if !backup.quietBoundaries.isEmpty {
                                Text(backup.quietBoundaries.count == 1 ? "1 quiet boundary · imported monitoring stays off" : "\(backup.quietBoundaries.count) quiet boundaries · imported monitoring stays off")
                                    .accessibilityIdentifier("backup-quiet-boundary-count")
                            }
                            Text(onRestoreBackup == nil ? "Use Import backup to restore this file." : "Restores records and included settings. Existing records are kept.").font(.footnote)
                        }.padding().background(FieldPalette(night: night).ink.opacity(0.06),in: RoundedRectangle(cornerRadius: 16))
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
                            Text(preview.format.importNote).font(.footnote)
                            DisclosureGroup("Import details") {
                                Text("Existing records and settings are kept. Matching records are reviewed before import. Reimporting unchanged content keeps saved edits.")
                                Text("Use an MGRS GPS backup to preserve library symbols and settings.")
                            }.font(.footnote).accessibilityIdentifier("interchange-details")
                        }.padding().background(FieldPalette(night: night).ink.opacity(0.06),in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let message = importCommit.failure ?? message { Text(message).font(.footnote).accessibilityIdentifier("interchange-message") }
                }.padding()
            }
            .background { FieldScreenBackground() }
            .navigationTitle("Import \(label)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Import \(label)").font(.headline).foregroundStyle(FieldPalette(night: night).ink) }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { password = ""; invalidate(); dismiss() }.disabled(importing) }
                ToolbarItem(placement: .confirmationAction) {
                    if let backup = backupPreview {
                        Button("Restore") {
                            guard let onRestoreBackup else { return }
                            backupMutation.run("Restoring backup…",action: { message = await onRestoreBackup(backup) },completion: { presented in
                                if presented,let message,message.hasPrefix("Restored") || message == "Nothing new to restore" { dismiss() }
                            })
                        }.disabled(importing || onRestoreBackup == nil).accessibilityIdentifier("confirm-protected-backup")
                    } else if let preview {
                        Button("Import") {
                            commit(preview)
                        }.disabled(working || importing || preview.recordCount == 0).accessibilityIdentifier("confirm-gpx-import")
                    } else {
                        Button(requiresPassword ? "Unlock" : "Preview") { prepare() }.disabled(working || (requiresPassword ? password.isEmpty : request.url == nil && text.isEmpty))
                            .accessibilityIdentifier("preview-interchange")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hide keyboard") { editing = false } }
            }
        }
        .foregroundStyle(FieldPalette(night: night).ink).tint(FieldPalette(night: night).accent).fieldSheetAppearance()
        .onAppear { backupMutation.setPresented(true); importCommit.setPresented(true); if request.url != nil { prepare() } }
        .alert("Already here",isPresented:Binding(get:{duplicateReview != nil},set:{if !$0 {duplicateReview=nil}}),presenting:duplicateReview) { review in
            Button("Skip \(review.count)") { finishImport(review.filtered) }
            Button("Import all") { finishImport(review.all) }
            Button("Cancel",role:.cancel) { duplicateReview=nil;message="Import cancelled. Nothing was added." }
        } message: { review in
            Text("\(review.count) of \(review.total) items match your library. Skip the matches, or import them too? Saved records won’t be overwritten.")
        }
        .interactiveDismissDisabled(importing)
        .onDisappear { password = ""; backupMutation.setPresented(false); importCommit.setPresented(false); invalidate() }
    }

    private func invalidate() {
        // Preparation may be cancelled. Once confirmed, retain the owned task
        // through disappearance so ordered publication can finish and report.
        guard !importing else { return }
        importCommit.clearFailure()
        task?.cancel(); task = nil; generation = UUID(); preview = nil; backupPreview = nil; duplicateReview=nil; message = nil; working = false
    }
    private func commit(_ preview: InterchangePreview) {
        guard !working,!importing,preview.recordCount>0 else {return}
        editing=false;message=nil;working=true
        let token=generation,waypoints=store.waypoints,graphics=field.document.graphics,tracks=field.document.tracks,folders=store.folders.map(\.name)
        task=Task {
            let checker=Task.detached(priority:.userInitiated) { () throws -> DuplicateReview in
                guard let contents=preview.contents else {throw BackupError.notABackup("Preview this file again before importing.")}
                let check=try ImportDuplicates.check(contents,waypoints:waypoints,graphics:graphics,tracks:tracks)
                // Rebuild the filtered content's Android namespace/ordinals, rather
                // than assigning random IDs or reusing mismatched filtered ordinals.
                let filtered=check.duplicates>0 ? try check.withoutDuplicates.document(now:preview.document.exportedAt,knownFolders:folders) : preview.document
                return DuplicateReview(total:check.total,count:check.duplicates,all:preview.document,filtered:filtered)
            }
            do {
                let review=try await withTaskCancellationHandler(operation:{try await checker.value},onCancel:{checker.cancel()})
                guard !Task.isCancelled,generation==token else {return}
                working=false;task=nil
                if review.count>0 {duplicateReview=review} else {finishImport(review.all)}
            } catch {
                guard !Task.isCancelled,generation==token else {return}
                working=false;task=nil;message=error.localizedDescription
            }
        }
    }
    private func finishImport(_ document:Backup.Document) {
        duplicateReview=nil
        importCommit.start(document,apply:onImport) { result in
            if result.completed {dismiss()} else {message=result.message}
        }
    }

    private func prepare() {
        guard !importing else { return }
        let suppliedPassword = requiresPassword ? password : nil
        password = ""
        invalidate(); editing = false; working = true
        let token = generation, input = text, request = request, folders = knownFolders
        task = Task {
            let parser = Task.detached(priority: .userInitiated) {
                if let url = request.url { return try InterchangeFileReader.review(url,format: request.format,knownFolders: folders,password: suppliedPassword) }
                return InterchangeFileReview.interchange(try TextInterchange.preview(Data(input.utf8),format: request.format,knownFolders: folders))
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await parser.value },onCancel: { parser.cancel() })
                guard !Task.isCancelled, generation == token else { return }
                switch result {
                case .interchange(let value): preview = value
                case .backup(let value): backupPreview = value
                }
                requiresPassword = false; working = false; task = nil
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                if (error as? BackupCrypto.Failure) == .passwordRequired { requiresPassword = true; message = nil }
                else if (error as? BackupCrypto.Failure) == .authentication { message = "Wrong password, or the file has been changed. Nothing was added." }
                else { message = error.localizedDescription }
                working = false; task = nil
            }
        }
    }
}
