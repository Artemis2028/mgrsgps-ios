import GridFixCore
import SwiftUI
import UIKit

struct MilitaryMarker: View {
    let symbol: String
    var affiliation = "none"
    var echelon = ""
    var rotation = 0.0
    var metadata = WaypointMetadata()
    @Environment(\.fieldNight) private var night
    var body: some View { Image(uiImage: MilitaryMarkerRenderer.image(symbol: symbol,affiliation: affiliation,echelon: echelon,rotation: rotation,night: night,metadata: metadata)).resizable().scaledToFit().accessibilityLabel(MilitarySymbols.label(symbol)) }
}
