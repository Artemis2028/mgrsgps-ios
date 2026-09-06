import SwiftUI
import GridFixCore

@main
struct MGRSGPSApp: App {
    @StateObject private var location = LocationService()
    @StateObject private var waypoints = WaypointStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(location)
                .environmentObject(waypoints)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
