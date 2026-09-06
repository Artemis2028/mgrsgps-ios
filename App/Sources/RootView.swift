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
        VStack(spacing: 0) {
            Group {
                switch selection {
                case 1:
                    MapScreen()
                case 2:
                    WaypointsView()
                default:
                    PositionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FieldTabBar(selection: $selection)
        }
        .background(Blackout.background.ignoresSafeArea())
    }
}
