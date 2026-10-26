import CoreLocation
import GridFixCore
import SwiftUI
import UserNotifications

@MainActor
protocol BoundaryAlerting: AnyObject {
    var status: String { get }
    func prepare() async
    func begin()
    func crossing(name: String)
    func stop()
}

/// Foreground: haptic only. Background/locked: a system notification, whose
/// sound/haptics and delivery remain controlled by the user's iOS settings.
@MainActor
final class BoundaryAlerts: BoundaryAlerting {
    private let center = UNUserNotificationCenter.current()
    private var session: UUID?
    private var identifiers = Set<String>()
    private(set) var status = "Locked-screen alerts need notification permission."
    func prepare() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { _ = try? await center.requestAuthorization(options: [.alert,.sound]) }
        let current = await center.notificationSettings()
        if current.authorizationStatus == .authorized {
            status = current.soundSetting == .enabled ? "Locked-screen alerts use your iOS sound and haptic settings; Focus may silence them." : "Notification sounds are off. Locked-screen buzzes may be silent."
        } else { status = "Notifications are not enabled. Buzzes work only while the app is open." }
    }
    func begin() { session = UUID() }
    func crossing(name: String) {
        guard let token = session else { return }
        if UIApplication.shared.applicationState == .active {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Boundary crossed"
        content.body = "You crossed outside \(name). Open GridFix to check your position."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let id = "boundary-\(token.uuidString)"
        identifiers.insert(id)
        Task {
            guard session == token else { return }
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                if session != token { center.removePendingNotificationRequests(withIdentifiers: [id]); center.removeDeliveredNotifications(withIdentifiers: [id]) }
            } catch { status = "The last locked-screen alert could not be delivered: \(error.localizedDescription)" }
        }
    }
    func stop() {
        session = nil
        center.removePendingNotificationRequests(withIdentifiers: Array(identifiers))
        center.removeDeliveredNotifications(withIdentifiers: Array(identifiers))
        identifiers.removeAll()
    }
}

@MainActor
final class BoundaryMonitor: ObservableObject {
    struct Document: Codable, Sendable { var areas: [BoundaryArea] = []; var interruptedID: String? }
    @Published private(set) var areas: [BoundaryArea] = []
    @Published private(set) var activeID: String?
    @Published private(set) var preparing = false
    @Published private(set) var status = "Monitoring off"
    @Published private(set) var alertStatus = ""
    @Published private(set) var error: String?
    @Published private(set) var loadFailed = false
    @Published private(set) var crossingCount = 0
    @Published private(set) var lastFixAt: Date?
    @Published private(set) var hasFreshFix = false
    @Published private(set) var lastCrossing: Date?
    @Published var displayedID: String?
    private let file: URL
    private let driver: RecordingLocationDriver
    private let alerts: BoundaryAlerting
    private let now: () -> Date
    private let foreground: @MainActor () -> Bool
    private var detector: BoundaryCrossingDetector?
    private var pendingID: String?
    private var operation: Task<Void,Never>?
    private var generation = UUID()
    private var latestTimestamp: TimeInterval?
    var activeArea: BoundaryArea? { areas.first { $0.id == activeID } }
    var displayedArea: BoundaryArea? { areas.first { $0.id == (activeID ?? displayedID) } }
    var running: Bool { activeID != nil }

    struct PreparedStartup: Sendable {
        fileprivate let file: URL
        fileprivate let stamp: SourceStamp?
        fileprivate let document: Document?
        fileprivate let error: String?
        func validate() throws {
            guard SourceStamp.read(file) == stamp else { throw StartupFailure.changed }
        }
    }
    enum StartupFailure: LocalizedError {
        case changed
        var errorDescription: String? { "Saved boundaries changed while opening. Try again." }
    }
    fileprivate struct SourceStamp: Equatable, Sendable {
        let size: UInt64,inode: UInt64,volume: UInt64
        let modified: Date?
        static func read(_ file: URL) -> Self? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { return nil }
            return .init(size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                         inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                         volume: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                         modified: attributes[.modificationDate] as? Date)
        }
    }
    nonisolated static func prepareStartup(directory: URL? = nil) -> PreparedStartup {
        let file = (directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!).appendingPathComponent("boundaries-v1.json")
        let stamp = SourceStamp.read(file)
        guard FileManager.default.fileExists(atPath: file.path) else { return .init(file: file,stamp: stamp,document: nil,error: nil) }
        do {
            guard stamp.map({ $0.size <= 2 * 1024 * 1024 }) ?? true else { throw BoundaryError.invalid("Boundary library is too large.") }
            let data = try Data(contentsOf: file,options: .mappedIfSafe)
            guard data.count <= 2 * 1024 * 1024 else { throw BoundaryError.invalid("Boundary library is too large.") }
            let doc = try JSONDecoder().decode(Document.self,from: data)
            guard doc.areas.count <= 100,Set(doc.areas.map(\.id)).count == doc.areas.count else { throw BoundaryError.invalid("Invalid boundary library.") }
            for area in doc.areas { try Task.checkCancellation(); _ = try BoundaryGeometry(vertices: area.vertices) }
            return .init(file: file,stamp: stamp,document: doc,error: nil)
        } catch { return .init(file: file,stamp: stamp,document: nil,error: "Boundary files were kept: \(error.localizedDescription)") }
    }

    init(directory: URL? = nil,startup: PreparedStartup? = nil, driver: RecordingLocationDriver? = nil, alerts: BoundaryAlerting? = nil,
         now: @escaping () -> Date = Date.init, foreground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!
        file = dir.appendingPathComponent("boundaries-v1.json")
        self.driver = driver ?? CoreLocationRecordingDriver()
        self.alerts = alerts ?? BoundaryAlerts(); self.now = now; self.foreground = foreground
        let prepared = startup ?? Self.prepareStartup(directory: directory)
        do {
            guard prepared.file == file else { throw BoundaryError.invalid("Prepared boundaries belong to another library.") }
            try prepared.validate()
            if let failure = prepared.error { loadFailed = true; error = failure }
            else if let doc = prepared.document {
                areas = doc.areas; displayedID = areas.first?.id
                if doc.interruptedID != nil { status = "Monitoring was interrupted. Open a saved boundary and start again." }
            }
        } catch { loadFailed = true; self.error = "Boundary files were kept: \(error.localizedDescription)" }
        self.driver.onLocations = { [weak self] in self?.receive($0) }
        self.driver.onAuthorization = { [weak self] in self?.authorizationChanged() }
        self.driver.onFailure = { [weak self] in
            guard let self, self.running else { return }
            if ($0 as? CLError)?.code == .denied { self.stop(); self.error = "Monitoring stopped: precise location permission is unavailable." }
            else { self.status = "Location unavailable · boundary crossings cannot be checked"; self.lastFixAt = nil }
        }
    }
    @discardableResult func save(_ area: BoundaryArea) -> Bool {
        guard !running, !preparing, !loadFailed else { return false }
        do {
            _ = try BoundaryGeometry(vertices: area.vertices)
            let name = area.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 100 else { throw BoundaryError.invalid("Give the boundary a name of 1–100 characters.") }
            var next = areas
            let saved = BoundaryArea(id: area.id,name: name,vertices: area.vertices)
            if let i = next.firstIndex(where: { $0.id == area.id }) { next[i] = saved } else { next.append(saved) }
            guard next.count <= 100 else { throw BoundaryError.invalid("The boundary library is full. Delete a boundary first.") }
            try persist(next,active: nil); areas = next; displayedID = area.id; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func delete(_ area: BoundaryArea) {
        guard !running, !preparing, !loadFailed else { return }
        do { let next = areas.filter { $0.id != area.id }; try persist(next,active: nil); areas = next; if displayedID == area.id { displayedID = next.first?.id }; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func start(_ area: BoundaryArea) {
        guard !running, !preparing, !loadFailed, areas.contains(area), foreground() else { return }
        error = nil
        guard driver.servicesEnabled, driver.authorization != .denied, driver.authorization != .restricted else { error = "Enable location permission to monitor a boundary."; return }
        if driver.authorization == .notDetermined { pendingID = area.id; preparing = true; driver.requestPermission(); return }
        guard hasPermission else { error = "Boundary monitoring needs Precise Location. Enable it in Settings."; return }
        preparing = true; generation = UUID(); let token = generation
        operation = Task {
            await alerts.prepare()
            await waitForPermissionForeground(foreground)
            guard generation == token else { return }
            guard !Task.isCancelled, foreground(), hasPermission else {
                preparing = false; error = "Start monitoring with the app open and Precise Location enabled."; return
            }
            do {
                let detector = try BoundaryCrossingDetector(vertices: area.vertices)
                try persist(areas,active: area.id)
                self.detector = detector; activeID = area.id; displayedID = area.id; preparing = false
                crossingCount = 0; lastFixAt = nil; hasFreshFix = false; latestTimestamp = nil; lastCrossing = nil
                alertStatus = alerts.status; status = "Waiting for an accurate fix inside the boundary"
                alerts.begin(); driver.start()
            } catch { preparing = false; self.error = error.localizedDescription }
        }
    }
    func stop() {
        generation = UUID(); operation?.cancel(); pendingID = nil; preparing = false
        driver.stop(); alerts.stop(); activeID = nil; detector = nil; lastFixAt = nil; hasFreshFix = false
        status = "Monitoring off"
        do { if !loadFailed { try persist(areas,active: nil) } } catch { self.error = "Monitoring stopped; status could not be saved: \(error.localizedDescription)" }
    }
    func becameActive() {
        refresh()
        guard running else { return }
        let token = generation
        Task {
            await alerts.prepare()
            guard generation == token, running else { return }
            alertStatus = alerts.status
        }
    }
    func clearError() { if !loadFailed { error = nil } }
    func refresh() {
        if running, !hasPermission { stop(); error = "Monitoring stopped because precise location permission changed." }
        let fresh = lastFixAt.map { (-1...10).contains(now().timeIntervalSince($0)) } ?? false
        if hasFreshFix != fresh { hasFreshFix = fresh }
        if running, alertStatus != alerts.status { alertStatus = alerts.status }
    }
    private var hasPermission: Bool { (driver.authorization == .authorizedWhenInUse || driver.authorization == .authorizedAlways) && driver.precise && driver.servicesEnabled }
    private func authorizationChanged() {
        if let id = pendingID, driver.authorization != .notDetermined {
            pendingID = nil; preparing = false
            if let area = areas.first(where: { $0.id == id }) { start(area) }
        } else if running, !hasPermission { stop(); error = "Monitoring stopped because precise location permission changed." }
    }
    private func receive(_ locations: [CLLocation]) {
        guard running, hasPermission else { refresh(); return }
        let time = now().timeIntervalSince1970
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let timestamp = location.timestamp.timeIntervalSince1970
            guard latestTimestamp.map({ timestamp > $0 }) ?? true else { continue }
            let point = GeoPoint(lat: location.coordinate.latitude,lon: location.coordinate.longitude)
            let result = detector?.update(point: point,accuracy: location.horizontalAccuracy,timestamp: timestamp,now: time) ?? .unknown
            if result != .unknown { latestTimestamp = timestamp; lastFixAt = location.timestamp }
            switch result {
            case .unknown: status = "Waiting for an accurate, fresh location"
            case .edge: status = "Near boundary · GPS uncertainty overlaps the line"
            case .confirming(.inside): status = "Confirming position inside"
            case .confirming(.outside): status = "Confirming position outside"
            case .inside: status = "Inside · quiet · crossing alerts armed"
            case .outside: status = "Outside · enter the boundary to re-arm"
            case .exited:
                crossingCount += 1; lastCrossing = location.timestamp
                status = "Boundary crossed · outside · enter to re-arm"
                alerts.crossing(name: activeArea?.name ?? "the boundary")
            }
        }
        alertStatus = alerts.status
        refresh()
    }
    private func persist(_ areas: [BoundaryArea], active: String?) throws {
        let data = try JSONEncoder().encode(Document(areas: areas,interruptedID: active))
        try data.write(to: file,options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}
