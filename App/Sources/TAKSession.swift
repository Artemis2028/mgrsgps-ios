import CoreLocation
import Foundation
import GridFixCore

@MainActor
final class TAKSession: ObservableObject {
    @Published private(set) var profile = TAKProfile()
    @Published private(set) var status = "Disconnected"
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var trustRequest: TAKServerTrust.Certificate?
    @Published private(set) var remoteItems: [TAKRemoteItem] = []
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var failure: String?
    @Published var sharePosition = false { didSet { if oldValue != sharePosition { updateLocationDemand(); lastPresence = nil; tick() } } }
    private let transport: TAKTransportDriving
    private let location: RecordingLocationDriver
    private var store: TAKLocalStore?
    private var credentials: TAKImportedCredentials?
    private var scene = TAKRemoteScene()
    private var timer: Timer?
    private var desired = false
    private var foreground = true
    private var attempt = UUID()
    private var retryAt: TimeInterval?
    private var backoff: TimeInterval = 1
    private var lastPing: TimeInterval?
    private var lastPresence: TimeInterval?
    private var fix: Fix?
    private var locationStarted = false
    private let waypoints: WaypointStore?
    private let field: FieldDataStore?
    private var sent: [String: String] = [:]
    private var sharingAvailable = true
    private var sharingBusy = false
    private var lastShareCheck: TimeInterval?
    private var lastShareRefresh: TimeInterval?
    private var synthetic: GeoPoint?
    var isSyntheticValidation: Bool { synthetic != nil }
    var availableFolders: [String] {
        Array(Set((waypoints?.folders.map(\.name) ?? []) + (field?.document.graphics.map(\.folder) ?? []))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var sharedFolders: Set<String> { profile.sharedFolders ?? [] }
    var configured: Bool { !profile.host.isEmpty }

    init(directory: URL, transport: TAKTransportDriving = TAKTransport(), driver: RecordingLocationDriver? = nil, startTimer: Bool = true, waypoints: WaypointStore? = nil, field: FieldDataStore? = nil) {
        self.waypoints = waypoints; self.field = field
        self.transport = transport; self.location = driver ?? CoreLocationRecordingDriver()
        do {
            let local = try TAKLocalStore(root: directory)
            store = local; profile = try local.readProfile()
            do { sent = try local.readSent(profile: profile) } catch { sharingAvailable = false; failure = "Saved TAK sharing history needs repair; folder sharing is disabled" }
        } catch { failure = "Unable to read local TAK preferences" }
        location.onLocations = { [weak self] samples in
            guard let self, let sample = samples.last else { return }
            self.fix = Fix(location: sample, now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
            self.tick()
        }
        location.onAuthorization = { [weak self] in self?.updateLocationDemand() }
        location.onFailure = { [weak self] _ in self?.fix = nil }
        if startTimer { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        } }
    }
    func importPackage(_ bytes: Data) async {
        disconnect()
        do {
            let package = try await Task.detached(priority: .userInitiated) { try TAKConnectionPackage.read(bytes) }.value
            guard let store else { throw TAKCoT.Failure(message: "Local TAK storage is unavailable") }
            if package.needsEnrollment { throw TAKCoT.Failure(message: "This package needs certificate enrollment. Import a package containing your client certificate and private key.") }
            let imported = try await Task.detached(priority: .userInitiated) { try TAKImportedCredentials.read(package) }.value
            var next = profile
            if next.host != package.host || next.port != package.port || next.tls != package.usesTLS { next.pin = nil }
            next.host = package.host; next.port = package.port; next.title = package.description; next.tls = package.usesTLS
            // Secrets stay in a device-only Keychain item; the profile contains
            // endpoint/callsign/pin only and is excluded from backups.
            try store.saveCredentials(.init(package), uid: next.uid)
            try store.write(next)
            profile = next
            do { sent = try store.readSent(profile: next); sharingAvailable = true }
            catch { sent = [:]; sharingAvailable = false }
            credentials = imported; trustRequest = nil; failure = nil
            status = "Ready to connect"
            scene.clear(); remoteItems = []
        } catch { failure = error.localizedDescription; status = "Import failed" }
    }
    func reportImportFailure(_ message: String) { failure = message }
    func setCallsign(_ value: String) {
        let name = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { return }
        profile.callsign = name; saveProfile(); lastPresence = nil
    }
    func setFolderShared(_ folder: String, shared: Bool) {
        var folders = sharedFolders
        if shared { folders.insert(folder) } else { folders.remove(folder) }
        profile.sharedFolders = folders; saveProfile(); lastShareCheck = nil; tick()
    }
    func setRemoteVisible(_ value: Bool) { profile.showRemote = value; saveProfile() }
    func connect() {
        guard configured, !desired else { return }
        desired = true; failure = nil; backoff = 1; retryAt = nil
        beginAttempt()
    }
    func disconnect() {
        desired = false; attempt = UUID(); retryAt = nil; connected = false; connecting = false
        transport.stop(); status = "Disconnected"; sharePosition = false
        updateLocationDemand()
        trustRequest = nil
    }
    func approveCertificate() {
        guard let request = trustRequest else { return }
        profile.pin = request.sha256
        do { try store?.write(profile) } catch { failure = "Unable to save the certificate pin"; return }
        trustRequest = nil; connect()
    }
    func declineCertificate() { trustRequest = nil; disconnect() }
    func resetServerTrust() {
        disconnect()
        guard let store else { failure = "Local TAK storage is unavailable"; return }
        var next = profile; next.pin = nil
        do {
            try store.write(next); profile = next; failure = nil
            status = "Server trust reset. Connect to verify the certificate."
        } catch { failure = "Unable to reset the saved certificate pin" }
    }
    func setForeground(_ active: Bool) {
        foreground = active
        if active { updateLocationDemand(); tick() }
        else if !sharePosition {
            // iOS can suspend receive-only sockets. Do not turn on location to
            // manufacture background execution when position sharing is off.
            attempt = UUID(); transport.stop(); connected = false; connecting = false
            if desired { status = "Paused in background"; retryAt = 0 }
        }
    }
    private func beginAttempt() {
        guard desired, foreground || sharePosition, let port = UInt16(exactly: profile.port), port > 0 else { return }
        let token = UUID(); attempt = token; connecting = true; connected = false; status = "Connecting"
        let profile = profile
        Task {
            do {
                if credentials == nil {
                    guard let archive = try store?.credentials(profile.uid) else { throw TAKCoT.Failure(message: "Import a TAK connection package first") }
                    credentials = try await Task.detached(priority: .userInitiated) { try TAKImportedCredentials.read(archive.package(profile)) }.value
                }
                guard attempt == token, desired, let credentials else { return }
                transport.start(host: profile.host, port: port, tls: profile.tls, identity: credentials.identity,
                                anchors: credentials.anchors, pinnedSHA256: profile.pin) { [weak self] event in
                    Task { @MainActor in self?.receive(event, attempt: token) }
                }
            } catch {
                guard attempt == token else { return }
                desired = false; connecting = false; failure = error.localizedDescription; status = "Credentials unavailable"
            }
        }
    }
    private func receive(_ event: TAKTransport.Event, attempt token: UUID) {
        guard attempt == token, desired else { return }
        switch event {
        case .ready:
            connected = true; connecting = false; failure = nil; status = "Connected"; lastReceivedAt = nil
            backoff = 1; retryAt = nil; lastPing = nil; lastPresence = nil; lastShareCheck = nil; lastShareRefresh = nil; sharingBusy = false
            updateLocationDemand(); tick()
        case let .trustRequired(certificate):
            desired = false; connecting = false; connected = false
            status = "Certificate approval required"; trustRequest = certificate
            updateLocationDemand()
        case let .refused(reason):
            desired = false; connected = false; connecting = false; status = "Connection refused"; failure = reason
            updateLocationDemand()
        case let .failed(reason):
            connected = false; connecting = false; status = "Reconnecting"; failure = reason
            retryAt = ProcessInfo.processInfo.systemUptime + backoff; backoff = min(60, backoff * 2)
        case let .xml(xml):
            lastReceivedAt = Date()
            if let event = TAKCoT.parse(xml, ownUID: profile.uid, now: Date()) {
                if scene.apply(event, now: Date(), uptime: ProcessInfo.processInfo.systemUptime) { remoteItems = scene.items }
            }
        }
    }
    private func tick() {
        let uptime = ProcessInfo.processInfo.systemUptime, now = Date()
        if scene.expire(now: now, uptime: uptime) { remoteItems = scene.items }
        if desired, !connected, !connecting, let retryAt, uptime >= retryAt, foreground || sharePosition {
            self.retryAt = nil; beginAttempt()
        }
        guard connected else { return }
        do {
            // Announce device identity before other traffic on every connection.
            // This deterministic ordering is not a workaround for OTS's unique
            // callsign constraint: the caller must still use a unique callsign.
            let cadence: TimeInterval = sharePosition ? 10 : 60
            if lastPresence == nil || uptime - lastPresence! >= cadence {
                var position: GeoPoint?, accuracy: Double = 9999999
                if sharePosition {
                    if let synthetic { position = synthetic; accuracy = 5 }
                    else if let fix, !PositionFixQuality(fix: fix, nowUptime: uptime).stale,
                            fix.accuracyMeters.isFinite, fix.accuracyMeters >= 0,
                            fix.lat.isFinite, fix.lon.isFinite, abs(fix.lat) <= 90, abs(fix.lon) <= 180 {
                        position = .init(lat: fix.lat, lon: fix.lon); accuracy = fix.accuracyMeters
                    }
                }
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
                transport.send(try TAKCoT.presence(uid: profile.uid, callsign: profile.callsign, version: version,
                                                 now: now, position: position, accuracy: accuracy))
                lastPresence = uptime
            }
            if lastPing == nil || uptime - lastPing! >= 15 {
                transport.send(try TAKCoT.ping(uid: profile.uid, now: now)); lastPing = uptime
            }
            reconcileSharing(now: now, uptime: uptime)
        } catch { failure = "Unable to encode TAK presence" }
    }
    private func reconcileSharing(now: Date, uptime: TimeInterval) {
        guard sharingAvailable, !sharingBusy, let store,
              lastShareCheck == nil || uptime - lastShareCheck! >= 3 else { return }
        lastShareCheck = uptime
        let current = TAKSharing.current(sharedFolders: sharedFolders, waypoints: waypoints?.waypoints ?? [],
                                         graphics: field?.document.graphics ?? [], folders: waypoints?.folders ?? [],
                                         uid: profile.uid, callsign: profile.callsign)
        let refresh = lastShareRefresh == nil || uptime - lastShareRefresh! >= TAKSharing.refreshSeconds
        let plan = TAKSharing.plan(current: current, sent: sent, refreshAll: refresh)
        guard !plan.send.isEmpty || !plan.delete.isEmpty else { if refresh { lastShareRefresh = uptime }; return }
        let token = attempt, sharingProfile = profile
        sharingBusy = true
        Task {
            defer { if attempt == token { sharingBusy = false } }
            guard connected, attempt == token else { return }
            do {
                // Journal newly advertised UIDs before any network write. A
                // crash must not lose the ability to unshare them on reconnect.
                var journal = sent
                for item in plan.send { journal[item.uid] = item.signature }
                try store.writeSent(journal, profile: sharingProfile); sent = journal
                for uid in plan.delete {
                    guard connected, attempt == token else { return }
                    let success = await sendTracked(try TAKCoT.delete(uid: uid, now: now))
                    guard success, attempt == token else { return }
                    var next = sent; next[uid] = nil
                    try store.writeSent(next, profile: sharingProfile); sent = next
                }
                for item in plan.send {
                    guard connected, attempt == token else { return }
                    guard await sendTracked(try item.xml(now: now)) else { return }
                }
                if attempt == token, refresh { lastShareRefresh = uptime }
            } catch { failure = "Unable to persist or encode TAK folder sharing" }
        }
    }
    private func sendTracked(_ xml: String) async -> Bool {
        await withCheckedContinuation { continuation in
            transport.send(xml, completion: { continuation.resume(returning: $0) })
        }
    }
    private func updateLocationDemand() {
        guard synthetic == nil else { if locationStarted { location.stop(); locationStarted = false }; return }
        guard sharePosition, desired else {
            if locationStarted { location.stop(); locationStarted = false }; fix = nil; return
        }
        switch location.authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            if !locationStarted, foreground { location.start(); locationStarted = true }
        case .notDetermined:
            if foreground { location.requestPermission() }
        default: failure = "Location permission is required to share your position"; fix = nil
        }
    }
    private func saveProfile() {
        do { try store?.write(profile) } catch { failure = "Unable to save TAK preferences" }
    }
    #if DEBUG
    func seedMapPreview() {
        profile.host = "127.0.0.1"; profile.title = "Local rendering preview"
        status = "Rendering preview · no server connection"
        let now = Date()
        let events = [
            try? TAKCoT.marker(uid: "preview-wp", name: "ANDROID OP CAFÉ", affiliation: "hostile", position: .init(lat: 35.1384, lon: -78.9925), creatorUID: "preview", creatorCallsign: "PREVIEW", now: now),
            try? TAKCoT.drawing(uid: "preview-line", name: "ANDROID TEST LINE", points: [.init(lat: 35.1378, lon: -78.9930), .init(lat: 35.1380, lon: -78.9920), .init(lat: 35.1376, lon: -78.9912)], closed: false, creatorUID: "preview", creatorCallsign: "PREVIEW", now: now)
        ]
        for xml in events.compactMap({ $0 }) {
            if let event = TAKCoT.parse(xml, ownUID: profile.uid, now: now) { scene.apply(event, now: now, uptime: ProcessInfo.processInfo.systemUptime) }
        }
        remoteItems = scene.items
    }
    func enableLocalValidation() {
        guard profile.host == "127.0.0.1", profile.port == 8089, profile.tls else { return }
        synthetic = .init(lat: 35.1388, lon: -78.9914)
        updateLocationDemand()
    }
    #endif
}
