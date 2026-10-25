import GridFixCore
import SwiftUI

struct WaypointRecoveryView: View {
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var confirming = false
    @State private var message: String?
    @State private var failure: String?
    @State private var files: [Archive] = []
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    private struct Archive: Identifiable, Sendable {
        let url: URL
        let date: Date
        let size: Int64
        var id: URL { url }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if store.loadError != nil {
                        Text("Saved waypoints need attention").font(.headline)
                        Text("The saved file could not be read and has not been overwritten. You can retry after the file becomes available, or preserve it and start an empty waypoint library before restoring a backup.")
                            .font(.footnote).foregroundStyle(palette.ink)
                        Button("Retry loading") { retry() }.frame(minHeight: 44).buttonStyle(.bordered).disabled(working).accessibilityIdentifier("waypoint-recovery-retry")
                        Button("Preserve original for sharing") { preserve() }.frame(minHeight: 44).buttonStyle(.bordered).disabled(working).accessibilityIdentifier("waypoint-recovery-preserve")
                        Button("Archive original and start fresh", role: .destructive) { confirming = true }
                            .frame(minHeight: 44).buttonStyle(.bordered).disabled(working).accessibilityIdentifier("waypoint-recovery-fresh")
                    } else {
                        Text("Waypoint library available").font(.headline).accessibilityIdentifier("waypoint-recovery-available")
                    }
                    if working { ProgressView("Preparing recovery…").tint(palette.accent) }
                    if let message { Text(message).font(.footnote).accessibilityIdentifier("waypoint-recovery-result") }
                    if let failure { Text(failure).font(.footnote).foregroundStyle(palette.warn).accessibilityIdentifier("waypoint-recovery-error") }
                    Text("Preserved originals").font(.headline)
                    Text("Keep these copies for repair or before restoring a backup. A preserved file may still be unreadable.").font(.footnote).foregroundStyle(palette.inkDim)
                    if files.isEmpty { Text("No preserved originals yet").font(.footnote).foregroundStyle(palette.inkDim) }
                    ForEach(files) { file in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(file.date.formatted(date: .abbreviated, time: .standard)).font(.subheadline)
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption).foregroundStyle(palette.inkDim)
                            ShareLink(item: file.url) { Label("Save or share original", systemImage: "square.and.arrow.up").frame(minHeight: 44) }
                                .accessibilityIdentifier("waypoint-recovery-share")
                        }.padding().fieldChrome()
                    }
                }.padding(20).foregroundStyle(palette.ink)
            }.background(palette.background.ignoresSafeArea()).tint(palette.accent)
                .navigationTitle("Waypoint recovery").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Waypoint recovery").font(.headline).foregroundStyle(palette.ink) }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(working).accessibilityIdentifier("waypoint-recovery-done") }
                }
        }.fieldSheetAppearance().interactiveDismissDisabled(working).task { await reloadFiles() }
            .alert("Start an empty waypoint library?", isPresented: $confirming) {
                Button("Archive and start fresh", role: .destructive) { recover() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("First preserves an exact copy of the original file on this device. The new waypoint library starts empty. You can then restore a backup or import your records. If the original cannot be preserved, nothing is replaced.") }
    }
    private func retry() {
        working = true; failure = nil; message = nil
        Task { @MainActor in
            defer { working = false }
            do {
                let snapshot = try store.recoverySnapshot()
                let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepareReload() }.value
                _ = try store.publishReload(prepared)
                message = "Loaded saved waypoints."
            } catch { failure = "Unable to reload: " + error.localizedDescription }
        }
    }
    private func preserve() {
        working = true; failure = nil; message = nil
        Task { @MainActor in
            defer { working = false }
            do {
                let snapshot = try store.recoverySnapshot()
                _ = try await Task.detached(priority: .userInitiated) { try snapshot.preserveOriginal() }.value
                message = "Original preserved. The saved library has not been replaced."
            } catch { failure = "Unable to preserve original: " + error.localizedDescription }
            await reloadFiles()
        }
    }
    private func recover() {
        working = true; failure = nil; message = nil
        Task { @MainActor in
            defer { working = false }
            do {
                let snapshot = try store.recoverySnapshot()
                let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepareFreshLibrary() }.value
                _ = try store.publishRecovery(prepared)
                message = "Original preserved. The empty waypoint library is ready for a backup restore or import."
            } catch { failure = "Recovery stopped: " + error.localizedDescription }
            await reloadFiles()
        }
    }
    private func reloadFiles() async {
        let store = store
        do {
            files = try await Task.detached(priority: .utility) {
                try store.recoveryFiles().map { url in
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    return Archive(url: url, date: attributes[.creationDate] as? Date ?? .distantPast, size: (attributes[.size] as? NSNumber)?.int64Value ?? 0)
                }.sorted { $0.date > $1.date }
            }.value
        } catch { failure = "Unable to list preserved files: " + error.localizedDescription }
    }
}
