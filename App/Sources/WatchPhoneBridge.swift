import Combine
import GridFixCore
import WatchConnectivity

/// A complete application context coalesces offline edits, deletion and selection clearing.
@MainActor
final class WatchPhoneBridge: NSObject, WCSessionDelegate {
    private let store: WaypointStore
    private let settings: AppSettings
    private var subscriptions = Set<AnyCancellable>()
    private var session: WCSession?

    init(store: WaypointStore, settings: AppSettings) {
        self.store = store; self.settings = settings
        super.init()
        guard WCSession.isSupported() else { return }
        session = .default
        session?.delegate = self
        session?.activate()
        // objectWillChange fires before the new value: defer serialization until the next runloop.
        Publishers.Merge(store.objectWillChange.map { _ in () }, settings.objectWillChange.map { _ in () })
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
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
        try? session.updateApplicationContext([WatchSnapshot.contextKey: data])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish() }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
