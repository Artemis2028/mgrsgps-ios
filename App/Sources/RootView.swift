import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var maps: MapLayerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Int
    @State private var showingRecorder = false

    init() {
        // The standalone screenshot script picks a tab with a launch argument;
        // the UI workflow tests also exercise normal tab interaction. Order matches Android:
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
        VStack(spacing: 0) {
            RecordingBanner(onOpen: { showingRecorder = true }).zIndex(1)
            TabView(selection: $selection) {
                PositionView()
                    .toolbar(settings.nightMode ? .hidden : .visible, for: .tabBar)
                    .tabItem { Label("Position", systemImage: "location.north.line") }.tag(0)
                NavigateView()
                    .toolbar(settings.nightMode ? .hidden : .visible, for: .tabBar)
                    .tabItem { Label("Navigate", systemImage: "safari") }.tag(1)
                MapScreen(onNavigate: { selection = 1 })
                    .toolbar(settings.nightMode ? .hidden : .visible, for: .tabBar)
                    .tabItem { Label("Map", systemImage: "map") }.tag(2)
                WaypointsView(onNavigate: { selection = 1 })
                    .toolbar(settings.nightMode ? .hidden : .visible, for: .tabBar)
                    .tabItem { Label("Waypoints", systemImage: "flag") }.tag(3)
            }
        }
        // Keep the content hierarchy alive when night mode changes, including
        // an open Settings/editor sheet. Only the navigation chrome changes.
        .tint(settings.nightMode ? FieldPalette(night: true).accent : Blackout.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if settings.nightMode { FieldTabBar(selection: $selection) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Blackout.background.ignoresSafeArea())
        .sheet(isPresented: $showingRecorder) { TrackRecordingPanel() }
        .environment(\.fieldNight, settings.nightMode)
        .onAppear { location.start(); UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn }
        .onChange(of: settings.keepScreenOn) { UIApplication.shared.isIdleTimerDisabled = $0 }
        .onChange(of: scenePhase) { phase in
            if phase == .active { location.start() }
            else if phase == .background { location.stop(); maps.pauseDownload() }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            location.refreshFixValidity()
        }
    }

}
