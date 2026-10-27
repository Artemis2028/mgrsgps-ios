import SwiftUI

enum MapAccessibleAction: String, Identifiable {
    case details, layers, lanes, graphics, boundaries, tools, terrain, ruler, goTo, buttons, night, locate, fit, record, add, tak
    var id: String { rawValue }
}
struct MapAccessibleChoice: Identifiable {
    let action: MapAccessibleAction
    let title: String
    let symbol: String
    var enabled = true
    var id: String { action.id }
}

/// Large text lives in a native scrollable list, rather than a fixed icon grid.
struct MapAccessibleActions: View {
    let choices: [MapAccessibleChoice]
    let choose: (MapAccessibleAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    private var palette: FieldPalette { .init(night:night) }
    var body: some View {
        NavigationStack {
            List(choices) { item in
                Button { choose(item.action) } label: {
                    HStack(alignment:.firstTextBaseline,spacing:12) {
                        Image(systemName:item.symbol).font(.system(size:22)).frame(width:28)
                        Text(item.title).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                }.foregroundStyle(palette.ink).disabled(!item.enabled)
                    .accessibilityIdentifier("map-action-"+item.id)
                    .listRowBackground(night ? Color.black : Color(white:0.12))
            }.scrollContentBackground(.hidden).background(palette.background)
                .navigationTitle("Map actions").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.principal) { Text("Map actions").font(.headline).foregroundStyle(palette.ink) }
                    ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(palette.accent) }
                }
        }.tint(palette.accent).fieldSheetAppearance()
    }
}
