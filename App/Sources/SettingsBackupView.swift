import SwiftUI
import GridFixCore
import UniformTypeIdentifiers

/// Settings and waypoint actions share one snapshot/codec/restore contract.
struct SettingsBackupView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var field: FieldDataStore
    @EnvironmentObject private var lanes: NavigationLaneStore
    @EnvironmentObject private var boundaries: BoundaryMonitor
    @Environment(\.dismiss) private var dismiss
    @StateObject private var transfer = BackupTransfer()
    @State private var importing = false
    @State private var passwordRequest: BackupPasswordRequest?
    @State private var pendingPassword: (URL?,String)?
    @State private var exportFile: FieldExportDocumentFile?
    @State private var exportReported = false
    @State private var status: String?
    private var palette: FieldPalette { .init(night:settings.nightMode) }
    private var busy: Bool { transfer.phase != nil || exportFile != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Keep waypoints, folders, graphics, tracks, settings and practice results in one backup. Restoring adds saved data without duplicating existing records.")
                        .fixedSize(horizontal:false,vertical:true)
                    Text("Offline maps and active recording/navigation sessions are kept separately.")
                        .font(.footnote).foregroundStyle(palette.inkDim).fixedSize(horizontal:false,vertical:true)
                }.listRowBackground(rowColor)
                Section {
                    Button("Back up now") { export() }.accessibilityIdentifier("settings-backup-export")
                    Button("Create protected backup") { passwordRequest = .init(url:nil) }.accessibilityIdentifier("settings-backup-protect")
                    Button("Restore…") { importing = true }.accessibilityIdentifier("settings-backup-restore")
                }.disabled(busy).listRowBackground(rowColor)
                if let phase = transfer.phase {
                    Section {
                        ProgressView(phase.title).accessibilityIdentifier("settings-backup-progress")
                        if phase != .restoring { Button("Cancel") { transfer.cancel(); status = "Backup operation cancelled" }.accessibilityIdentifier("settings-backup-cancel") }
                    }.listRowBackground(rowColor)
                }
                if let status {
                    Section { Text(status).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("settings-backup-status") }
                        .listRowBackground(rowColor)
                }
            }.foregroundStyle(palette.ink).scrollContentBackground(.hidden).background(palette.background)
                .navigationTitle("Backup & restore").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) {
                    Button("Done") { dismiss() }.disabled(transfer.phase == .restoring)
                } }
        }.tint(palette.accent).environment(\.fieldNight,settings.nightMode).fieldSheetAppearance()
            .interactiveDismissDisabled(transfer.phase == .restoring)
            .sheet(item:$passwordRequest,onDismiss:finishPassword) { request in
                BackupPasswordSheet(exporting:request.url == nil) { value in
                    pendingPassword = (request.url,value); passwordRequest = nil
                }
            }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.zip,.gridFixProtectedBackup,.data],allowsMultipleSelection:false) { result in
                switch result {
                case .success(let files): if let file = files.first { restore(file) }
                case .failure(let error):
                    if !cancelled(error) { status = "Import failed: " + error.localizedDescription }
                }
            }
            .background {
                if let exportFile {
                    FieldFileExportPresentation(document:exportFile,onDismiss: {
                        if !exportReported { status = "Backup not saved" }
                        self.exportFile = nil
                    }) { result in
                        exportReported = true
                        switch result {
                        case .success: status = "Backup saved"
                        case .failure(let error):
                            status = cancelled(error) ? "Backup not saved" : "Export failed: " + error.localizedDescription
                        }
                    }
                }
            }
            .onDisappear { transfer.cancel(); pendingPassword = nil }
    }
    private func cancelled(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError
    }
    private var rowColor: Color { settings.nightMode ? .black : Color(white:0.12) }
    private func export(password: String? = nil) {
        guard !busy else { return }
        do {
            let document = try BackupCoordinator.snapshot(waypoints:waypoints,fieldData:field,settings:settings,lanes:lanes,boundaries:boundaries)
            status = nil
            transfer.export(document,password:password) { result in
                switch result {
                case .success(let bytes):
                    exportReported = false
                    exportFile = .init(data:bytes,contentType:password == nil ? .zip : .gridFixProtectedBackup,
                                       filename:password == nil ? "gridfix-backup" : "gridfix-backup.mgrsgps")
                    status = "Backup ready"
                case .failure(let error): status = "Backup failed: " + error.localizedDescription
                }
            }
        } catch { status = "Backup failed: " + error.localizedDescription }
    }
    private func restore(_ file: URL,password: String? = nil) {
        guard !busy else { return }
        status = nil
        transfer.restore(file,password:password,passwordRequired: { passwordRequest = .init(url:file) },apply: { document in
            await BackupCoordinator.restore(document,waypoints:waypoints,fieldData:field,settings:settings,lanes:lanes,boundaries:boundaries)
        },completion: { status = $0 })
    }
    private func finishPassword() {
        guard let (file,password) = pendingPassword else { return }
        pendingPassword = nil
        if let file { restore(file,password:password) } else { export(password:password) }
    }
}
