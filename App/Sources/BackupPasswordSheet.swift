import SwiftUI
import GridFixCore
import UniformTypeIdentifiers

struct BackupPasswordRequest: Identifiable {
    let id = UUID()
    let url: URL?
    var exportRequest: FieldExportRequest?
}

struct BackupPasswordSheet: View {
    let exporting: Bool
    var interchange = false
    let submit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @State private var password = ""
    @State private var confirmation = ""
    @FocusState private var focused: Field?
    private enum Field { case password, confirmation }
    private var palette: FieldPalette { .init(night: night) }
    private var title: String { exporting ? (interchange ? "Protect export" : "Protect backup") : "Unlock backup" }
    private var valid: Bool {
        exporting ? password.utf16.count >= BackupCrypto.minimumPasswordLength && password.utf8.elementsEqual(confirmation.utf8) : !password.isEmpty
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading,spacing: 8) {
                        Text("Password").font(.caption)
                        SecureField("Password",text: $password)
                            .foregroundStyle(palette.ink)
                            .textContentType(exporting ? .newPassword : .password)
                            .focused($focused,equals: .password).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("backup-password")
                    }
                    if exporting {
                        VStack(alignment: .leading,spacing: 8) {
                            Text("Confirm password").font(.caption)
                            SecureField("Confirm password",text: $confirmation).textContentType(.newPassword)
                                .foregroundStyle(palette.ink)
                                .focused($focused,equals: .confirmation).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("backup-password-confirmation")
                        }
                    }
                } footer: {
                    Text(exporting ? "Use at least 8 characters. Keep the password somewhere safe; a forgotten password cannot be recovered." : "Enter the password used when this file was created. Nothing is added until the file is unlocked and checked.")
                }.listRowBackground(night ? Color.black : Color(white: 0.12))
                Section {
                    Button(exporting ? (interchange ? "Create protected file" : "Create protected backup") : "Unlock and restore") {
                        guard valid else { return }
                        let value = password; password = ""; confirmation = ""; submit(value)
                    }.disabled(!valid).frame(minHeight: 44).accessibilityIdentifier("backup-password-submit")
                }.listRowBackground(night ? Color.black : Color(white: 0.12))
            }.foregroundStyle(palette.ink).scrollContentBackground(.hidden).background(palette.background)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text(title).font(.headline).foregroundStyle(palette.ink) }
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { password = ""; confirmation = ""; dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil }.accessibilityIdentifier("backup-password-keyboard-done") }
                }
        }.tint(palette.accent).fieldSheetAppearance()
            .onDisappear { password = ""; confirmation = "" }
    }
}

extension UTType {
    static let gridFixProtectedBackup = UTType(exportedAs: "app.gridfix.protected-backup",conformingTo: .data)
}
