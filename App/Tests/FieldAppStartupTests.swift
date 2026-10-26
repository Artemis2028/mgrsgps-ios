import Combine
import Foundation
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class FieldAppStartupTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(condition())
    }
    func testServicesWaitForCompleteWaypointsAndQueuedLinksSurvive() async throws {
        let dir = try directory(),points = WaypointStore(directory: dir)
        let selected = points.add(.init(name: "Saved target CAFÉ",lat: 35,lon: -79,folder: "Recon"))
        points.select(selected.id); try points.setLibraryFolderVisible("Recon",visible: false)
        let file = dir.appendingPathComponent("waypoints-v1.json"),before = try Data(contentsOf: file)
        let gate = StartupReadGate(); defer { gate.release() }
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false),prepare: { try gate.prepare($0) })
        let load = Task { await startup.load() }; try await wait { gate.entered }
        XCTAssertNil(startup.stores)
        let urls = [dir.appendingPathComponent("first.gpx"),URL(string: "gridfix://recording")!,dir.appendingPathComponent("second.geojson")]
        for url in urls { startup.enqueue(url) }
        XCTAssertEqual(startup.pendingURLs,urls)
        XCTAssertEqual(try Data(contentsOf: file),before)
        gate.release(); await load.value
        let stores = try XCTUnwrap(startup.stores)
        defer { stores.tak.disconnect() }
        XCTAssertEqual(stores.waypoints.waypoints,points.waypoints)
        XCTAssertEqual(stores.waypoints.selectedId,selected.id)
        XCTAssertEqual(stores.waypoints.folders,points.folders)
        XCTAssertFalse(stores.fieldData.ready,"The independent field read remains deferred to RootView")
        XCTAssertFalse(stores.navigation.running); XCTAssertFalse(stores.tak.connected)
        XCTAssertEqual(startup.pendingURLs,urls)
        XCTAssertEqual(try Data(contentsOf: file),before)
    }
    func testConcurrentCallersBuildOneWorkspaceAndCancelledCallerCannotPublishIt() async throws {
        let dir = try directory(),gate = StartupReadGate(); defer { gate.release() }
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false),prepare: { try gate.prepare($0) })
        var publications = 0
        let subscription = startup.$stores.sink { if $0 != nil { publications += 1 } }
        defer { subscription.cancel(); startup.stores?.tak.disconnect() }
        let cancelled = Task { await startup.load() }; try await wait { gate.entered }
        cancelled.cancel(); gate.release(); await cancelled.value
        XCTAssertNil(startup.stores); XCTAssertNil(startup.error)
        async let a: Void = startup.load()
        async let b: Void = startup.load()
        _ = await (a,b)
        XCTAssertNotNil(startup.stores); XCTAssertEqual(publications,1); XCTAssertEqual(gate.count,1)
    }
    func testCorruptionKeepsOriginalAndShowsExistingRecoveryInsteadOfFreshLibrary() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("waypoints-v1.json"),bytes = Data("unreadable original CAFÉ".utf8)
        try bytes.write(to: file)
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false))
        await startup.load()
        let stores = try XCTUnwrap(startup.stores); defer { stores.tak.disconnect() }
        XCTAssertNotNil(stores.waypoints.loadError)
        XCTAssertEqual(try Data(contentsOf: file),bytes)
        XCTAssertThrowsError(try stores.waypoints.restore(waypoints: [],folders: []))
    }
    func testFileReplacedAfterPreparationRetriesBeforeCreatingServices() async throws {
        let dir = try directory(),points = WaypointStore(directory: dir),attempts = StartupAttemptCounter()
        let selected = points.add(.init(name: "Before",lat: 35,lon: -79)); points.select(selected.id)
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false),prepare: { directory in
            let prepared = try WaypointStore.prepareStartup(directory: directory)
            if attempts.next() == 1 {
                let file = dir.appendingPathComponent("waypoints-v1.json")
                var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
                var values = try XCTUnwrap(document["waypoints"] as? [[String: Any]])
                values[0]["name"] = "Newer stored target"; document["waypoints"] = values
                try JSONSerialization.data(withJSONObject: document).write(to: file,options: .atomic)
            }
            return prepared
        })
        var publications = 0
        let subscription = startup.$stores.sink { if $0 != nil { publications += 1 } }
        defer { subscription.cancel(); startup.stores?.tak.disconnect() }
        await startup.load()
        XCTAssertNil(startup.error); XCTAssertEqual(attempts.count,2); XCTAssertEqual(publications,1)
        XCTAssertEqual(startup.stores?.waypoints.waypoints.first?.name,"Newer stored target")
        XCTAssertEqual(startup.stores?.waypoints.selectedId,selected.id)
    }
    func testChangedMapPreferencesRetryBeforeOneServiceGraphIsPublished() async throws {
        let dir = try directory(),attempts = StartupAttemptCounter()
        let file = dir.appendingPathComponent("map-prefs-v1.json")
        try JSONEncoder().encode(MapLayerStore.Preferences()).write(to: file)
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false),prepareMaps: { directory in
            XCTAssertFalse(Thread.isMainThread)
            let prepared = MapLayerStore.prepareStartup(directory: directory)
            if attempts.next() == 1 {
                var preferences = MapLayerStore.Preferences(); preferences.offlineOnly = true; preferences.gridEnabled = false
                try! JSONEncoder().encode(preferences).write(to: file,options: .atomic)
            }
            return prepared
        })
        var publications = 0
        let subscription = startup.$stores.sink { if $0 != nil { publications += 1 } }
        defer { subscription.cancel(); startup.stores?.tak.disconnect() }
        await startup.load()
        XCTAssertNil(startup.error); XCTAssertEqual(attempts.count,2); XCTAssertEqual(publications,1)
        let maps = try XCTUnwrap(startup.stores?.maps)
        XCTAssertTrue(maps.preferences.offlineOnly); XCTAssertTrue(maps.pipeline.offlineOnly)
        XCTAssertFalse(maps.preferences.gridEnabled)
    }
    func testSettingsReadWaitsForWorkerAndPublishesSavedAppearanceWithServices() async throws {
        let dir = try directory(),saved = AppSettings(directory: dir),gate = StartupReadGate(),attempts = StartupAttemptCounter()
        saved.nightMode = true; saved.orientation = 3; saved.liveActivitiesEnabled = true
        saved.hiddenMapTools = ["record"]; saved.mgrsDigits = 4
        defer { gate.release() }
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false),prepare: { try gate.prepare($0) },prepareSettings: { directory in
            XCTAssertFalse(Thread.isMainThread); _ = attempts.next()
            return AppSettings.prepareStartup(directory: directory)
        })
        XCTAssertEqual(attempts.count,0,"Constructing the startup view must not read settings")
        let load = Task { await startup.load() }; try await wait { gate.entered }
        XCTAssertNil(startup.stores); XCTAssertEqual(attempts.count,1)
        startup.enqueue(URL(string: "gridfix://recording")!)
        gate.release(); await load.value
        let stores = try XCTUnwrap(startup.stores); defer { stores.tak.disconnect() }
        XCTAssertTrue(stores.settings.nightMode); XCTAssertEqual(stores.settings.orientation,3)
        XCTAssertTrue(stores.settings.liveActivitiesEnabled); XCTAssertEqual(stores.settings.hiddenMapTools,["record"])
        XCTAssertEqual(stores.settings.mgrsDigits,4); XCTAssertFalse(stores.navigation.running)
        XCTAssertEqual(startup.pendingURLs,[URL(string: "gridfix://recording")!])
    }
    func testSettingsReplacedDuringPreparationRetryBeforeServicesPublish() async throws {
        let dir = try directory(),saved = AppSettings(directory: dir),attempts = StartupAttemptCounter()
        saved.nightMode = false
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false),prepareSettings: { directory in
            let prepared = AppSettings.prepareStartup(directory: directory)
            if attempts.next() == 1 {
                let file = directory!.appendingPathComponent("settings-v1.json")
                var snapshot = try! JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String:Any]
                snapshot["nightMode"] = true; snapshot["orientation"] = 2
                try! JSONSerialization.data(withJSONObject: snapshot).write(to: file,options: .atomic)
            }
            return prepared
        })
        var publications = 0
        let subscription = startup.$stores.sink { if $0 != nil { publications += 1 } }
        defer { subscription.cancel(); startup.stores?.tak.disconnect() }
        await startup.load()
        XCTAssertNil(startup.error); XCTAssertEqual(attempts.count,2); XCTAssertEqual(publications,1)
        XCTAssertTrue(try XCTUnwrap(startup.stores?.settings).nightMode)
        XCTAssertEqual(startup.stores?.settings.orientation,2)
    }
    func testWorkerCourseStartupRetainsRunAndSplitsBeforeFieldReadiness() async throws {
        let dir = try directory(),points = WaypointStore(directory: dir)
        let first = points.add(.init(name: "First",lat: 35,lon: -79)),second = points.add(.init(name: "Second",lat: 35.1,lon: -79))
        var course = try PracticeCourse(name: "Saved run CAFÉ",waypointIDs: [first.id,second.id],startedAt: 100)
        _ = try course.markFound(runID: course.runID,checkpointID: first.id,now: 500)
        try PracticeCourseStore(directory: dir).save(course)
        let file = dir.appendingPathComponent("practice-course-v1.json"),before = try Data(contentsOf: file)
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false))
        await startup.load()
        let stores = try XCTUnwrap(startup.stores); defer { stores.tak.disconnect() }
        XCTAssertEqual(stores.practice.active,course); XCTAssertFalse(stores.fieldData.ready)
        XCTAssertFalse(stores.navigation.running); XCTAssertEqual(try Data(contentsOf: file),before)
        await stores.fieldData.load()
        try await wait { !stores.practice.working && stores.waypoints.practiceNavigationLocked }
        XCTAssertEqual(stores.waypoints.selectedId,second.id)
        XCTAssertEqual(stores.practice.active?.foundAt,[500]); XCTAssertTrue(stores.fieldData.document.courseHistory.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file),before)
    }
    func testWorkerCourseStartupKeepsDamagedBytesAndLocksNavigationAfterFieldReadiness() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("practice-course-v1.json"),bytes = Data("unreadable course".utf8)
        try bytes.write(to: file)
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false))
        await startup.load()
        let stores = try XCTUnwrap(startup.stores); defer { stores.tak.disconnect() }
        XCTAssertTrue(stores.practice.damaged); XCTAssertEqual(try Data(contentsOf: file),bytes)
        await stores.fieldData.load()
        try await wait { !stores.practice.working && stores.waypoints.practiceNavigationLocked }
        XCTAssertNotNil(stores.practice.error); XCTAssertNil(stores.waypoints.selectedId)
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testWorkerNavigationStartupPreservesDamagedSessionAndQueuedResumeLink() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("navigation-session-v1.json"),bytes = Data("SYNTHETIC damaged navigation session".utf8)
        try bytes.write(to: file)
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false))
        let link = URL(string: "gridfix://navigation")!; startup.enqueue(link)
        await startup.load()
        let stores = try XCTUnwrap(startup.stores); defer { stores.tak.disconnect() }
        XCTAssertNotNil(stores.navigation.error); XCTAssertNil(stores.navigation.progress)
        XCTAssertFalse(stores.navigation.running); XCTAssertFalse(stores.navigation.preparing)
        XCTAssertFalse(stores.fieldData.ready); XCTAssertEqual(startup.pendingURLs,[link])
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testInterruptedAndDamagedBoundaryStartupStayInactiveAndKeepOriginalFiles() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("boundaries-v1.json")
        let area = BoundaryArea(name: "Quiet perimeter",vertices: [.init(lat: 35,lon: -79),.init(lat: 35.001,lon: -79),.init(lat: 35.001,lon: -78.999)])
        for bytes in [try JSONEncoder().encode(BoundaryMonitor.Document(areas: [area],interruptedID: area.id)),Data("damaged boundary CAFÉ".utf8)] {
            try bytes.write(to: file,options: .atomic)
            let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false))
            await startup.load()
            let stores = try XCTUnwrap(startup.stores); defer { stores.tak.disconnect() }
            XCTAssertFalse(stores.boundaries.running); XCTAssertFalse(stores.fieldData.ready)
            XCTAssertEqual(try Data(contentsOf: file),bytes)
            if stores.boundaries.loadFailed { XCTAssertFalse(stores.boundaries.save(area)) }
            else { XCTAssertEqual(stores.boundaries.areas,[area]); XCTAssertTrue(stores.boundaries.status.contains("interrupted")) }
        }
    }
    func testChangedBoundaryLibraryRetriesBeforePublishingOneServiceGraph() async throws {
        let dir = try directory(),file = dir.appendingPathComponent("boundaries-v1.json"),attempts = StartupAttemptCounter()
        let area = BoundaryArea(name: "Before",vertices: [.init(lat: 35,lon: -79),.init(lat: 35.001,lon: -79),.init(lat: 35.001,lon: -78.999)])
        try JSONEncoder().encode(BoundaryMonitor.Document(areas: [area])).write(to: file)
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false),prepareBoundaries: { directory in
            XCTAssertFalse(Thread.isMainThread)
            let prepared = BoundaryMonitor.prepareStartup(directory: directory)
            if attempts.next() == 1 {
                var replacement = area; replacement.name = "Newer perimeter"
                try! JSONEncoder().encode(BoundaryMonitor.Document(areas: [replacement])).write(to: file,options: .atomic)
            }
            return prepared
        })
        var publications = 0
        let subscription = startup.$stores.sink { if $0 != nil { publications += 1 } }
        defer { subscription.cancel(); startup.stores?.tak.disconnect() }
        await startup.load()
        XCTAssertNil(startup.error); XCTAssertEqual(attempts.count,2); XCTAssertEqual(publications,1)
        XCTAssertEqual(startup.stores?.boundaries.areas.first?.name,"Newer perimeter")
        XCTAssertEqual(startup.stores?.boundaries.running,false)
    }
    func testFailedPreparationCanRetryWithoutDroppingQueuedLink() async throws {
        let dir = try directory(),attempts = StartupAttemptCounter()
        let startup = FieldAppStartup(configuration: .init(directory: dir,seedFixtures: false,holdsForUITest: false),prepare: { directory in
            if attempts.next() == 1 { throw CocoaError(.fileReadNoPermission) }
            return try WaypointStore.prepareStartup(directory: directory)
        })
        let link = URL(string: "gridfix://navigation")!; startup.enqueue(link)
        await startup.load()
        XCTAssertNotNil(startup.error); XCTAssertNil(startup.stores)
        XCTAssertEqual(startup.pendingURLs,[link])
        await startup.load()
        defer { startup.stores?.tak.disconnect() }
        XCTAssertNil(startup.error); XCTAssertNotNil(startup.stores)
        XCTAssertEqual(startup.pendingURLs,[link]); XCTAssertEqual(attempts.count,2)
    }
}

private final class StartupAttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}

private final class StartupReadGate: @unchecked Sendable {
    private let lock = NSLock(),semaphore = DispatchSemaphore(value: 0)
    private var reads = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var entered: Bool { count > 0 }
    func release() { semaphore.signal() }
    func prepare(_ directory: URL?) throws -> WaypointStore.PreparedStartup {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); reads += 1; lock.unlock()
        guard semaphore.wait(timeout: .now()+10) == .success else { throw CancellationError() }
        return try WaypointStore.prepareStartup(directory: directory)
    }
}
