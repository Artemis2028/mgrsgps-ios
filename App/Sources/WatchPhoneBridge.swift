import Combine
import GridFixCore
import WatchConnectivity

/// A complete application context coalesces offline edits, deletion and selection clearing.
@MainActor
final class WatchPhoneBridge: NSObject, WCSessionDelegate {
    private let store: WaypointStore
    private let settings: AppSettings
    private let field: FieldDataStore
    private let boundaries: BoundaryMonitor
    private var sourceID: String
    private var revision: Int64
    private var generation = 0
    private var mapTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var session: WCSession?

    init(store: WaypointStore, settings: AppSettings, field: FieldDataStore, boundaries: BoundaryMonitor) {
        self.store = store; self.settings = settings; self.field = field; self.boundaries = boundaries
        let defaults = UserDefaults.standard
        sourceID = defaults.string(forKey: "watch.map.source") ?? UUID().uuidString
        revision = max(0, (defaults.object(forKey: "watch.map.revision") as? NSNumber)?.int64Value ?? 0)
        defaults.set(sourceID, forKey: "watch.map.source")
        super.init()
        guard WCSession.isSupported() else { return }
        session = .default
        session?.delegate = self
        session?.activate()
        // objectWillChange fires before the new value: defer serialization until the next runloop.
        Publishers.MergeMany([
            store.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            settings.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            field.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            boundaries.$areas.map { _ in () }.eraseToAnyPublisher(),
            boundaries.$displayedID.map { _ in () }.eraseToAnyPublisher(),
            boundaries.$activeID.map { _ in () }.eraseToAnyPublisher()
        ])
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in self?.publish() }.store(in: &subscriptions)
    }

    private func publish() {
        guard let session, session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled else { return }
        let selected = store.waypoints.first { $0.id == store.selectedId }
        let snapshot = WatchSnapshot(target: selected.map { .init(id: $0.id, name: $0.name, lat: $0.lat, lon: $0.lon) },
                                     nightMode: settings.nightMode, mgrsDigits: settings.mgrsDigits,
                                     units: settings.units.rawValue, angleUnit: settings.angleUnit.rawValue,
                                     northRef: settings.northRef.rawValue, declinationOverride: settings.declinationOverride)
        guard snapshot.isValid, let data = try? JSONEncoder().encode(snapshot) else { return }
        let points = store.waypoints, folders = store.folders, document = field.document
        let boundary = boundaries.displayedArea
        generation += 1
        if revision == .max { sourceID = UUID().uuidString; revision = 0 }
        revision += 1
        UserDefaults.standard.set(sourceID, forKey: "watch.map.source")
        UserDefaults.standard.set(revision, forKey: "watch.map.revision")
        let source = sourceID, mapRevision = revision
        let token = generation
        // Track decoding/simplification is bounded and off the main actor. A newer edit wins.
        mapTask?.cancel()
        mapTask = Task.detached(priority: .utility) { [weak self] in
            let map = WatchMapSnapshot.build(waypoints: points, folders: folders, document: document, boundary: boundary, sourceID: source, revision: mapRevision)
            guard !Task.isCancelled else { return }
            let mapData = map.encoded()
            await MainActor.run { [weak self] in
                guard let self, self.generation == token, session.activationState == .activated else { return }
                var context: [String: Any] = [WatchSnapshot.contextKey: data]
                if let mapData { context[WatchMapSnapshot.contextKey] = mapData }
                else { context["gridfix.map.error"] = "Phone map snapshot unavailable" }
                try? session.updateApplicationContext(context)
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish() }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

#if DEBUG
extension WatchPhoneBridge {
    /// Explicit opt-in, temporary-store-only fixture for paired simulator delivery tests.
    static func seedUITest(store: WaypointStore, settings: AppSettings) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting"), args.contains("-uiTestWatch") else { return }
        let target = store.add(.init(name: "SYNTHETIC RALLY", lat: 24.4639, lon: 54.3873))
        store.select(args.contains("-uiTestWatchClear") ? nil : target.id)
        settings.nightMode = args.contains("-uiTestWatchNight")
        settings.setMgrsDigits(args.contains("-uiTestWatchPrecision4") ? 4 : 10)
        settings.northRef = args.contains("-uiTestWatchMag") ? .magnetic : .trueNorth
        settings.declinationOverride = args.contains("-uiTestWatchMag") ? 4 : nil
    }

    static func seedMapUITest(store: WaypointStore, field: FieldDataStore, boundaries: BoundaryMonitor) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting") else { return }
        if args.contains("-uiTestWatchMapClear") { store.setFolderVisible(Folders.defaultFolder, visible: false); return }
        guard args.contains("-uiTestWatchMap") else { return }
        _ = store.add(.init(name: "SYNTHETIC INF", lat: 24.4548, lon: 54.3783, symbol: "nato_f_inf", affiliation: "friendly"))
        _ = store.add(.init(name: "HIDDEN", lat: 24.454, lon: 54.377, folder: "Watch hidden"))
        store.setFolderVisible("Watch hidden", visible: false)
        try? field.saveGraphic(.init(id: "watch-map-route", name: "SYNTHETIC ROUTE", type: "route", points: [.init(lat: 24.4535, lon: 54.3765), .init(lat: 24.454, lon: 54.378), .init(lat: 24.455, lon: 54.379)], affiliation: "friendly"))
        try? field.saveGraphic(.init(id: "watch-map-area", name: "SYNTHETIC AREA", type: "objective", points: [.init(lat: 24.453, lon: 54.378), .init(lat: 24.453, lon: 54.379), .init(lat: 24.454, lon: 54.379)], affiliation: "hostile"))
        try? field.saveGraphic(.init(id: "watch-map-ring", name: "SYNTHETIC RING", type: "ring", points: [.init(lat: 24.454, lon: 54.3773), .init(lat: 24.4547, lon: 54.3773)]))
        var document = Backup.Document()
        let id = "00000000-0000-0000-0000-000000000029"
        let points = [TrackPoint(lat: 24.4534, lon: 54.3768), TrackPoint(lat: 24.4537, lon: 54.3771), TrackPoint(lat: 24.4541, lon: 54.3774)]
        document.tracks = [.init(id: id, name: "SYNTHETIC TRACK", startedAt: 0, endedAt: 0, distanceM: 100, pointCount: points.count)]
        document.trackFiles[id] = try? TrackCodec.encode(points)
        _ = try? field.restore(document)
        _ = boundaries.save(.init(id: "watch-map-fence", name: "SYNTHETIC FENCE", vertices: [.init(lat: 24.4528, lon: 54.3764), .init(lat: 24.4555, lon: 54.3764), .init(lat: 24.4555, lon: 54.380), .init(lat: 24.4528, lon: 54.380)]))
    }
}
#endif
