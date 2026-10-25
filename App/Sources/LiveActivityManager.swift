import ActivityKit
import Combine
import Foundation
import UIKit

struct FieldActivitySession: Equatable, Sendable {
    var id: String
    var kind: String
    var state: FieldActivityState
}
struct FieldActivityReference: Equatable { var id: String; var sessionID: String; var kind: String }
@MainActor protocol FieldActivityDriver {
    var authorized: Bool { get }
    var supported: Bool { get }
    func current() -> [FieldActivityReference]
    func start(_ session: FieldActivitySession) async throws -> Bool
    func update(_ activity: FieldActivityReference,state: FieldActivityState) async
    func end(_ activity: FieldActivityReference) async
}

@available(iOS 16.2, *)
@MainActor final class SystemFieldActivityDriver: FieldActivityDriver {
    var authorized: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var supported: Bool { true }
    func current() -> [FieldActivityReference] {
        Activity<FieldActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }.map {
            .init(id:$0.id,sessionID:$0.attributes.sessionID,kind:$0.attributes.kind)
        }
    }
    func start(_ session: FieldActivitySession) async throws -> Bool {
        guard authorized,UIApplication.shared.applicationState == .active else { return false }
        _ = try Activity<FieldActivityAttributes>.request(attributes:.init(sessionID:session.id,kind:session.kind),content:.init(state:session.state,staleDate:session.state.fixExpiresAt ?? Date().addingTimeInterval(15)),pushType:nil)
        return true
    }
    func update(_ activity: FieldActivityReference,state: FieldActivityState) async {
        guard let value=Activity<FieldActivityAttributes>.activities.first(where:{$0.id==activity.id}) else { return }
        await value.update(.init(state:state,staleDate:state.fixExpiresAt ?? Date().addingTimeInterval(15)))
    }
    func end(_ activity: FieldActivityReference) async {
        guard let value=Activity<FieldActivityAttributes>.activities.first(where:{$0.id==activity.id}) else { return }
        await value.end(nil,dismissalPolicy:.immediate)
    }
}
@MainActor private final class UnsupportedFieldActivityDriver: FieldActivityDriver {
    var authorized: Bool { false };var supported: Bool { false }
    func current()->[FieldActivityReference] { [] }
    func start(_ session:FieldActivitySession) async throws -> Bool { false }
    func update(_ activity:FieldActivityReference,state:FieldActivityState) async {}
    func end(_ activity:FieldActivityReference) async {}
}

/// Serial reconciliation handles opt-out/session changes while an ActivityKit
/// await is pending. Existing location services provide background callbacks.
@MainActor final class LiveActivityManager: ObservableObject {
    @Published private(set) var message = "Live Activities are off"
    @Published private(set) var activityCount = 0
    private let driver: FieldActivityDriver
    private let enabled: ()->Bool
    private let foreground: ()->Bool
    private let sessions: ()->[FieldActivitySession]
    private var subscriptions = Set<AnyCancellable>()
    private var revision = 0
    private var work: Task<Void,Never>?
    private var known: [String:FieldActivityReference] = [:]
    private var suppressed = Set<String>()
    private var last: [String:FieldActivityState] = [:]
    private var lastUpdate: [String:Date] = [:]
    init(driver: FieldActivityDriver,enabled:@escaping ()->Bool,foreground:@escaping ()->Bool,sessions:@escaping ()->[FieldActivitySession]) {
        self.driver=driver;self.enabled=enabled;self.foreground=foreground;self.sessions=sessions
    }
    convenience init(recorder:TrackRecorder,navigation:NavigationSession,settings:AppSettings) {
        let driver:FieldActivityDriver
        if #available(iOS 16.2, *) { driver=SystemFieldActivityDriver() } else { driver=UnsupportedFieldActivityDriver() }
        self.init(driver:driver,enabled:{settings.liveActivitiesEnabled},foreground:{UIApplication.shared.applicationState == .active},sessions:{
            [recorder.liveActivitySession(settings:settings),navigation.liveActivitySession()].compactMap{$0}
        })
        Publishers.MergeMany([recorder.objectWillChange.map{_ in ()}.eraseToAnyPublisher(),navigation.objectWillChange.map{_ in ()}.eraseToAnyPublisher(),settings.objectWillChange.map{_ in ()}.eraseToAnyPublisher()])
            .throttle(for:.seconds(1),scheduler:RunLoop.main,latest:true).sink { [weak self] in
                // objectWillChange precedes publication.
                Task { @MainActor [weak self] in self?.refresh() }
            }.store(in:&subscriptions)
        refresh()
    }
    func refresh() {
        revision+=1
        guard work==nil else { return }
        work=Task {
            while true { let token=revision;await reconcile();if token==revision { break } }
            work=nil
        }
    }
    func waitForUpdates() async { await work?.value }
    private func reconcile() async {
        defer { activityCount=driver.current().count }
        let desired=enabled() && driver.authorized ? sessions() : []
        let current=driver.current()
        let keys=Set(desired.map { $0.kind+":"+$0.id })
        suppressed.formIntersection(keys)
        known=known.filter { keys.contains($0.key+":"+$0.value.sessionID) }
        for (kind,reference) in known where !current.contains(reference) && keys.contains(kind+":"+reference.sessionID) {
            suppressed.insert(kind+":"+reference.sessionID)
        }
        var kept=Set<String>()
        for activity in current {
            guard let session=desired.first(where:{$0.id==activity.sessionID && $0.kind==activity.kind}),kept.insert(activity.kind).inserted else {
                await driver.end(activity);known[activity.kind]=nil;last[activity.id]=nil;lastUpdate[activity.id]=nil;continue
            }
            known[activity.kind]=activity
            let previous=last[activity.id]
            let urgent=previous?.title != session.state.title || previous?.status != session.state.status || previous?.night != session.state.night
            if previous != session.state && (urgent || Date().timeIntervalSince(lastUpdate[activity.id] ?? .distantPast)>=5) {
                await driver.update(activity,state:session.state);last[activity.id]=session.state;lastUpdate[activity.id]=Date()
            }
        }
        if foreground() {
            for session in desired where !kept.contains(session.kind) && !suppressed.contains(session.kind+":"+session.id) {
                do {
                    if try await driver.start(session) {
                        kept.insert(session.kind)
                        if let reference=driver.current().first(where:{$0.sessionID==session.id && $0.kind==session.kind}) { known[session.kind]=reference;last[reference.id]=session.state;lastUpdate[reference.id]=Date() }
                    }
                }
                catch { message="Live Activity unavailable: "+error.localizedDescription;return }
            }
        }
        message = !driver.supported ? "Live Activities require iOS 16.2 or later" : !enabled() ? "Live Activities are off" : !driver.authorized ? "Live Activities are disabled in iOS settings" : desired.isEmpty ? "Ready for your next recording or navigation session" : kept.isEmpty && !suppressed.isEmpty ? "Live Activity dismissed for this session" : kept.isEmpty ? "Open the app to start the Live Activity" : "Live session status on the Lock Screen"
    }
}
