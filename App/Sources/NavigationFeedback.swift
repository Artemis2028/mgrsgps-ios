import CoreHaptics
import SwiftUI
import GridFixCore
import UserNotifications

@MainActor
protocol NavigationFeedback: AnyObject {
    var status: String { get }
    func prepare() async
    func begin()
    func emit(_ pulse: NavigationPulse,name: String)
    func cancelPlayback()
    func stop()
}

@MainActor
final class SystemNavigationFeedback: NavigationFeedback {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var session: UUID?
    private let center = UNUserNotificationCenter.current()
    private(set) var status = ""
    func prepare() async {
        if (await center.notificationSettings()).authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert,.sound])
        }
        let permitted = (await center.notificationSettings()).authorizationStatus == .authorized
        status = CHHapticEngine.capabilitiesForHardware().supportsHaptics ? "Steering patterns work while open. " : "Distinct steering haptics unavailable on this device. "
        status += permitted ? "Background route milestones and lane crossings use iOS notifications; settings and Focus apply." : "Notifications are off; background route milestones and lane crossings will be silent."
    }
    func begin() { session = UUID() }
    func emit(_ pulse: NavigationPulse,name: String) {
        guard let token = session else { return }
        if UIApplication.shared.applicationState != .active {
            let laneEvent = pulse.isLaneCrossingEvent
            guard let title = pulse.backgroundNotificationTitle else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = name; content.sound = .default; content.interruptionLevel = .timeSensitive
            let id = "navigation-\(token.uuidString)"+(laneEvent ? "-lane" : pulse == .laneNotEntered ? "-lane-reminder" : "")
            Task {
                guard session == token else { return }
                do {
                    try await center.add(.init(identifier: id,content: content,trigger: nil))
                    if session != token { center.removePendingNotificationRequests(withIdentifiers: [id]); center.removeDeliveredNotifications(withIdentifiers: [id]) }
                } catch { status = "Navigation notification could not be submitted: \(error.localizedDescription)" }
            }
            return
        }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                let e = try CHHapticEngine(); e.playsHapticsOnly = true; e.isAutoShutdownEnabled = true
                e.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.engine = nil; self?.player = nil } }
                e.resetHandler = { [weak self] in Task { @MainActor in self?.engine = nil; self?.player = nil } }
                engine = e
            }
            try engine?.start(); try player?.stop(atTime: CHHapticTimeImmediate)
            let bursts: [(Double,Double)]
            switch pulse {
            case .right,.laneLeftCrossing: bursts = [(0,0.07),(0.16,0.07)]
            case .left,.laneRightCrossing: bursts = [(0,0.3)]
            case .laneOvershot,.laneBackstopCrossing: bursts = [(0,0.3),(0.5,0.3),(1,0.3)]
            case .laneNotEntered: bursts = [(0,0.3),(0.45,0.08),(0.68,0.3)]
            case .unavailable: bursts = [(0,0.12),(0.24,0.12),(0.48,0.12)]
            case .onCourse,.checkpoint,.laneReentered: bursts = [(0,0.05)]
            case .arrival,.complete: bursts = [(0,0.4),(0.6,0.4)]
            }
            let events = bursts.map { CHHapticEvent(eventType: .hapticContinuous,parameters: [.init(parameterID: .hapticIntensity,value: 1),.init(parameterID: .hapticSharpness,value: 0.5)],relativeTime: $0.0,duration: $0.1) }
            let pattern = try CHHapticPattern(events: events,parameters: [])
            player = try engine?.makePlayer(with: pattern); try player?.start(atTime: CHHapticTimeImmediate)
        } catch { status = "Steering haptics unavailable: \(error.localizedDescription). Use the visual guide." }
    }
    func cancelPlayback() { try? player?.stop(atTime: CHHapticTimeImmediate); player = nil }
    func stop() {
        cancelPlayback()
        if let session {
            let id = "navigation-\(session.uuidString)"
            center.removePendingNotificationRequests(withIdentifiers: [id,id+"-lane",id+"-lane-reminder"]); center.removeDeliveredNotifications(withIdentifiers: [id,id+"-lane",id+"-lane-reminder"])
        }
        session = nil
    }
}
