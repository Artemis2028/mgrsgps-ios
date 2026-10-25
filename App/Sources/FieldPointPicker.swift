import GridFixCore
import SwiftUI

struct FieldPointChoice: Identifiable {
    let id: String
    let name: String
    var coordinate: GeoPoint?
}

/// A native searchable sheet avoids ambiguous popup activation points and keeps
/// long waypoint libraries usable without changing navigation selection.
struct FieldPointPicker: View {
    @Binding var selection: String
    let choices: [FieldPointChoice]
    let title: String
    let identifier: String
    let choicePrefix: String
    var labelPrefix = ""
    var prompt = "Choose point"
    var onOpen: () -> Void = {}
    @Environment(\.fieldNight) private var night
    @State private var showing = false
    @State private var search = ""
    private var palette: FieldPalette { FieldPalette(night: night) }
    private var filtered: [FieldPointChoice] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? choices : choices.filter { $0.name.localizedStandardContains(query) }
    }
    var body: some View {
        Button {
            onOpen(); search = ""; showing = true
        } label: {
            HStack {
                Text(labelPrefix + (choices.first { $0.id == selection }?.name ?? prompt))
                Spacer(); Image(systemName: "chevron.up.chevron.down")
            }.frame(minHeight: 32).contentShape(Rectangle())
        }.accessibilityIdentifier(identifier)
        .sheet(isPresented: $showing) {
            NavigationStack {
                List {
                    ForEach(filtered) { point in
                        Button {
                            selection = point.id; showing = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading,spacing: 5) {
                                    Text(point.name).font(.headline)
                                    if let coordinate = point.coordinate {
                                        Text(MGRS.parts(lat: coordinate.lat,lon: coordinate.lon,digits: 8)?.full ?? Format.latLon(lat: coordinate.lat,lon: coordinate.lon,format: .decimalDegrees))
                                            .font(.system(.caption,design: .monospaced)).foregroundStyle(palette.inkDim)
                                    }
                                }
                                Spacer()
                                if point.id == selection { Image(systemName: "checkmark").foregroundStyle(palette.accent) }
                            }.foregroundStyle(palette.ink).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier(choicePrefix + point.name)
                            .accessibilityAddTraits(point.id == selection ? .isSelected : [])
                            .listRowBackground(night ? Color.black : Color(white: 0.12))
                    }
                    if filtered.isEmpty { Text("No matching points").foregroundStyle(palette.inkDim) }
                }
                .scrollContentBackground(.hidden).background(palette.background)
                .searchable(text: $search,prompt: "Search points")
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showing = false }.accessibilityIdentifier(identifier + "-cancel") } }
            }.tint(palette.accent).fieldSheetAppearance()
        }
    }
}
