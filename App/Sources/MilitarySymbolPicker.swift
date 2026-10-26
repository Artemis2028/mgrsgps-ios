import GridFixCore
import SwiftUI

struct MilitarySymbolPicker: View {
    @Binding var symbol: String
    @Binding var affiliation: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @State private var category = 0
    @State private var search = ""
    private var palette: FieldPalette { .init(night: night) }
    private var entries: [MilitarySymbols.Entry] { category == 0 ? MilitarySymbols.functions : (category == 1 ? MilitarySymbols.tasks : MilitarySymbols.basic) }
    private var filtered: [MilitarySymbols.Entry] { entries.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.key.localizedCaseInsensitiveContains(search) } }
    private func key(_ entry: MilitarySymbols.Entry) -> String { category == 0 ? "nato_\(MilitarySymbols.affiliationCode(affiliation))_\(entry.key)" : entry.key }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Symbol category",selection: $category) {
                    Text("Units").tag(0); Text("Tasks").tag(1); Text("Basic").tag(2)
                }.pickerStyle(.segmented).accessibilityIdentifier("symbol-category")
                Picker("Affiliation",selection: $affiliation) {
                    ForEach(MilitarySymbols.affiliations.filter { category != 0 || $0.key != "none" || affiliation == "none" }) { Text($0.label).tag($0.key) }
                }.pickerStyle(.menu).accessibilityIdentifier("symbol-affiliation")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 95),spacing: 12)],spacing: 16) {
                    ForEach(filtered) { entry in
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to: nil,from: nil,for: nil)
                            symbol = key(entry)
                            if category == 0 && affiliation == "none" { affiliation = "friendly" }
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                MilitaryMarker(symbol: key(entry),affiliation: affiliation).frame(width: 52,height: 52)
                                Text(entry.label).font(.caption).multilineTextAlignment(.center).frame(minHeight: 32)
                            }.frame(maxWidth: .infinity).padding(8)
                                .background(symbol == key(entry) ? palette.accent.opacity(0.2) : Color.white.opacity(0.04),in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("symbol-\(entry.key)")
                    }
                }
            }.padding(16)
        }.background { FieldScreenBackground() }.foregroundStyle(palette.ink)
            .navigationTitle("Military symbols").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search,prompt: "Search symbol functions")
            .onAppear { category = symbol.hasPrefix("nato_") ? 0 : (symbol.hasPrefix("task_") ? 1 : 2) }
            .fieldSheetAppearance()
    }
}

struct ImportedMarkerEditor: View {
    @Binding var metadata: WaypointMetadata
    private var decoded: MilGpsSymbol? { MilGpsSymbols.decode(metadata.milgpsSymbolCode) }
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            Text("Imported marker").font(.headline)
            if metadata.milgpsSymbolCode != nil && decoded == nil { Text("Unsupported imported symbol code is kept until you choose a replacement.").font(.caption) }
            Picker("Marker color",selection: Binding(get: { metadata.color ?? "" },set: { metadata.color = $0.isEmpty ? nil : $0 })) {
                Text("Default").tag(""); ForEach(MilGpsSymbols.colors,id: \.self) { Text($0.capitalized).tag($0) }
            }
            Picker("Marker shape",selection: Binding(get: { decoded?.shape.rawValue ?? -1 },set: { raw in
                if let shape = MilGpsShape(rawValue: raw) { metadata.milgpsSymbolCode = MilGpsSymbols.encode(shape: shape,character: decoded?.character) }
            })) {
                Text("Choose").tag(-1); ForEach(MilGpsShape.allCases,id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            Picker("Marker character",selection: Binding(get: { decoded?.character ?? "" },set: { text in
                if let shape = decoded?.shape { metadata.milgpsSymbolCode = MilGpsSymbols.encode(shape: shape,character: text.isEmpty ? nil : text) }
            })) {
                Text("None").tag(""); ForEach(MilGpsSymbols.characters,id: \.self) { Text($0).tag($0) }
            }.disabled(decoded == nil || decoded?.shape == .cross)
            Button("Use MGRS GPS symbol appearance") { metadata.color = nil; metadata.milgpsSymbolCode = nil }
        }
    }
}
