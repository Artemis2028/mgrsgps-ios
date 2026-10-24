import SwiftUI
import GridFixCore

@main
struct MGRSGPSApp: App {
    @StateObject private var location = LocationService()
    @StateObject private var waypoints: WaypointStore
    @StateObject private var settings: AppSettings
    @StateObject private var fieldData: FieldDataStore
    @StateObject private var recorder: TrackRecorder
    @StateObject private var maps: MapLayerStore
    @StateObject private var terrain: TerrainSession
    @StateObject private var boundaries: BoundaryMonitor
    @StateObject private var navigation: NavigationSession

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
        let waypointStore = WaypointStore(directory: directory)
        let settingsStore = AppSettings(directory: directory)
        _waypoints = StateObject(wrappedValue: waypointStore)
        _settings = StateObject(wrappedValue: settingsStore)
        let mapStore = MapLayerStore(directory: directory)
        _maps = StateObject(wrappedValue: mapStore)
        _terrain = StateObject(wrappedValue: TerrainSession(sampler: mapStore.terrainSampler))
        _boundaries = StateObject(wrappedValue: BoundaryMonitor(directory: directory))
        let fieldStore = FieldDataStore(directory: directory)
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
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") && (ProcessInfo.processInfo.arguments.contains("-uiTestTerrain") || ProcessInfo.processInfo.arguments.contains("-uiTestTerrainNoData")), waypointStore.waypoints.isEmpty {
            _ = waypointStore.add(.init(name: "West observer",lat: 24.4539,lon: 54.3773))
            _ = waypointStore.add(.init(name: "East target",lat: 24.4539,lon: 54.3923))
            try? fieldStore.saveGraphic(.init(id: "terrain-ui-route",name: "Terrain patrol",type: "route",points: [.init(lat: 24.4539,lon: 54.3773),.init(lat: 24.4539,lon: 54.3923)]))
        }
        #endif
        _fieldData = StateObject(wrappedValue: fieldStore)
        _navigation = StateObject(wrappedValue: NavigationSession(directory: directory,store: waypointStore,field: fieldStore,settings: settingsStore))
        _recorder = StateObject(wrappedValue: TrackRecorder(directory: directory, fieldData: fieldStore))
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
                .environment(\.fieldNight, settings.nightMode)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
