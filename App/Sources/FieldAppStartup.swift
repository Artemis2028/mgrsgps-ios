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
            directory = temporary
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
    let settings: AppSettings
    let holdsForUITest: Bool
    private let configuration: FieldLaunchConfiguration
    private let prepare: @Sendable (URL?) throws -> WaypointStore.PreparedStartup
    private struct PreparedWorkspace: Sendable {
        let waypoints: WaypointStore.PreparedStartup
        let maps: MapLayerStore.PreparedStartup
        let course: PracticeCourseStore.PreparedStartup
    }
    private var worker: Task<PreparedWorkspace,Error>?
    private var generation = UUID()
    private let prepareMaps: @Sendable (URL?) -> MapLayerStore.PreparedStartup

    init(configuration: FieldLaunchConfiguration = .current(),
         prepare: @escaping @Sendable (URL?) throws -> WaypointStore.PreparedStartup = { try WaypointStore.prepareStartup(directory: $0) },
         prepareMaps: @escaping @Sendable (URL?) -> MapLayerStore.PreparedStartup = { MapLayerStore.prepareStartup(directory: $0) }) {
        self.configuration = configuration; self.prepare = prepare; self.prepareMaps = prepareMaps
        holdsForUITest = configuration.holdsForUITest
        settings = AppSettings(directory: configuration.directory)
        OrientationState.shared.prepare(settings.orientation)
        // Existing UI fixture setup stays synchronous. Normal launches and the
        // explicit cold-launch fixtures exercise the worker path below.
        if configuration.seedFixtures {
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
                let operation = prepare,mapOperation = prepareMaps,directory = configuration.directory
                generation = UUID(); token = generation
                task = Task.detached(priority: .userInitiated) {
                    let waypoints = try operation(directory)
                    try Task.checkCancellation()
                    let maps = mapOperation(directory)
                    try Task.checkCancellation()
                    let courseDirectory = directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!
                    let course = try PracticeCourseStore.prepareStartup(directory: courseDirectory)
                    return PreparedWorkspace(waypoints: waypoints,maps: maps,course: course)
                }
                worker = task
            }
            do {
                let prepared = try await task.value
                guard generation == token,!Task.isCancelled,stores == nil else { return }
                let points = try WaypointStore(startup: prepared.waypoints)
                let course = try PracticeCourseStore(startup: prepared.course)
                let maps = try MapLayerStore(startup: prepared.maps)
                stores = FieldAppStores(directory: configuration.directory,waypointStore: points,settingsStore: settings,seedFixtures: false,mapStore: maps,practiceStore: course)
                worker = nil
                return
            } catch is CancellationError {
                if generation == token { worker = nil }
                return
            } catch WaypointStore.StartupFailure.changed {
                guard generation == token,!Task.isCancelled else { return }
                worker = nil // The file changed after preparation: read it again.
                changedError = WaypointStore.StartupFailure.changed
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
