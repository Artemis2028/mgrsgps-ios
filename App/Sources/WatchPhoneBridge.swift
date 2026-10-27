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
    private let lanes: NavigationLaneStore?
    private let navigation: NavigationSession?
    private let tak: TAKSession?
    private var takRevision: Int64 = 0
    private var takGeneration = 0
    private var takTask: Task<Void,Never>?
    private var takSnapshot: WatchTAKSnapshot?
    private var context: [String:Any] = [:]
    private var guideRevision: Int64 = 0
    private var guideTimer: AnyCancellable?
    private var previousGuide: WatchGuideSnapshot?
    private var guideSentAt: Date?
    private var sourceID: String
    private var revision: Int64
    private var generation = 0
    private var mapTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var session: WCSession?

    init(store: WaypointStore, settings: AppSettings, field: FieldDataStore, boundaries: BoundaryMonitor,lanes: NavigationLaneStore? = nil,navigation: NavigationSession? = nil,tak: TAKSession? = nil) {
        self.store = store; self.settings = settings; self.field = field; self.boundaries = boundaries; self.lanes = lanes; self.navigation = navigation; self.tak = tak
        takRevision = max(0,(UserDefaults.standard.object(forKey:"watch.tak.revision") as? NSNumber)?.int64Value ?? 0)
        guideRevision = max(0,(UserDefaults.standard.object(forKey:"watch.guide.revision") as? NSNumber)?.int64Value ?? 0)
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
        var sources: [AnyPublisher<Void,Never>] = [
            store.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            settings.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            field.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            boundaries.$areas.map { _ in () }.eraseToAnyPublisher(),
            boundaries.$displayedID.map { _ in () }.eraseToAnyPublisher(),
            boundaries.$activeID.map { _ in () }.eraseToAnyPublisher()
        ]
        if let navigation {
            navigation.objectWillChange.debounce(for:.milliseconds(100),scheduler:RunLoop.main)
                .sink { [weak self] in self?.publishGuide() }.store(in:&subscriptions)
        }
        if let tak {
            tak.objectWillChange.debounce(for:.milliseconds(250),scheduler:RunLoop.main)
                .sink { [weak self] in self?.publishTAK() }.store(in:&subscriptions)
        }
        guideTimer = Timer.publish(every: 5,on:.main,in:.common).autoconnect().sink { [weak self] _ in self?.publishGuide(heartbeat:true) }
        if let lanes { sources.append(lanes.objectWillChange.map { _ in () }.eraseToAnyPublisher()) }
        Publishers.MergeMany(sources)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in self?.publish() }.store(in: &subscriptions)
    }

    private func publish() {
        guard field.ready, field.loadError == nil else { return }
        guard let session, session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled else { return }
        let selected = store.waypoints.first { $0.id == store.selectedId }
        let snapshot = WatchSnapshot(target: selected.map { .init(id: $0.id, name: $0.name, lat: $0.lat, lon: $0.lon) },
                                     nightMode: settings.nightMode, mgrsDigits: settings.mgrsDigits,
                                     units: settings.units.rawValue, angleUnit: settings.angleUnit.rawValue,
                                     northRef: settings.northRef.rawValue, declinationOverride: settings.declinationOverride)
        guard snapshot.isValid, let data = try? JSONEncoder().encode(snapshot) else { return }
        let points = store.waypoints, folders = store.folders, document = field.document
        let boundary = boundaries.displayedArea, laneValues = lanes?.lanes ?? []
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
            let map = WatchMapSnapshot.build(waypoints: points, folders: folders, document: document, boundary: boundary, lanes: laneValues, sourceID: source, revision: mapRevision)
            guard !Task.isCancelled else { return }
            let mapData = map.encoded()
            await MainActor.run { [weak self] in
                guard let self, self.generation == token, session.activationState == .activated else { return }
                self.context[WatchSnapshot.contextKey] = data
                self.context.removeValue(forKey:"gridfix.map.error")
                if let mapData { self.context[WatchMapSnapshot.contextKey] = mapData }
                else { self.context.removeValue(forKey:WatchMapSnapshot.contextKey); self.context["gridfix.map.error"] = "Phone map snapshot unavailable" }
                self.publishGuide(force:true)
            }
        }
    }

    private func publishGuide(heartbeat: Bool = false,force: Bool = false) {
        guard field.ready else { return }
        guard let session,session.activationState == .activated,session.isPaired,session.isWatchAppInstalled else { return }
        var next = navigation?.watchGuideSnapshot(sourceID:sourceID,revision:guideRevision) ?? .init(sourceID:sourceID,revision:guideRevision,at:Int64(Date().timeIntervalSince1970*1000),active:false)
        // Compare content without its heartbeat fields; rate-limit repeated unchanged evaluations.
        var previous = previousGuide
        previous?.at = next.at; previous?.revision = next.revision
        guard force || previous != next || (heartbeat && next.active && Date().timeIntervalSince(guideSentAt ?? .distantPast) >= 4) else { return }
        guard guideRevision < .max else { return }
        guideRevision += 1; next.revision = guideRevision
        guard next.isValid,let data = try? JSONEncoder().encode(next) else { return }
        UserDefaults.standard.set(guideRevision,forKey:"watch.guide.revision")
        previousGuide = next; guideSentAt = Date(); context[WatchGuideSnapshot.contextKey] = data
        // Complete context handles disconnect/offline stop; a reachable watch also receives it immediately.
        sendContext()
        if session.isReachable { session.sendMessage([WatchGuideSnapshot.contextKey:data],replyHandler:nil,errorHandler:{ _ in }) }
    }

    private func publishTAK() {
        guard field.ready else { return }
        guard let session,session.activationState == .activated,session.isPaired,session.isWatchAppInstalled,takRevision < .max else { return }
        takRevision += 1; takGeneration += 1
        UserDefaults.standard.set(takRevision,forKey:"watch.tak.revision")
        let token = takGeneration,revision = takRevision,sourceID = sourceID
        let items = tak?.remoteItems ?? [],enabled = tak?.profile.showRemote ?? false,connected = tak?.connected ?? false
        takTask?.cancel()
        takTask = Task.detached(priority:.utility) { [weak self] in
            let value = WatchTAKSnapshot.build(items,enabled:enabled,connected:connected,sourceID:sourceID,revision:revision)
            guard !Task.isCancelled,let data = value.encoded() else { return }
            await MainActor.run { [weak self] in
                guard let self,self.takGeneration == token else { return }
                self.takSnapshot = value; self.sendContext()
                if session.activationState == .activated,session.isReachable {
                    session.sendMessage([WatchTAKSnapshot.contextKey:data],replyHandler:nil,errorHandler:{ _ in })
                }
            }
        }
    }
    /// Reserve a separate 8 KiB remote budget without silently truncating geometry.
    /// A local map too large for the whole context gets an explicit cache warning.
    static func boundedContext(_ base: [String:Any],tak: WatchTAKSnapshot?) -> [String:Any]? {
        var result = base; result.removeValue(forKey:WatchTAKSnapshot.contextKey)
        func size(_ value:[String:Any]) -> Int { (try? PropertyListSerialization.data(fromPropertyList:value,format:.binary,options:0).count) ?? .max }
        if size(result) > 52*1024-512 {
            result.removeValue(forKey:WatchMapSnapshot.contextKey)
            result["gridfix.map.error"] = "Phone map exceeds the watch context budget · cached overlay"
        }
        if let data = tak?.encoded() { result[WatchTAKSnapshot.contextKey] = data }
        return size(result) <= 60*1024 ? result : nil
    }
    private func sendContext() {
        guard let session,session.activationState == .activated,let outgoing = Self.boundedContext(context,tak:takSnapshot) else { return }
        try? session.updateApplicationContext(outgoing)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish(); self.publishTAK() }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.publish(); self.publishTAK() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.publish(); self.publishTAK() } }
    nonisolated func session(_ session: WCSession,didReceiveMessage message: [String:Any]) {
        guard message["gridfix.guide.request"] as? Bool == true || message["gridfix.tak.request"] as? Bool == true else { return }
        Task { @MainActor in self.publishGuide(force:true); self.publishTAK() }
    }
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
        if args.contains("-uiTestWatchTactical") {
            for point in store.waypoints { store.setVisible(id:point.id,visible:false) }
            let values: [(String,[(Double,Double)])]
            if args.contains("-uiTestWatchTacticalDateline") {
                values = [("wire",[(10.0005,179.999),(10,-179.999),(10.0005,-179.997)])]
            } else {
                values = [
                    ("axis",[(24.456,54.3748),(24.4563,54.3757),(24.456,54.3766)]),
                    ("wire",[(24.456,54.3776),(24.4563,54.3785),(24.456,54.3794)]),
                    ("screen_l",[(24.4545,54.3748),(24.4548,54.3757),(24.4545,54.3766)]),
                    ("strongpoint",[(24.4545,54.3776),(24.4548,54.3785),(24.4543,54.3794)]),
                    ("route",[(24.453,54.3748),(24.4533,54.3757),(24.453,54.3766)]),
                    ("minefield",[(24.453,54.3776),(24.4533,54.3785),(24.4528,54.3794)])
                ]
            }
            for (index,item) in values.enumerated() {
                try? field.saveGraphic(.init(id:"watch-tactical-\(index)",name:item.0,type:item.0,
                                            points:item.1.map { .init(lat:$0.0,lon:$0.1) },affiliation:index%2 == 0 ? "friendly" : "hostile",echelon:"bn"))
                if index < 2,let start = item.1.first,let end = item.1.last {
                    for (label,point) in [("START",start),("END",end)] {
                        _ = store.add(.init(name:"\(item.0) \(label)",lat:point.0,lon:point.1,symbol:"dot"))
                    }
                }
            }
            return
        }
        if args.contains("-uiTestWatchSymbols") {
            for point in store.waypoints where point.name == "SYNTHETIC RALLY" { store.setVisible(id:point.id,visible:false) }
            let entries: [(String,String,String,String,Double,WaypointMetadata)] = [
                ("SBF","task_sbf","friendly","",90,.init()),
                ("AMBUSH","task_ambush","hostile","",0,.init()),
                ("SCREEN","task_screen","friendly","",90,.init()),
                ("HOSTILE","diamond","hostile","",0,.init()),
                ("PLATOON","nato_f_inf","friendly","plt",0,.init()),
                ("IMPORTED","flag","none","",0,.init(color:"cyan",milgpsSymbolCode:MilGpsSymbols.encode(shape:.circle,character:"6")))
            ]
            for (index,item) in entries.enumerated() {
                _ = store.add(.init(name:item.0,lat:24.4555-Double(index/2)*0.0015,lon:54.3758+Double(index%2)*0.0022,
                                    symbol:item.1,affiliation:item.2,echelon:item.3,rotation:item.4,metadata:item.5))
            }
            return
        }
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
