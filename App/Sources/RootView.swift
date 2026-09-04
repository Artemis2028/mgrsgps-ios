import SwiftUI

struct RootView: View {
    @EnvironmentObject private var location: LocationService
    @State private var selection: Int

    init() {
        // CI cannot tap a tab bar, so the screenshot run picks the tab with a
        // launch argument instead of driving the UI.
        let wantsMap = ProcessInfo.processInfo.arguments.contains("-startTab")
            && ProcessInfo.processInfo.arguments.contains("map")
        _selection = State(initialValue: wantsMap ? 1 : 0)
    }

    var body: some View {
        TabView(selection: $selection) {
            PositionView()
                .tabItem { Label("Position", systemImage: "location.north.line") }
                .tag(0)
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)
        }
        .tint(Blackout.accent)
    }
}
