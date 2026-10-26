import SwiftUI
import GridFixCore

@main
struct MGRSGPSApp: App {
    @UIApplicationDelegateAdaptor(FieldAppDelegate.self) private var appDelegate
    @StateObject private var location = LocationService()
    @StateObject private var waypoints: WaypointStore
    @StateObject private var settings: AppSettings
    @StateObject private var fieldData: FieldDataStore
    @StateObject private var recorder: TrackRecorder
    @StateObject private var maps: MapLayerStore
    @StateObject private var terrain: TerrainSession
    @StateObject private var boundaries: BoundaryMonitor
    @StateObject private var navigation: NavigationSession
    @StateObject private var lanes: NavigationLaneStore

    @StateObject private var liveActivities: LiveActivityManager
    @StateObject private var tak: TAKSession
    @StateObject private var practice: PracticeSession

    private let watchBridge: WatchPhoneBridge

    init() {
        var directory: URL?
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            // UI automation uses its own store and never wipes field data.
            let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("mgrsgps-ui-tests", isDirectory: true)
            if !ProcessInfo.processInfo.arguments.contains("-keepUITestData") {
                try? FileManager.default.removeItem(at: testDirectory)
            }
            try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
            directory = testDirectory
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestWaypointRecovery"),
           !ProcessInfo.processInfo.arguments.contains("-keepUITestData"), let directory {
            try? Data("SYNTHETIC unreadable CAFÉ waypoint library\n".utf8).write(to: directory.appendingPathComponent("waypoints-v1.json"), options: .atomic)
        }
        #endif
        let waypointStore = WaypointStore(directory: directory)
        let settingsStore = AppSettings(directory: directory)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestWaypointRecoveryNight") { settingsStore.nightMode = true }
        if OfflineDownloadValidation.enabled, ProcessInfo.processInfo.arguments.contains("-uiTestOfflineDownloadNight") { settingsStore.nightMode = true }
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestTAKEnrollmentNight") { settingsStore.nightMode = true }
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestWaypointWriteFailure") {
            if ProcessInfo.processInfo.arguments.contains("-uiTestWaypointWriteFailureNight") { settingsStore.nightMode = true }
            if !ProcessInfo.processInfo.arguments.contains("-keepUITestData"), let directory {
                try? FileManager.default.createDirectory(at: directory.appendingPathComponent("waypoints-v1.json"),withIntermediateDirectories: false)
            }
        }
        #endif
        OrientationState.shared.prepare(settingsStore.orientation)
        #if DEBUG
        WatchPhoneBridge.seedUITest(store: waypointStore, settings: settingsStore)
        #endif
        _waypoints = StateObject(wrappedValue: waypointStore)
        _settings = StateObject(wrappedValue: settingsStore)
        let mapStore: MapLayerStore
        #if DEBUG
        if OfflineDownloadValidation.enabled, let directory { mapStore = OfflineDownloadValidation.makeStore(directory: directory) }
        else { mapStore = MapLayerStore(directory: directory) }
        #else
        mapStore = MapLayerStore(directory: directory)
        #endif
        _maps = StateObject(wrappedValue: mapStore)
        _terrain = StateObject(wrappedValue: TerrainSession(sampler: mapStore.terrainSampler))
        let boundaryStore = BoundaryMonitor(directory: directory)
        _boundaries = StateObject(wrappedValue: boundaryStore)
        let fieldStore = FieldDataStore(directory: directory)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestTAKSharing") {
            if !waypointStore.waypoints.contains(where: { $0.name == "IOS OP CAFÉ" }) {
                _ = waypointStore.add(.init(name: "IOS OP CAFÉ", lat: 35.1388, lon: -78.9914, folder: "TAK INTEROP", affiliation: "hostile"))
            }
            if !fieldStore.document.graphics.contains(where: { $0.id == "ios-interop-area" }) {
                try? fieldStore.saveGraphic(.init(id: "ios-interop-area", name: "IOS TEST AREA", type: "objective", points: [
                    .init(lat: 35.1392, lon: -78.9908), .init(lat: 35.1392, lon: -78.9900),
                    .init(lat: 35.1386, lon: -78.9900), .init(lat: 35.1386, lon: -78.9908)
                ], folder: "TAK INTEROP"))
            }
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"),ProcessInfo.processInfo.arguments.contains("-uiTestLasso") {
            if ProcessInfo.processInfo.arguments.contains("-uiTestLassoNight") { settingsStore.nightMode = true }
            if !ProcessInfo.processInfo.arguments.contains("-keepUITestData") {
                _ = waypointStore.add(.init(name: "Lasso Alpha",lat: 24.4539,lon: 54.3773))
                _ = waypointStore.add(.init(name: "Lasso Bravo",lat: 24.4538,lon: 54.3774))
                _ = waypointStore.add(.init(name: "Lasso hidden folder",lat: 24.4539,lon: 54.3773,folder: "Hidden"))
                try? waypointStore.setLibraryFolderVisible("Hidden",visible: false)
                try? fieldStore.saveGraphic(.init(id: "lasso-line",name: "Lasso line",type: "phase_line",points: [.init(lat: 24.4538,lon: 54.3772),.init(lat: 24.4540,lon: 54.3774)]))
            }
        }
        #endif
        let takSession = TAKSession(directory: directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0], waypoints: waypointStore, field: fieldStore)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestTAKPreview") { takSession.seedMapPreview() }
        #endif
        #if DEBUG
        let takWatchArgs = ProcessInfo.processInfo.arguments
        if takWatchArgs.contains("-uiTesting"),takWatchArgs.contains("-uiTestWatchTAK") {
            takSession.seedWatchPreview(hidden:takWatchArgs.contains("-uiTestWatchTAKHidden"),cleared:takWatchArgs.contains("-uiTestWatchTAKClear"),expiry:takWatchArgs.contains("-uiTestWatchTAKExpiry"))
        }
        #endif
        _tak = StateObject(wrappedValue: takSession)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestLibrary"),
           !ProcessInfo.processInfo.arguments.contains("-keepUITestData"), waypointStore.waypoints.isEmpty, fieldStore.document.graphics.isEmpty {
            _ = waypointStore.add(.init(name: "Alpha",lat: 24.4539,lon: 54.3773))
            let hidden = waypointStore.add(.init(name: "Bravo",lat: 24.4542,lon: 54.3775,folder: "Recon"))
            waypointStore.setVisible(id: hidden.id,visible: false)
            _ = waypointStore.add(.init(name: "Charlie",lat: 24.455,lon: 54.379))
            var fixture = Backup.Document(); fixture.hasSettings = false
            fixture.graphics = [
                .init(id: "library-route",name: "Recon route",type: "route",points: [.init(lat: 24.4539,lon: 54.3773),.init(lat: 24.455,lon: 54.379)],folder: "Recon"),
                .init(id: "library-checkpoint",name: "Base checkpoint",type: "checkpoint",points: [.init(lat: 24.4539,lon: 54.3773)],visible: false)
            ]
            if let (track,bytes) = try? TrackCodec.imported(name: "Recon track",points: [.init(lat: 24.4539,lon: 54.3773),.init(lat: 24.455,lon: 54.379)],now: 1000,folder: "Recon") {
                fixture.tracks = [track]; fixture.trackFiles[track.id] = bytes
            }
            _ = try? fieldStore.restore(fixture)
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestTargetSelection"),
           !ProcessInfo.processInfo.arguments.contains("-keepUITestData") {
            if let initial = waypointStore.waypoints.first { waypointStore.select(initial.id) }
            _ = waypointStore.add(.init(name: "Selection target",lat: 24.456,lon: 54.376))
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestLibraryWriteFailure"),
           !ProcessInfo.processInfo.arguments.contains("-keepUITestData"), let directory {
            // The valid in-memory test library remains available; only its next
            // publication is blocked. Never operates on production storage.
            let file = directory.appendingPathComponent("waypoints-v1.json")
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
            if ProcessInfo.processInfo.arguments.contains("-uiTestLibraryWriteFailureNight") { settingsStore.nightMode = true }
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestLargeLibrary"),
           !ProcessInfo.processInfo.arguments.contains("-keepUITestData"), waypointStore.waypoints.isEmpty {
            // Real stores and production listing; no synthetic UI result path.
            let folders = (0..<100).map { FolderInfo(name: String(format: "Folder %03d",$0)) }
            var points: [Waypoint] = []
            for i in 0..<5000 {
                points.append(.init(id: "large-point-\(i)",name: String(format: "Point %04d",i),lat: 24.4539+Double(i%100)*0.0001,lon: 54.3773+Double(i/100)*0.0001,createdAt: Int64(i),folder: folders[i%100].name,favorite: i == 4999))
            }
            try? waypointStore.restore(waypoints: points,folders: folders)
            var fixture = Backup.Document(); fixture.hasSettings = false
            fixture.graphics = (0..<1000).map { i in
                .init(id: "large-route-\(i)",name: String(format: "Route %04d",i),type: "route",points: [.init(lat: 24.4539,lon: 54.3773),.init(lat: 24.455,lon: 54.379)],folder: folders[i%100].name)
            }
            _ = try? fieldStore.restore(fixture)
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") && (ProcessInfo.processInfo.arguments.contains("-uiTestTerrain") || ProcessInfo.processInfo.arguments.contains("-uiTestTerrainNoData")), waypointStore.waypoints.isEmpty {
            _ = waypointStore.add(.init(name: "West observer",lat: 24.4539,lon: 54.3773))
            _ = waypointStore.add(.init(name: "East target",lat: 24.4539,lon: 54.3923))
            try? fieldStore.saveGraphic(.init(id: "terrain-ui-route",name: "Terrain patrol",type: "route",points: [.init(lat: 24.4539,lon: 54.3773),.init(lat: 24.4539,lon: 54.3923)]))
        }
        #endif
        #if DEBUG
        WatchPhoneBridge.seedMapUITest(store: waypointStore, field: fieldStore, boundaries: boundaryStore)
        #endif
        let laneStore = NavigationLaneStore(directory: directory)
        _lanes = StateObject(wrappedValue: laneStore)
        #if DEBUG
        let watchArgs = ProcessInfo.processInfo.arguments
        if watchArgs.contains("-uiTesting"),watchArgs.contains("-uiTestWatchMapLanes"),!watchArgs.contains("-uiTestWatchMapClear") {
            func p(_ x: Double,_ y: Double) -> GeoPoint { .init(lat:24.4539+y/111195,lon:54.3773+x/(111195*cos(24.4539 * .pi/180))) }
            let fixture = NavLane(id:"watch-lane",name:"SYNTHETIC LANE",left:.init(points:[p(-60,-200),p(-60,200),p(-90,320)],label:"Creek"),right:.init(points:[p(60,-200),p(60,320)],label:"Road"),backstop:.init(points:[p(-120,340),p(0,360),p(120,340)],label:"Power line"),scope:.checkpoint,targetId:"watch-objective")
            Task { _ = try? await laneStore.restore([fixture]) }
        }
        #endif
        _fieldData = StateObject(wrappedValue: fieldStore)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestPractice"), waypointStore.waypoints.isEmpty {
            let far = ProcessInfo.processInfo.arguments.contains("-uiTestPracticeFar")
            _ = waypointStore.add(.init(name: "Alpha checkpoint",lat: far ? 25 : 24.4539,lon: 54.3773,folder: "Drill"))
            _ = waypointStore.add(.init(name: "Bravo checkpoint",lat: far ? 25.01 : 24.4550,lon: 54.3773,folder: "Drill"))
            _ = waypointStore.add(.init(name: "Unrelated target",lat: 24.5,lon: 54.4))
            if ProcessInfo.processInfo.arguments.contains("-uiTestPracticeNight") { settingsStore.nightMode = true }
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"),ProcessInfo.processInfo.arguments.contains("-uiTestLanes"),waypointStore.waypoints.isEmpty {
            func point(_ x: Double,_ y: Double) -> GeoPoint { .init(lat: 24.4539+y/111195,lon: 54.3773+x/(111195*cos(24.4539 * .pi/180))) }
            let target = point(0,450)
            _ = waypointStore.add(.init(name: "Lane OBJ",lat: target.lat,lon: target.lon))
            if ProcessInfo.processInfo.arguments.contains("-uiTestLaneInvalidObjective") {
                let backstop=point(0,520)
                _=waypointStore.add(.init(name:"Checkpoint on backstop",lat:backstop.lat,lon:backstop.lon))
            }
            for (id,name,points) in [("lane-left","Creek bank",[point(-50,0),point(-50,500)]),("lane-right","Right road",[point(50,0),point(50,500)]),("lane-backstop","Power line",[point(-100,520),point(100,520)])] {
                try? fieldStore.saveGraphic(.init(id: id,name: name,type: "phase_line",points: points.map { .init(lat: $0.lat,lon: $0.lon) }))
            }
            try? fieldStore.saveGraphic(.init(id: "lane-route",name: "Lane patrol",type: "route",points: [point(0,0),point(0,300),point(0,500)].map { .init(lat: $0.lat,lon: $0.lon) }))
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting"),ProcessInfo.processInfo.arguments.contains("-uiTestWatchGuide"),!ProcessInfo.processInfo.arguments.contains("-keepUITestData") {
            func p(_ x:Double,_ y:Double) -> GeoPoint { .init(lat:24.4539+y/111195,lon:54.3773+x/(111195*cos(24.4539 * .pi/180))) }
            let point = p(0,450)
            let target = waypointStore.add(.init(name:"SYNTHETIC GUIDE",lat:point.lat,lon:point.lon)); waypointStore.select(target.id)
            let fixture = NavLane(id:"watch-guide-lane",name:"SYNTHETIC CREEK",left:.init(points:[p(-50,-200),p(-50,500)],label:"Creek bank"),right:.init(points:[p(50,-200),p(50,500)],label:"Road"),backstop:.init(points:[p(-100,520),p(100,520)],label:"Power line"),scope:.checkpoint,targetId:target.id)
            Task { _ = try? await laneStore.save(fixture,graphics:fieldStore.document.graphics) }
        }
        #endif
        let navigationSession = NavigationSession(directory: directory,store: waypointStore,field: fieldStore,settings: settingsStore,lanes: laneStore)
        _navigation = StateObject(wrappedValue: navigationSession)
        watchBridge = WatchPhoneBridge(store: waypointStore, settings: settingsStore, field: fieldStore, boundaries: boundaryStore,lanes: laneStore,navigation: navigationSession,tak: takSession)
        _practice = StateObject(wrappedValue: PracticeSession(directory: directory,waypoints: waypointStore,field: fieldStore,navigation: navigationSession))
        let recordingSession = TrackRecorder(directory: directory, fieldData: fieldStore)
        _recorder = StateObject(wrappedValue: recordingSession)
        _liveActivities = StateObject(wrappedValue: LiveActivityManager(recorder:recordingSession,navigation:navigationSession,settings:settingsStore))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(location)
                .environmentObject(waypoints)
                .environmentObject(settings)
                .environmentObject(fieldData)
                .environmentObject(recorder)
                .environmentObject(maps)
                .environmentObject(terrain)
                .environmentObject(boundaries)
                .environmentObject(navigation)
                .environmentObject(lanes)
                .environmentObject(practice)
                .environmentObject(liveActivities)
                .environmentObject(tak)
                .environment(\.fieldNight, settings.nightMode)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
