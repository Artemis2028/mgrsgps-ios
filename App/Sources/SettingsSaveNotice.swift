import SwiftUI

/// A failed disk write must remain visible outside the settings sheet too:
/// map/night shortcuts and watch preferences can change these same values.
struct SettingsSaveNotice: View {
    @EnvironmentObject private var settings: AppSettings
    let identifier: String
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    var body: some View {
        if let error = settings.saveError {
            VStack(alignment: .leading,spacing: 6) {
                Text(error).font(.footnote).foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false,vertical: true).accessibilityIdentifier(identifier)
                Button(settings.saving ? "Saving…" : "Retry saving settings") { settings.retryPersistence() }
                    .disabled(settings.saving).frame(minHeight: 44).tint(palette.accent)
                    .accessibilityIdentifier(identifier + "-retry")
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uiTesting"),ProcessInfo.processInfo.arguments.contains("-uiTestSettingsWriteFailure") {
                    Button("Restore test write access") { settings.restoreWriteAccessForUITest() }
                        .frame(minHeight: 44).accessibilityIdentifier(identifier + "-test-repair")
                }
                #endif
            }.frame(maxWidth: .infinity,alignment: .leading).padding(12)
                .background(palette.background).overlay { RoundedRectangle(cornerRadius: 12).stroke(palette.warn) }
                .padding(.horizontal,12)
        }
    }
}
