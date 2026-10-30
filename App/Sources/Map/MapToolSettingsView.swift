import SwiftUI
import GridFixCore

struct MapToolSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(MapTools.all,id: \.self) { key in
                        Toggle(MapTools.title(key),isOn: Binding(get: { !settings.hiddenMapTools.contains(key) },set: { shown in
                            if shown { settings.hiddenMapTools.remove(key) } else { settings.hiddenMapTools.insert(key) }
                        })).accessibilityIdentifier("map-tool-shown-"+key)
                    }
                }.listRowBackground(settings.nightMode ? Color.black : Color(white: 0.12))
                Section {
                    Button("Show all map buttons") { settings.hiddenMapTools = [] }.accessibilityIdentifier("map-tools-reset")
                }.listRowBackground(settings.nightMode ? Color.black : Color(white: 0.12))
            }.foregroundStyle(palette.ink).scrollContentBackground(.hidden).background(palette.background)
                .navigationTitle("Map buttons").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(palette.accent).fieldSheetAppearance()
    }
}
