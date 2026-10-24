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
    @StateObject private var boundaries: BoundaryMonitor

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
        _waypoints = StateObject(wrappedValue: WaypointStore(directory: directory))
        _settings = StateObject(wrappedValue: AppSettings(directory: directory))
        _maps = StateObject(wrappedValue: MapLayerStore(directory: directory))
        _boundaries = StateObject(wrappedValue: BoundaryMonitor(directory: directory))
        let fieldStore = FieldDataStore(directory: directory)
        _fieldData = StateObject(wrappedValue: fieldStore)
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
                .environmentObject(boundaries)
                .environment(\.fieldNight, settings.nightMode)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
