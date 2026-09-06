import SwiftUI

struct RootView: View {
    @EnvironmentObject private var location: LocationService
    @State private var selection: Int

    init() {
        // CI cannot tap a tab bar, so the screenshot run picks the tab with a
        // launch argument instead of driving the UI. Order matches Android:
        // position=0, navigate=1, map=2, waypoints=3. Keep map=2 stable for CI.
        let args = ProcessInfo.processInfo.arguments
        let tab: Int
        if let idx = args.firstIndex(of: "-startTab"), args.index(after: idx) < args.endIndex {
            switch args[args.index(after: idx)] {
            case "navigate": tab = 1
            case "map": tab = 2
            case "waypoints": tab = 3
            default: tab = 0
            }
        } else {
            tab = 0
        }
        _selection = State(initialValue: tab)
    }

    var body: some View {
        Group {
            switch selection {
            case 1:
                NavigateView()
            case 2:
                MapScreen()
            case 3:
                WaypointsView()
            default:
                PositionView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Blackout.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FieldTabBar(selection: $selection)
        }
    }
}
