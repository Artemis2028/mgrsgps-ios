import SwiftUI

enum MapToolChoice: String, CaseIterable, Identifiable {
    case distance = "measure-distance", area = "measure-area", resection = "field-resection", intersection = "field-intersection"
    case sunMoon = "field-sunmoon", declination = "field-declination", sight = "field-los", course = "field-course", orientation = "field-orientation"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .distance: return "Distance ruler"
        case .area: return "Measure area"
        case .resection: return "Resection"
        case .intersection: return "Intersection"
        case .sunMoon: return "Sun & moon"
        case .declination: return "Declination diagram"
        case .sight: return "Line of sight"
        case .course: return "Practice course"
        case .orientation: return "Orientation"
        }
    }
}

struct FieldToolChooser: View {
    let night: Bool
    let choose: (MapToolChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    private var palette: FieldPalette { FieldPalette(night: night) }
    var body: some View {
        NavigationStack {
            List(MapToolChoice.allCases) { tool in
                Button(tool.title) { choose(tool) }
                    .foregroundStyle(palette.ink).frame(minHeight: 44)
                    .accessibilityIdentifier(tool.id)
                    .listRowBackground(night ? Color.black : Color(white: 0.12))
            }.scrollContentBackground(.hidden).background(palette.background)
                .navigationTitle("Map tools").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(palette.accent).fieldSheetAppearance()
    }
}

struct OrientationChooser: View {
    let current: Int
    let night: Bool
    let choose: (ScreenOrientation) -> Void
    @Environment(\.dismiss) private var dismiss
    private var palette: FieldPalette { FieldPalette(night: night) }
    var body: some View {
        NavigationStack {
            List(ScreenOrientation.allCases) { mode in
                Button { choose(mode) } label: {
                    HStack {
                        VStack(alignment: .leading,spacing: 5) {
                            Text(mode.title).font(.headline)
                            Text(mode.explanation).font(.footnote).foregroundStyle(palette.inkDim)
                        }
                        Spacer()
                        if mode.rawValue == current { Image(systemName: "checkmark").foregroundStyle(palette.accent) }
                    }.foregroundStyle(palette.ink).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("orientation-option-\(mode.rawValue)")
                    .accessibilityAddTraits(mode.rawValue == current ? .isSelected : [])
                    .listRowBackground(night ? Color.black : Color(white: 0.12))
            }.scrollContentBackground(.hidden).background(palette.background)
                .navigationTitle("Screen orientation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(palette.accent).fieldSheetAppearance()
    }
}
