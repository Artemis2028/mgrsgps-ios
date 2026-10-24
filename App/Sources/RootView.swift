import SwiftUI
import GridFixCore

struct RootView: View {
    @EnvironmentObject private var waypointStore: WaypointStore
    @EnvironmentObject private var fieldStore: FieldDataStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var maps: MapLayerStore
    @EnvironmentObject private var terrain: TerrainSession
    @EnvironmentObject private var boundaries: BoundaryMonitor
    @EnvironmentObject private var practice: PracticeSession
    @EnvironmentObject private var navigation: NavigationSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Int
    @State private var showingRecorder = false
    @State private var incomingFile: URL?
    @State private var importRequest: TextImportRequest?
    @State private var importStatus: String?
    @State private var showingPractice = false

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
            if practice.locked || practice.summary != nil {
                Button { showingPractice = true } label: {
                    HStack { Image(systemName: "timer"); Text(practice.damaged ? "Saved course needs attention" : practice.summary != nil ? "Course complete · view results" : practice.active?.paused == true ? "Course paused · missing checkpoint" : "Practice course · CP \(min((practice.active?.nextIndex ?? 0)+1,practice.active?.waypointIDs.count ?? 0))"); Spacer(); Image(systemName: "chevron.right") }
                        .font(.caption).padding(.horizontal,16).frame(minHeight: 44)
                }.accessibilityIdentifier("practice-banner")
            }
            if let url = incomingFile {
                HStack {
                    Button { importRequest = TextImportRequest(url: url) } label: { Label("Review " + url.lastPathComponent,systemImage: "doc.badge.plus").lineLimit(1).frame(minHeight: 44) }
                    Spacer()
                    Button("Dismiss") { incomingFile = nil }.font(.caption)
                }.padding(.horizontal,16).accessibilityIdentifier("incoming-file-banner")
            }
            if let importStatus {
                HStack { Text(importStatus).font(.caption); Spacer(); Button("Done") { self.importStatus = nil } }.padding(.horizontal,16)
            }
            RecordingBanner(onOpen: { showingRecorder = true }).zIndex(1)
            if boundaries.running {
                Button { selection = 2 } label: {
                    HStack {
                        Image(systemName: "shield.lefthalf.filled")
                        Text(boundaries.activeArea?.name ?? "Boundary")
                        Spacer()
                        Text(boundaries.hasFreshFix ? boundaries.status : "Waiting for GPS")
                            .font(.caption).lineLimit(2)
                    }.padding(.horizontal,12).padding(.vertical,6)
                }.accessibilityIdentifier("boundary-monitor-banner")
            }
            if navigation.running || navigation.preparing {
                Button { selection = 1 } label: {
                    HStack {
                        Image(systemName: "location.north.line")
                        Text(navigation.progress?.name ?? "Haptic guide")
                        Spacer()
                        Text(navigation.status).font(.caption).lineLimit(2)
                    }.padding(.horizontal,12).padding(.vertical,6)
                }.accessibilityIdentifier("navigation-session-banner")
            }
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
                WaypointsView(onNavigate: { selection = 1 },onShowMap: { selection = 2 })
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
        .onOpenURL { url in
            if url.isFileURL { incomingFile = url; importStatus = nil }
        }
        .sheet(item: $importRequest) { request in
            InterchangeImportView(request: request,knownFolders: waypointStore.folders.map(\.name)) { document in
                let result = InterchangeCoordinator.apply(document,waypoints: waypointStore,field: fieldStore)
                importStatus = result.message
                if result.completed && incomingFile == request.url { incomingFile = nil }
                return result
            }
        }
        .sheet(isPresented: $showingPractice) { PracticeCourseView() }
        .sheet(isPresented: $showingRecorder) { TrackRecordingPanel() }
        .environment(\.fieldNight, settings.nightMode)
        .onAppear { practice.setForeground(scenePhase == .active); location.start(); UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn }
        .onChange(of: settings.keepScreenOn) { UIApplication.shared.isIdleTimerDisabled = $0 }
        .onChange(of: scenePhase) { phase in
            practice.setForeground(phase == .active)
            if phase == .active { location.start(); boundaries.becameActive(); navigation.foregroundChanged(true) }
            else if phase == .inactive { navigation.foregroundChanged(false) }
            else if phase == .background { location.stop(); maps.pauseDownload(); terrain.backgrounded() }
        }
        .onReceive(location.$usableFix) { practice.receive($0) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            location.refreshFixValidity(); boundaries.refresh(); practice.receive(location.usableFix)
        }
    }

}
