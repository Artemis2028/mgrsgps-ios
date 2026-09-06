import SwiftUI

struct RootView: View {
    @EnvironmentObject private var location: LocationService
    @State private var selection: Int

    init() {
        // CI cannot tap a tab bar, so the screenshot run picks the tab with a
        // launch argument instead of driving the UI. Keep position=0 and map=1
        // stable so existing simulator-shots keep working.
        let args = ProcessInfo.processInfo.arguments
        let tab: Int
        if let idx = args.firstIndex(of: "-startTab"), args.index(after: idx) < args.endIndex {
            switch args[args.index(after: idx)] {
            case "map": tab = 1
            case "waypoints": tab = 2
            default: tab = 0
            }
        } else {
            tab = 0
        }
        _selection = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $selection) {
            PositionView()
                .tabItem { Label("Position", systemImage: "location.north.line") }
                .tag(0)
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)
            WaypointsView()
                .tabItem { Label("Waypoints", systemImage: "flag") }
                .tag(2)
        }
        .tint(Blackout.accent)
    }
}
