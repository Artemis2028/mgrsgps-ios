import Foundation
import GridFixCore
import SwiftUI

struct FieldLaunchConfiguration {
    let directory: URL?
    let seedFixtures: Bool
    let holdsForUITest: Bool

    static func current() -> Self {
        var directory: URL?
        var seed = false,hold = false
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTesting") {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mgrsgps-ui-tests",isDirectory: true)
            if !args.contains("-keepUITestData") { try? FileManager.default.removeItem(at: temporary) }
            try? FileManager.default.createDirectory(at: temporary,withIntermediateDirectories: true)
            if args.contains("-uiTestFieldReadRecovery"),!args.contains("-keepUITestData") {
                FieldLibraryReadValidation.seed(in: temporary)
            }
            directory = temporary
            if args.contains("-uiTestHoldMapGeometry") { try? Data().write(to: temporary.appendingPathComponent("hold-map-geometry")) }
            if args.contains("-uiTestWaypointRecovery"),!args.contains("-keepUITestData") {
                try? Data("SYNTHETIC unreadable CAFÉ waypoint library\n".utf8).write(to: temporary.appendingPathComponent("waypoints-v1.json"),options: .atomic)
            }
            if args.contains("-uiTestPracticeDamage"),!args.contains("-keepUITestData") {
                try? Data("SYNTHETIC damaged CAFÉ course\n".utf8).write(to: temporary.appendingPathComponent("practice-course-v1.json"),options: .atomic)
            }
            hold = args.contains("-uiTestSlowWaypointStartup")
            seed = !args.contains("-uiTestDeferredFieldLoad") && !hold
        }
        #endif
        return .init(directory: directory,seedFixtures: seed,holdsForUITest: hold)
    }
}

@MainActor
final class FieldAppStartup: ObservableObject {
    @Published private(set) var stores: FieldAppStores?
    @Published private(set) var error: String?
    @Published private(set) var pendingURLs: [URL] = []
    let holdsForUITest: Bool
    private let configuration: FieldLaunchConfiguration
    private let prepare: @Sendable (URL?) throws -> WaypointStore.PreparedStartup
    private struct PreparedWorkspace: Sendable {
        let settings: AppSettings.PreparedStartup
        let waypoints: WaypointStore.PreparedStartup
        let maps: MapLayerStore.PreparedStartup
        let course: PracticeCourseStore.PreparedStartup
        let navigation: NavigationSession.PreparedStartup
        let boundaries: BoundaryMonitor.PreparedStartup
        let tak: TAKLocalStore.PreparedStartup
    }
    private var worker: Task<PreparedWorkspace,Error>?
    private var generation = UUID()
    private let prepareMaps: @Sendable (URL?) -> MapLayerStore.PreparedStartup
    private let prepareSettings: @Sendable (URL?) -> AppSettings.PreparedStartup
    private let prepareBoundaries: @Sendable (URL?) -> BoundaryMonitor.PreparedStartup
    private let prepareTAK: @Sendable (URL) -> TAKLocalStore.PreparedStartup

    init(configuration: FieldLaunchConfiguration = .current(),
         prepare: @escaping @Sendable (URL?) throws -> WaypointStore.PreparedStartup = { try WaypointStore.prepareStartup(directory: $0) },
         prepareMaps: @escaping @Sendable (URL?) -> MapLayerStore.PreparedStartup = { MapLayerStore.prepareStartup(directory: $0) },
         prepareSettings: @escaping @Sendable (URL?) -> AppSettings.PreparedStartup = { AppSettings.prepareStartup(directory: $0) },
         prepareBoundaries: @escaping @Sendable (URL?) -> BoundaryMonitor.PreparedStartup = { BoundaryMonitor.prepareStartup(directory: $0) },
         prepareTAK: @escaping @Sendable (URL) -> TAKLocalStore.PreparedStartup = { TAKLocalStore.prepareStartup(root: $0) }) {
        self.configuration = configuration; self.prepare = prepare; self.prepareMaps = prepareMaps
        self.prepareSettings = prepareSettings
        self.prepareBoundaries = prepareBoundaries
        self.prepareTAK = prepareTAK
        holdsForUITest = configuration.holdsForUITest
        // Existing UI fixture setup stays synchronous. Normal launches and the
        // explicit cold-launch fixtures exercise the worker path below.
        if configuration.seedFixtures {
            let settings = AppSettings(directory: configuration.directory)
            stores = FieldAppStores(directory: configuration.directory,waypointStore: WaypointStore(directory: configuration.directory),settingsStore: settings,seedFixtures: true)
        }
    }

    func enqueue(_ url: URL) { pendingURLs.append(url) }

    func load() async {
        guard stores == nil else { return }
        error = nil
        var changedError: Error = WaypointStore.StartupFailure.changed
        for _ in 0..<3 {
            let task: Task<PreparedWorkspace,Error>,token: UUID
            if let worker { task = worker; token = generation }
            else {
                let operation = prepare,mapOperation = prepareMaps,settingsOperation = prepareSettings,boundaryOperation = prepareBoundaries,takOperation = prepareTAK,directory = configuration.directory
                generation = UUID(); token = generation
                task = Task.detached(priority: .userInitiated) {
                    let settings = settingsOperation(directory)
                    try Task.checkCancellation()
                    let waypoints = try operation(directory)
                    try Task.checkCancellation()
                    let maps = mapOperation(directory)
                    try Task.checkCancellation()
                    let courseDirectory = directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!
                    let course = try PracticeCourseStore.prepareStartup(directory: courseDirectory)
                    let navigation = NavigationSession.prepareStartup(directory: directory)
                    try Task.checkCancellation()
                    let boundaries = boundaryOperation(directory)
                    try Task.checkCancellation()
                    let tak = takOperation(directory ?? FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0])
                    try Task.checkCancellation()
                    return PreparedWorkspace(settings: settings,waypoints: waypoints,maps: maps,course: course,navigation: navigation,boundaries: boundaries,tak: tak)
                }
                worker = task
            }
            do {
                let prepared = try await task.value
                guard generation == token,!Task.isCancelled,stores == nil else { return }
                try prepared.navigation.validate()
                try prepared.settings.validate()
                try prepared.boundaries.validate()
                try prepared.tak.validate()
                let points = try WaypointStore(startup: prepared.waypoints)
                let course = try PracticeCourseStore(startup: prepared.course)
                let maps = try MapLayerStore(startup: prepared.maps)
                let settings = try AppSettings(startup: prepared.settings)
                stores = FieldAppStores(directory: configuration.directory,waypointStore: points,settingsStore: settings,seedFixtures: false,mapStore: maps,practiceStore: course,navigationStartup: prepared.navigation,boundaryStartup: prepared.boundaries,takStartup: prepared.tak)
                worker = nil
                return
            } catch is CancellationError {
                if generation == token { worker = nil }
                return
            } catch WaypointStore.StartupFailure.changed {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil // The file changed after preparation: read it again.
                changedError = WaypointStore.StartupFailure.changed
            } catch NavigationSession.StartupFailure.changed {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil; changedError = NavigationSession.StartupFailure.changed
            } catch AppSettings.StartupFailure.changed {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil; changedError = AppSettings.StartupFailure.changed
            } catch TAKLocalStore.StartupFailure.changed {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil; changedError = TAKLocalStore.StartupFailure.changed
            } catch BoundaryMonitor.StartupFailure.changed {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil; changedError = BoundaryMonitor.StartupFailure.changed
            } catch PracticeCourseStore.StartupFailure.changed {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil; changedError = PracticeCourseStore.StartupFailure.changed
            } catch MapLayerStore.StartupFailure.changed {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil; changedError = MapLayerStore.StartupFailure.changed
            } catch {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil; self.error = error.localizedDescription
                return
            }
        }
        error = changedError.localizedDescription
    }
}
