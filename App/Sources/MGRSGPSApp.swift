import SwiftUI

@main
struct MGRSGPSApp: App {
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(location)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
