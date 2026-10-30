import GridFixCore
import SwiftUI

struct FieldChoice: Identifiable {
    let id: String
    let title: String
    var accessibilityIdentifier: String?
    var enabled = true
    var destructive = false
    var waypoint: Waypoint?
    var symbolDescription: String {
        guard let waypoint else { return "" }
        return WaypointMarkerDescription.text(waypoint)
    }
}

/// Native scrolling choices avoid nested menu presentation/activation races.
struct FieldChoiceSheet: View {
    let title: String
    let choices: [FieldChoice]
    var selectedID: String?
    let night: Bool
    let choose: (String) -> Void
    @State private var committed = false
    @Environment(\.dismiss) private var dismiss
    private var palette: FieldPalette { .init(night: night) }
    var body: some View {
        NavigationStack {
            List(choices) { choice in
                Button(role: choice.destructive ? .destructive : nil) {
                    guard !committed,choice.enabled else { return }
                    committed = true
                    choose(choice.id)
                } label: {
                    HStack {
                        if let point = choice.waypoint {
                            MilitaryMarker(symbol:point.symbol,affiliation:point.affiliation,echelon:point.echelon,
                                           rotation:point.rotation,metadata:point.metadata)
                                .frame(width:28,height:28).accessibilityHidden(true)
                        }
                        Text(choice.title)
                        Spacer()
                        if selectedID == choice.id { Image(systemName: "checkmark").foregroundStyle(palette.accent) }
                    }.foregroundStyle(choice.destructive ? palette.warn : palette.ink)
                        .frame(maxWidth: .infinity,minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(committed || !choice.enabled)
                    .accessibilityLabel(choice.title).accessibilityValue(choice.symbolDescription)
                    .accessibilityAddTraits(selectedID == choice.id ? .isSelected : [])
                    .accessibilityIdentifier(choice.accessibilityIdentifier ?? choice.id)
                    .listRowBackground(night ? Color.black : Color(white: 0.12))
            }.scrollContentBackground(.hidden).background(palette.background)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { guard !committed else { return }; committed = true; dismiss() }.disabled(committed) } }
        }.environment(\.fieldNight,night).tint(palette.accent).fieldSheetAppearance()
    }
}

struct FieldChoicePicker: View {
    @Binding var selection: String
    let title: String
    let choices: [FieldChoice]
    let identifier: String
    @Environment(\.fieldNight) private var night
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            HStack {
                Text(title); Spacer()
                Text(choices.first { $0.id == selection }?.title ?? "Choose")
                Image(systemName: "chevron.up.chevron.down")
            }.frame(maxWidth: .infinity,minHeight: 32).contentShape(Rectangle())
        }.accessibilityIdentifier(identifier)
        .sheet(isPresented: $showing) {
            FieldChoiceSheet(title: title,choices: choices,selectedID: selection,night: night) {
                selection = $0; showing = false
            }
        }
    }
}

enum LibraryAction: String, CaseIterable {
    case fix = "library-add-fix", coordinates = "library-enter-coordinates", select = "library-select", folder = "library-new-folder-action"
    case orientation = "library-orientation-shortcut", export = "library-export", backup = "library-import-backup", file = "import-field-file", paste = "library-paste"
    case recovery = "library-waypoint-recovery"
    var title: String {
        switch self {
        case .fix: return "Add at fix"
        case .coordinates: return "Enter coordinates"
        case .select: return "Select items"
        case .folder: return "New folder"
        case .orientation: return "Orientation"
        case .export: return "Export"
        case .backup: return "Import backup"
        case .file: return "Import field file"
        case .paste: return "Paste text"
        case .recovery: return "Waypoint file recovery"
        }
    }
}
