import CoreLocation
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
private final class GuideTestDriver: NavigationLocationDriver {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var precise = true, servicesEnabled = true, hasCompass = true, updating = false
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var onHeading: ((NavigationHeading) -> Void)?
    func requestPermission() {}
    func start() { updating = true }
    func stop() { updating = false }
}
@MainActor
private final class GuideTestFeedback: NavigationFeedback {
    var status = "Test feedback"
    var pulses: [NavigationPulse] = []
    var active = false
    var begins = 0
    func prepare() async {}
    func begin() { active = true; begins += 1 }
    func emit(_ pulse: NavigationPulse,name: String) { if active { pulses.append(pulse) } }
    func cancelPlayback() {}
    func stop() { active = false }
}

@MainActor
final class NavigationIntegrationTests: XCTestCase {
    func testDeferredLibraryDoesNotStartGpsOrDiscardPausedRouteBeforeLoading() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let original = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,foreground: { true },scheduleTicks: false)
        let r = try route(field); original.follow(r); try await wait { original.running }
        original.pause(); try await wait { !original.saving }
        let saved = try Data(contentsOf: dir.appendingPathComponent("navigation-session-v1.json"))
        let delayed = FieldDataStore(directory: dir,loadImmediately: false), reopenedDriver = GuideTestDriver(), reopenedFeedback = GuideTestFeedback()
        let reopened = NavigationSession(directory: dir,store: store,field: delayed,settings: settings,driver: reopenedDriver,feedback: reopenedFeedback,foreground: { true },scheduleTicks: false)
        XCTAssertEqual(reopened.progress?.routeID,r.id)
        reopened.resume(); XCTAssertFalse(reopened.running); XCTAssertFalse(reopened.preparing)
        XCTAssertFalse(reopenedDriver.updating); XCTAssertEqual(reopenedFeedback.begins,0)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("navigation-session-v1.json")),saved)
        await delayed.load()
        reopened.resume(); try await wait { reopened.running }
        XCTAssertEqual(reopened.progress?.routeID,r.id); XCTAssertTrue(reopenedDriver.updating)
        reopened.stop(); try await wait { !reopened.saving }
    }
    private func lanePoint(_ x: Double,_ y: Double) -> GeoPoint { .init(lat: 35+y/111195,lon: -79+x/(111195*cos(35 * .pi/180))) }
    private func lane(_ target: String,scope: NavLane.Scope = .checkpoint) -> NavLane {
        .init(id: "lane",name: "Creek",left: .init(points: [lanePoint(-50,0),lanePoint(-50,500)]),right: .init(points: [lanePoint(50,0),lanePoint(50,500)]),backstop: .init(points: [lanePoint(-100,1600),lanePoint(100,1600)]),scope: scope,targetId: target,createdAt: 1)
    }
    func testWatchExportsConfirmedLaneDecisionAndCannotRefreshSuspendedOrExpiredGuide() async throws {
        let (directory,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let target = lanePoint(0,1000), waypoint = store.add(.init(name:"OBJ CAFÉ",lat:target.lat,lon:target.lon)); store.select(waypoint.id)
        let lanes = NavigationLaneStore(directory:directory)
        var value = lane(waypoint.id); value.left.label = "Creek bank"
        _ = try await lanes.save(value,graphics:[])
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory:directory,store:store,field:field,settings:settings,driver:driver,feedback:feedback,lanes:lanes,now:{ Date(timeIntervalSince1970:date) },uptime:{ up },foreground:{ true },scheduleTicks:false)
        func export() -> WatchGuideSnapshot { nav.watchGuideSnapshot(sourceID:"synthetic",revision:1) }
        XCTAssertFalse(export().active)
        nav.startGuide(); try await wait { nav.running }; XCTAssertTrue(export().active); XCTAssertFalse(export().available)
        func send(_ x: Double) { date += 1; up += 1; let p = lanePoint(x,100); driver.onLocations?([fix(p.lat,p.lon,date,accuracy:5)]) }
        send(0); XCTAssertEqual(export().laneState,"NOT_YET")
        send(0); XCTAssertEqual(export().laneState,"INSIDE"); XCTAssertTrue(export().available)
        up += 3; date += 3
        XCTAssertFalse(export().available,"Transport heartbeat must not extend a suspended owner loop")
        nav.tick(); XCTAssertTrue(export().available)
        send(-80); send(-80); XCTAssertEqual(export().laneState,"OUT_LEFT"); XCTAssertEqual(export().crossedLine,"Creek bank")
        up += 11; date += 11; nav.tick(); XCTAssertFalse(export().available); XCTAssertNil(export().laneState)
        nav.stop(); try await wait { !nav.saving }; XCTAssertFalse(export().active); XCTAssertNil(export().targetName); XCTAssertNil(export().laneName)
    }
    func testLaneIsSilentWithoutHeadingAndEmitsDistinctBackgroundCrossingEvents() async throws {
        let (directory,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let target = lanePoint(0,1000), waypoint = store.add(.init(name: "OBJ",lat: target.lat,lon: target.lon))
        store.select(waypoint.id)
        let lanes = NavigationLaneStore(directory: directory); _ = try await lanes.save(lane(waypoint.id),graphics: [])
        var date = 1000.0, up = 100.0, foreground = true
        let nav = NavigationSession(directory: directory,store: store,field: field,settings: settings,driver: driver,feedback: feedback,lanes: lanes,now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { foreground },scheduleTicks: false)
        nav.startGuide(); try await wait { nav.running }
        feedback.pulses.removeAll() // Initial no-position cue precedes the first fix.
        func send(_ x: Double,_ y: Double) { date += 1; up += 1; let p = lanePoint(x,y); driver.onLocations?([fix(p.lat,p.lon,date,accuracy: 5)]) }
        send(0,100); XCTAssertEqual(nav.laneDecision?.state,.notYet); XCTAssertTrue(feedback.pulses.isEmpty)
        send(0,101); XCTAssertEqual(nav.laneDecision?.state,.inside); XCTAssertEqual(feedback.pulses.last,.laneReentered)
        feedback.pulses.removeAll(); XCTAssertNil(nav.decision)
        XCTAssertTrue(feedback.pulses.isEmpty); XCTAssertTrue(nav.status.contains("silent"))
        let live=try XCTUnwrap(nav.liveActivitySession())
        XCTAssertNotNil(live.state.grid);XCTAssertTrue(live.state.hasFreshFix(at:Date(timeIntervalSince1970:date),uptime:up))
        foreground = false
        send(-80,100); nav.tick(); XCTAssertEqual(nav.laneDecision?.state,.inside)
        send(-80,110); XCTAssertEqual(nav.laneDecision?.state,.outLeft)
        XCTAssertEqual(feedback.pulses.last,.laneLeftCrossing)
        up += 3; date += 3; nav.tick(); XCTAssertEqual(feedback.pulses.last,.right)
        XCTAssertNil(feedback.pulses.last?.backgroundNotificationTitle)
        send(0,120); send(0,125); XCTAssertEqual(feedback.pulses.last,.laneReentered)
        XCTAssertEqual(nav.laneDecision?.state,.inside)
        up += 11; date += 11; nav.tick(); XCTAssertNil(nav.laneDecision)
        XCTAssertTrue(nav.status.contains("unavailable")); XCTAssertEqual(feedback.pulses.last,.unavailable)
        XCTAssertNil(nav.liveActivitySession()?.state.grid)
        nav.stop(); try await wait { !nav.saving };XCTAssertNil(nav.liveActivitySession())
    }
    func testLinkedLineMovementUpdatesGuidanceAndDeletionFallsBackToAzimuth() async throws {
        let (directory,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let target = lanePoint(0,1000), waypoint = store.add(.init(name: "OBJ",lat: target.lat,lon: target.lon)); store.select(waypoint.id)
        var value = lane(waypoint.id), graphic = Backup.Graphic(id: "limit",name: "Creek bank",type: "phase_line",points: value.left.points.map { .init(lat: $0.lat,lon: $0.lon) })
        try field.saveGraphic(graphic); value.left = .init(graphicId: graphic.id)
        let lanes = NavigationLaneStore(directory: directory); _ = try await lanes.save(value,graphics: field.document.graphics)
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory: directory,store: store,field: field,settings: settings,driver: driver,feedback: feedback,lanes: lanes,now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { true },scheduleTicks: false)
        nav.startGuide(); try await wait { nav.running }
        func send(_ x: Double) { date += 1; up += 1; let p = lanePoint(x,100); driver.onLocations?([fix(p.lat,p.lon,date,accuracy: 5)]) }
        send(0); send(0); send(-80); send(-80); XCTAssertEqual(nav.laneDecision?.state,.outLeft)
        graphic.points = [lanePoint(-150,0),lanePoint(-150,500)].map { .init(lat: $0.lat,lon: $0.lon) }
        try field.saveGraphic(graphic); send(-80); XCTAssertEqual(nav.laneDecision?.state,.inside,"Same-lane reshaping retains entered state")
        send(-80); XCTAssertEqual(nav.laneDecision?.state,.inside)
        try await lanes.setVisible(value.id,false); send(0)
        XCTAssertEqual(nav.lane?.visible,false); XCTAssertEqual(nav.laneDecision?.state,.inside)
        try field.deleteGraphic(graphic.id); nav.tick()
        XCTAssertNotNil(nav.laneProblem); XCTAssertNil(nav.laneDecision); XCTAssertEqual(nav.decision?.cue,.unavailable)
        driver.onHeading?(.init(magnetic: 0,accuracy: 5,timestamp: Date(timeIntervalSince1970: date)))
        XCTAssertEqual(nav.decision?.cue,.onBearing); nav.stop(); try await wait { !nav.saving }
    }
    func testRouteLaneStateSurvivesCheckpointAdvanceAndCheckpointLaneWins() async throws {
        let (directory,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let route = Backup.Graphic(id: "route",name: "Patrol",type: "route",points: [lanePoint(0,1000),lanePoint(0,1200),lanePoint(0,1400)].map { .init(lat: $0.lat,lon: $0.lon) })
        try field.saveGraphic(route)
        let lanes = NavigationLaneStore(directory: directory); _ = try await lanes.save(lane(route.id,scope: .route),graphics: [])
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory: directory,store: store,field: field,settings: settings,driver: driver,feedback: feedback,lanes: lanes,now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { true },scheduleTicks: false)
        nav.follow(route); try await wait { nav.running }
        for _ in 0..<2 { date += 1; up += 1; let p = lanePoint(0,100); driver.onLocations?([fix(p.lat,p.lon,date,accuracy: 5)]) }
        for _ in 0..<2 { date += 1; up += 1; let p = lanePoint(-80,100); driver.onLocations?([fix(p.lat,p.lon,date,accuracy: 5)]) }
        XCTAssertEqual(nav.laneDecision?.state,.outLeft)
        nav.movePoint(1); try await wait { !nav.saving }; nav.tick(); XCTAssertEqual(nav.laneDecision?.state,.outLeft)
        XCTAssertEqual(feedback.begins,1,"A route-lane checkpoint change must not cancel queued crossing notifications")
        let checkpoint = try XCTUnwrap(store.waypoints.first { $0.sourceRoutePointIndex == 1 })
        var cpLane = lane(checkpoint.id); cpLane.id = "checkpoint-lane"
        cpLane.left.points = [lanePoint(-150,0),lanePoint(-150,500)]
        _ = try await lanes.save(cpLane,graphics: [])
        nav.tick(); XCTAssertEqual(nav.lane?.id,cpLane.id); XCTAssertEqual(nav.laneDecision?.state,.notYet)
        date += 1;up += 1;let p=lanePoint(-80,100);driver.onLocations?([fix(p.lat,p.lon,date,accuracy:5)])
        XCTAssertEqual(nav.laneDecision?.state,.inside)
        nav.pause(); XCTAssertNil(nav.lane); XCTAssertNil(nav.laneDecision)
    }
    func testLaneWarningPreferencePersistsAndBacksUp() throws {
        let (directory,_,_,settings) = try setup()
        settings.laneWarningM = 50
        XCTAssertEqual(AppSettings(directory: directory).laneWarningM,50)
        let snapshot = settings.backupSettings
        XCTAssertEqual(snapshot.laneWarningM,50)
        settings.laneWarningM = 0; try settings.applyBackup(snapshot)
        XCTAssertEqual(settings.laneWarningM,50); XCTAssertEqual(AppSettings(directory: directory).laneWarningM,50)
    }

    func testLaneStartupReminderSwitchesAndCalmerLostPositionCadence() async throws {
        let (directory,store,field,settings)=try setup(),driver=GuideTestDriver(),feedback=GuideTestFeedback()
        let p=lanePoint(0,1000),wp=store.add(.init(name:"OBJ",lat:p.lat,lon:p.lon));store.select(wp.id)
        let lanes=NavigationLaneStore(directory:directory);_=try await lanes.save(lane(wp.id),graphics:[])
        settings.laneReminderMin=2;settings.laneGpsAlert=false
        var date=1000.0,up=100.0
        var foreground=true
        let foregroundNav=NavigationSession(directory:directory,store:store,field:field,settings:settings,driver:driver,feedback:feedback,lanes:lanes,now:{Date(timeIntervalSince1970:date)},uptime:{up},foreground:{foreground},scheduleTicks:false)
        foregroundNav.startGuide();try await wait { foregroundNav.running }
        feedback.pulses.removeAll()
        func send(_ x:Double,_ y:Double,after:Double=1) {date+=after;up+=after;let p=lanePoint(x,y);driver.onLocations?([fix(p.lat,p.lon,date,accuracy:5)])}
        send(-80,100);send(-80,100,after:119)
        XCTAssertEqual(foregroundNav.laneDecision?.state,.notYet);XCTAssertTrue(feedback.pulses.isEmpty)
        foreground=false;send(-80,100)
        XCTAssertEqual(feedback.pulses.last,.laneNotEntered);XCTAssertNotNil(feedback.pulses.last?.backgroundNotificationTitle)
        settings.laneInsideTick=false;send(0,100);send(0,101)
        XCTAssertEqual(foregroundNav.laneDecision?.state,.inside)
        let before=feedback.pulses.count
        settings.laneSideCues=false;send(-80,100);send(-80,101)
        XCTAssertEqual(foregroundNav.laneDecision?.state,.outLeft);XCTAssertEqual(feedback.pulses.count,before)
        settings.laneSideCues=true;send(-80,102);XCTAssertEqual(feedback.pulses.last,.right)
        up+=11;date+=11;foregroundNav.tick();XCTAssertNotEqual(feedback.pulses.last,.unavailable)
        settings.laneGpsAlert=true;foregroundNav.tick();XCTAssertEqual(feedback.pulses.last,.unavailable)
        let lost=feedback.pulses.count
        up+=59;date+=59;foregroundNav.tick();XCTAssertEqual(feedback.pulses.count,lost)
        up+=1;date+=1;foregroundNav.tick();XCTAssertEqual(feedback.pulses.count,lost+1)
        foregroundNav.stop()
    }
    func testAllLaneCuePreferencesPersistAndRestoreWithoutChangingActivityConsent() throws {
        let (directory,_,_,settings)=try setup()
        settings.laneSideCues=false;settings.laneBackstopCue=false;settings.laneInsideTick=false
        settings.laneReminderMin=10;settings.laneGpsAlert=false;settings.liveActivitiesEnabled=true
        let saved=settings.backupSettings,reopened=AppSettings(directory:directory)
        XCTAssertEqual(reopened.backupSettings,saved)
        settings.laneReminderMin=0;settings.laneSideCues=true
        let prepared=try settings.restoreSnapshot().prepare(saved)
        XCTAssertTrue(try settings.publishRestore(prepared))
        XCTAssertEqual(settings.backupSettings,saved)
        XCTAssertEqual(AppSettings(directory:directory).backupSettings,saved)
        XCTAssertTrue(settings.liveActivitiesEnabled)
    }
    func testObjectiveChangeRevalidatesLaneAndSameLaneReshapingKeepsCrossingActive() async throws {
        let (directory,store,field,settings)=try setup(),driver=GuideTestDriver(),feedback=GuideTestFeedback()
        let objective=lanePoint(0,1000),wp=store.add(.init(name:"OBJ",lat:objective.lat,lon:objective.lon));store.select(wp.id)
        let lanes=NavigationLaneStore(directory:directory);var value=lane(wp.id)
        _=try await lanes.save(value,graphics:[],waypoints:store.waypoints)
        var date=1000.0,up=100.0
        let nav=NavigationSession(directory:directory,store:store,field:field,settings:settings,driver:driver,feedback:feedback,lanes:lanes,now:{Date(timeIntervalSince1970:date)},uptime:{up},foreground:{true},scheduleTicks:false)
        nav.startGuide();try await wait {nav.running}
        func send(_ x:Double) {date+=1;up+=1;let p=lanePoint(x,100);driver.onLocations?([fix(p.lat,p.lon,date,accuracy:5)])}
        send(0);send(0);send(-80);send(-80);XCTAssertEqual(nav.laneDecision?.state,.outLeft)
        let original=value;value.left.points=[lanePoint(-60,0),lanePoint(-60,500)]
        _=try await lanes.save(value,original:original,graphics:[],waypoints:store.waypoints)
        nav.tick();send(-80);XCTAssertEqual(nav.laneDecision?.state,.outLeft,"A reshaped entered lane must not wait silently for entry")
        let bad=lanePoint(0,1600);store.update(id:wp.id,draft:.init(name:"OBJ",lat:bad.lat,lon:bad.lon));nav.tick()
        XCTAssertTrue(nav.laneProblem?.contains("on the backstop") == true);XCTAssertNil(nav.laneDecision)
        nav.stop(); try await wait { !nav.saving }
    }

    func testPauseWhileCheckpointSaveIsBlockedCannotPublishLateProgressOrCue() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback(), gate = NavigationSaveGate()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false,stageSession: { try gate.prepare($0,$1) })
        nav.follow(try route(field)); try await wait { nav.running }
        gate.arm(); driver.onLocations?([fix(0,0,1000)])
        try await wait { gate.entered }
        XCTAssertTrue(nav.saving); XCTAssertEqual(nav.progress?.index,0); XCTAssertFalse(feedback.pulses.contains(.checkpoint))
        let watch = nav.watchGuideSnapshot(sourceID: UUID().uuidString,revision: 1)
        XCTAssertTrue(watch.active); XCTAssertFalse(watch.available); XCTAssertEqual(watch.status,"Saving navigation progress")
        XCTAssertEqual(nav.liveActivitySession()?.state.status,"Saving navigation progress")
        nav.pause(); XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating)
        gate.release(); try await wait { !nav.saving && gate.returned }
        XCTAssertEqual(nav.progress?.index,0); XCTAssertTrue(nav.progress?.paused == true)
        XCTAssertFalse(feedback.pulses.contains(.checkpoint))
        let reopened = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: GuideTestDriver(),feedback: GuideTestFeedback(),foreground: { true },scheduleTicks: false)
        XCTAssertEqual(reopened.progress?.index,0); XCTAssertFalse(reopened.running)
    }
    func testRouteEditWhileCheckpointSaveIsBlockedRejectsLateSession() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback(), gate = NavigationSaveGate()
        var route = try route(field)
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false,stageSession: { try gate.prepare($0,$1) })
        nav.follow(route); try await wait { nav.running }
        gate.arm(); driver.onLocations?([fix(0,0,1000)]); try await wait { gate.entered }
        route.points[1].lon += 0.001; try field.saveGraphic(route)
        gate.release(); try await wait { !nav.running && !nav.saving }
        XCTAssertEqual(nav.progress?.index,0); XCTAssertFalse(feedback.pulses.contains(.checkpoint)); XCTAssertNotNil(nav.error)
    }
    func testNewTargetDuringBlockedProgressSaveIsKeptAndPausesRoute() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback(), gate = NavigationSaveGate()
        let manual = store.add(.init(name: "New choice",lat: 24,lon: 54))
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false,stageSession: { try gate.prepare($0,$1) })
        nav.follow(try route(field)); try await wait { nav.running }
        gate.arm(); driver.onLocations?([fix(0,0,1000)]); try await wait { gate.entered }
        try store.selectDurably(manual.id)
        gate.release(); try await wait { !nav.running && !nav.saving }
        XCTAssertEqual(store.selectedId,manual.id); XCTAssertEqual(nav.progress?.index,0)
        XCTAssertFalse(feedback.pulses.contains(.checkpoint)); XCTAssertEqual(WaypointStore(directory: dir).selectedId,manual.id)
    }
    func testStopDuringBlockedCheckpointSaveDurablyClearsAndCannotReviveSession() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback(), gate = NavigationSaveGate()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false,stageSession: { try gate.prepare($0,$1) })
        nav.follow(try route(field)); try await wait { nav.running }
        gate.arm(); driver.onLocations?([fix(0,0,1000)]); try await wait { gate.entered }
        nav.stop(); XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating); XCTAssertNil(nav.progress)
        gate.release(); try await wait { !nav.saving && gate.returned }
        let reopened = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: GuideTestDriver(),feedback: GuideTestFeedback(),foreground: { true },scheduleTicks: false)
        XCTAssertNil(reopened.progress); XCTAssertFalse(reopened.running); XCTAssertFalse(feedback.pulses.contains(.checkpoint))
    }
    func testNewSelectionIntentDuringProgressSavePreventsCheckpointCueBeforeItCommits() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback(), gate = NavigationSaveGate()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false,stageSession: { try gate.prepare($0,$1) })
        nav.follow(try route(field)); try await wait { nav.running }
        gate.arm(); driver.onLocations?([fix(0,0,1000)]); try await wait { gate.entered }
        store.beginSelection() // A newer UI choice has begun but not published.
        gate.release(); try await wait { !nav.running && !nav.saving }
        XCTAssertEqual(nav.progress?.index,0); XCTAssertFalse(feedback.pulses.contains(.checkpoint))
    }
    func testRouteHapticPreferenceCommitsBeforeChangingAndRejectsChangedRoute() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback(), gate = NavigationSaveGate()
        var route = try route(field)
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,foreground: { true },scheduleTicks: false,stageSession: { try gate.prepare($0,$1) })
        nav.follow(route); try await wait { nav.running }; XCTAssertTrue(nav.haptics)
        gate.arm(); nav.setHaptics(false); try await wait { gate.entered }
        XCTAssertTrue(nav.haptics); XCTAssertTrue(nav.saving)
        route.points[1].lat += 0.001; try field.saveGraphic(route)
        gate.release(); try await wait { !nav.running && !nav.saving }
        XCTAssertTrue(nav.haptics,"A rejected preference must not publish its value")
        XCTAssertNotNil(nav.error); XCTAssertFalse(driver.updating)
    }
    func testClockChangeDuringPendingCheckpointDoesNotDiscardFreshQueuedFix() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), gate = NavigationSaveGate()
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { true },scheduleTicks: false,stageSession: { try gate.prepare($0,$1) })
        nav.follow(try route(field)); try await wait { nav.running }
        gate.arm(); driver.onLocations?([fix(0,0,date)]); try await wait { gate.entered }
        date = 400; up += 1
        driver.onLocations?([fix(0,0.001,date)])
        gate.release(); try await wait { !nav.saving }
        XCTAssertEqual(nav.progress?.index,2)
        nav.stop(); try await wait { !nav.saving }
    }
    func testPendingCheckpointKeepsNewestFixAndScoresEachTimestampOnce() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback(), gate = NavigationSaveGate()
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { true },scheduleTicks: false,stageSession: { try gate.prepare($0,$1) })
        nav.follow(try route(field)); try await wait { nav.running }
        gate.arm(); driver.onLocations?([fix(0,0,date)]); try await wait { gate.entered }
        date += 1; up += 1
        driver.onLocations?([fix(0,0.001,date)])
        driver.onLocations?([fix(0.001,0.001,date+100),fix(0.001,0.001,date,accuracy: 250)]) // Invalid fixes cannot replace a usable queued sample.
        driver.onLocations?([fix(0.001,0.001,date-1)]) // Older fix cannot replace the queued sample.
        XCTAssertEqual(nav.progress?.index,0); XCTAssertNil(nav.decision)
        gate.release(); try await wait { !nav.saving }
        XCTAssertEqual(nav.progress?.index,2); XCTAssertEqual(feedback.pulses.filter { $0 == .checkpoint }.count,2)
        driver.onLocations?([fix(0.001,0.001,date)]); XCTAssertEqual(nav.progress?.index,2)
        nav.stop(); try await wait { !nav.saving }
    }
    private func setup() throws -> (URL,WaypointStore,FieldDataStore,AppSettings) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let settings = AppSettings(directory: dir); settings.declinationOverride = 0; settings.guideHoldOffSec = 0; settings.guideHeartbeatSec = 0
        return (dir,WaypointStore(directory: dir),FieldDataStore(directory: dir),settings)
    }
    private func route(_ field: FieldDataStore) throws -> Backup.Graphic {
        let r = Backup.Graphic(id: UUID().uuidString,name: "Patrol",type: "route",points: [.init(lat: 0,lon: 0),.init(lat: 0,lon: 0.001),.init(lat: 0.001,lon: 0.001)],createdAt: 1)
        try field.saveGraphic(r); return r
    }
    private func fix(_ lat: Double,_ lon: Double,_ date: Double,accuracy: Double = 2) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat,longitude: lon),altitude: 0,horizontalAccuracy: accuracy,verticalAccuracy: -1,timestamp: Date(timeIntervalSince1970: date))
    }
    private func wait(_ p: () -> Bool) async throws {
        let end = Date().addingTimeInterval(5)
        while !p() && Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(p())
    }
    func testRouteAdvancesInOrderOncePerFreshFixAndCompletesInBackground() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        var date = 1000.0, up = 100.0, foreground = true
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { foreground },scheduleTicks: false)
        let r = try route(field); nav.follow(r); try await wait { nav.running }
        driver.onLocations?([fix(0,0,date)]); try await wait { !nav.saving }
        XCTAssertEqual(nav.progress?.index,1)
        driver.onLocations?([fix(0,0.001,date)]); try await wait { !nav.saving } // same timestamp cannot score another point
        XCTAssertEqual(nav.progress?.index,1)
        foreground = false; date += 1; up += 1
        driver.onLocations?([fix(0,0.001,date)]); try await wait { !nav.saving }
        XCTAssertEqual(nav.progress?.index,2); XCTAssertTrue(driver.updating)
        date += 1; up += 1; driver.onLocations?([fix(0.001,0.001,date)]); try await wait { !nav.saving }
        XCTAssertTrue(nav.progress?.complete == true); XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating)
        XCTAssertTrue(feedback.pulses.contains(.checkpoint)); XCTAssertEqual(feedback.pulses.last,.complete)
    }
    func testPauseResumeAndInterruptedRelaunchNeverStartGPSAutomatically() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        nav.pause(); XCTAssertFalse(driver.updating); XCTAssertTrue(nav.progress?.paused == true)
        nav.resume(); try await wait { nav.running }
        let other = GuideTestDriver()
        let reloaded = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: other,feedback: GuideTestFeedback(),foreground: { true },scheduleTicks: false)
        XCTAssertFalse(reloaded.running); XCTAssertFalse(other.updating); XCTAssertTrue(reloaded.progress?.paused == true)
        XCTAssertTrue(reloaded.status.contains("interrupted")); nav.stop()
    }
    func testHeadingFreshnessHoldDirectionAndPermissionLoss() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let wp = store.add(WaypointDraft(name: "East",lat: 0,lon: 0.01)); store.select(wp.id)
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { true },scheduleTicks: false)
        nav.startGuide(); try await wait { nav.running }
        driver.onHeading?(.init(magnetic: 105,accuracy: 5,timestamp: Date(timeIntervalSince1970: date)))
        driver.onLocations?([fix(0,0,date)]); try await wait { !nav.saving }
        XCTAssertEqual(nav.decision?.cue,.left); XCTAssertTrue(feedback.pulses.contains(.left))
        up += 3; date += 3; nav.tick()
        XCTAssertEqual(nav.decision?.cue,.unavailable)
        driver.precise = false; driver.onAuthorization?()
        XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating); XCTAssertNotNil(nav.error)
        driver.precise = true; nav.startGuide(); try await wait { nav.running }
        nav.setHaptics(false)
        XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating); XCTAssertFalse(feedback.active)
    }
    func testRouteChangeOrTargetRemovalStopsSafely() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),foreground: { true },scheduleTicks: false)
        var r = try route(field); nav.follow(r); try await wait { nav.running }
        r.points[1].lon += 0.001; try field.saveGraphic(r)
        try await wait { !nav.running }; XCTAssertTrue(nav.error?.contains("changed") == true)
        nav.follow(r); try await wait { nav.running }
        let future = try XCTUnwrap(store.waypoints.first { $0.sourceRouteId == r.id && $0.sourceRoutePointIndex == 2 })
        store.delete(ids: [future.id])
        try await wait { !nav.running }; XCTAssertNotNil(nav.error)
    }
    func testAccuracyAndStaleSamplesCannotAdvanceRoute() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        driver.onLocations?([fix(0,0,980),fix(0,0,1000,accuracy: 30)])
        XCTAssertEqual(nav.progress?.index,0)
        driver.onLocations?([fix(0,0,1000,accuracy: 2)]); try await wait { !nav.saving }
        XCTAssertEqual(nav.progress?.index,1); nav.stop()
    }
    func testSettingsPersistAndAndroidBackupApplyPreservesGuideFields() throws {
        let (dir,_,_,settings) = try setup()
        settings.guideAllowance = 20; settings.guideHoldOffSec = 3; settings.guideMode = 1; settings.guideCorridorM = 200
        let reloaded = AppSettings(directory: dir)
        XCTAssertEqual(reloaded.guideAllowance,20); XCTAssertEqual(reloaded.guideMode,1)
        var s = reloaded.backupSettings; s.guideHeartbeatSec = 60; s.guideAllowance = 15
        try reloaded.applyBackup(s)
        let final = AppSettings(directory: dir)
        XCTAssertEqual(final.guideHeartbeatSec,60); XCTAssertEqual(final.guideAllowance,15); XCTAssertEqual(final.guideCorridorM,200)
    }
    func testWallClockAdjustmentDoesNotBlockFreshRouteFixes() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        var date = 1000.0, up = 100.0
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),now: { Date(timeIntervalSince1970: date) },uptime: { up },foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        driver.onLocations?([fix(0,0,date)]); try await wait { !nav.saving }; XCTAssertEqual(nav.progress?.index,1)
        date = 400; up += 1
        driver.onLocations?([fix(0,0.001,date)]); try await wait { !nav.saving }; XCTAssertEqual(nav.progress?.index,2)
        nav.stop()
    }
    func testQuietBoundaryDetectionIsIndependentOfSteeringGuide() async throws {
        let (dir,store,field,settings) = try setup(), guideDriver = GuideTestDriver(), boundaryDriver = GuideTestDriver()
        let feedback = GuideTestFeedback(), boundaryAlerts = QuietBoundaryAlerts()
        let boundary = BoundaryMonitor(directory: dir,driver: boundaryDriver,alerts: boundaryAlerts,now: { Date(timeIntervalSince1970: 1002) },foreground: { true })
        let area = BoundaryArea(name: "Safe area",vertices: [.init(lat: -0.001,lon: -0.001),.init(lat: -0.001,lon: 0.001),.init(lat: 0.001,lon: 0.001),.init(lat: 0.001,lon: -0.001)])
        XCTAssertTrue(boundary.save(area)); boundary.start(area); try await wait { boundary.running }
        boundaryDriver.onLocations?([fix(0,0,1000),fix(0,0,1002)])
        let wp = store.add(WaypointDraft(name: "East",lat: 0,lon: 0.01)); store.select(wp.id)
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: guideDriver,feedback: feedback,now: { Date(timeIntervalSince1970: 1002) },uptime: { 100 },foreground: { true },scheduleTicks: false)
        nav.startGuide(); try await wait { nav.running }
        guideDriver.onHeading?(.init(magnetic: 105,accuracy: 5,timestamp: Date(timeIntervalSince1970: 1002)))
        guideDriver.onLocations?([fix(0,0,1002)])
        XCTAssertTrue(feedback.pulses.contains(.left)); XCTAssertEqual(boundaryAlerts.crossings,0)
        XCTAssertTrue(boundary.status.contains("quiet")); nav.stop(); XCTAssertTrue(boundaryDriver.updating)
        boundary.stop()
    }
    func testRouteWaypointWriteFailureKeepsTargetAndRetryStartsOnlyAfterDurableSave() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let target = store.add(.init(name: "Keep target",lat: 24,lon: 54)); store.select(target.id)
        let r = try route(field)
        let file = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,foreground: { true },scheduleTicks: false)
        nav.follow(r); try await wait { !nav.preparing && nav.error != nil }
        XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating); XCTAssertEqual(feedback.begins,0)
        XCTAssertEqual(store.waypoints,[target]); XCTAssertEqual(store.selectedId,target.id)
        try FileManager.default.removeItem(at: file)
        nav.follow(r); try await wait { nav.running }
        XCTAssertTrue(driver.updating); XCTAssertEqual(feedback.begins,1)
        XCTAssertEqual(WaypointStore(directory: dir).waypoints.filter { $0.sourceRouteId == r.id }.count,3)
        nav.stop()
    }
    func testCancelledRoutePermissionRequestCannotGeneratePointsOrStartAfterGrant() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        driver.authorization = .notDetermined
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); XCTAssertTrue(nav.preparing)
        nav.stop(); driver.authorization = .authorizedWhenInUse; driver.onAuthorization?()
        await Task.yield()
        XCTAssertFalse(nav.running); XCTAssertFalse(nav.preparing); XCTAssertFalse(driver.updating)
        XCTAssertTrue(store.waypoints.isEmpty); XCTAssertEqual(feedback.begins,0)
    }
    func testGuideSelectionWriteFailureNeverStartsGPSOrHapticsAndRetryWorks() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let target = store.add(.init(name: "Target",lat: 24,lon: 54)); try store.selectDurably(target.id)
        let file = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,foreground: { true },scheduleTicks: false)
        nav.startGuide(); try await wait { !nav.preparing && nav.error != nil }
        XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating); XCTAssertEqual(feedback.begins,0)
        XCTAssertEqual(store.selectedId,target.id)
        try FileManager.default.removeItem(at: file)
        nav.startGuide(); try await wait { nav.running }
        XCTAssertEqual(WaypointStore(directory: dir).selectedId,target.id); nav.stop()
    }
    func testCheckpointSelectionFailurePausesBeforeProgressOrCheckpointCue() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver(), feedback = GuideTestFeedback()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: feedback,now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        let target = store.selectedId, file = dir.appendingPathComponent("waypoints-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: false)
        driver.onLocations?([fix(0,0,1000)]); try await wait { !nav.saving }
        XCTAssertFalse(nav.running); XCTAssertFalse(driver.updating); XCTAssertEqual(nav.progress?.index,0)
        XCTAssertEqual(store.selectedId,target); XCTAssertFalse(feedback.pulses.contains(.checkpoint)); XCTAssertNotNil(nav.error)
        try FileManager.default.removeItem(at: file)
        nav.resume(); try await wait { nav.running }
        driver.onLocations?([fix(0,0,1000)]); try await wait { !nav.saving }
        XCTAssertEqual(nav.progress?.index,1); XCTAssertNotEqual(store.selectedId,target)
        XCTAssertEqual(WaypointStore(directory: dir).selectedId,store.selectedId); nav.stop()
    }
    func testFailedProgressWriteStopsAndRetainsUnscoredCheckpoint() async throws {
        let (dir,store,field,settings) = try setup(), driver = GuideTestDriver()
        let nav = NavigationSession(directory: dir,store: store,field: field,settings: settings,driver: driver,feedback: GuideTestFeedback(),now: { Date(timeIntervalSince1970: 1000) },uptime: { 100 },foreground: { true },scheduleTicks: false)
        nav.follow(try route(field)); try await wait { nav.running }
        let file = dir.appendingPathComponent("navigation-session-v1.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file,withIntermediateDirectories: true)
        driver.onLocations?([fix(0,0,1000)]); try await wait { !nav.saving }
        XCTAssertFalse(nav.running); XCTAssertEqual(nav.progress?.index,0); XCTAssertFalse(driver.updating); XCTAssertNotNil(nav.error)
        XCTAssertEqual(store.waypoints.first { $0.id == store.selectedId }?.sourceRoutePointIndex,1,"Target committed before the blocked session file")
        try FileManager.default.removeItem(at: file)
        nav.resume(); try await wait { nav.running }
        XCTAssertEqual(store.waypoints.first { $0.id == store.selectedId }?.sourceRoutePointIndex,0,"Resume restores the unscored leg")
        driver.onLocations?([fix(0,0,1000)]); try await wait { !nav.saving }
        XCTAssertEqual(nav.progress?.index,1)
        nav.stop(); try await wait { !nav.saving }
    }
}

@MainActor
private final class QuietBoundaryAlerts: BoundaryAlerting {
    let status = "Test alerts"
    var crossings = 0
    func prepare() async {}
    func begin() {}
    func crossing(name: String) { crossings += 1 }
    func stop() {}
}

/// Blocks one real worker file preparation. Main-actor callbacks remain live;
/// neither session progress nor file publication is injected by the gate.
private final class NavigationSaveGate: @unchecked Sendable {
    private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
    private var armed = false, didEnter = false, didReturn = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return didEnter }
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    func arm() { lock.lock(); armed = true; didEnter = false; didReturn = false; lock.unlock() }
    func release() { semaphore.signal() }
    func prepare(_ data: Data,_ destination: URL) throws -> PreparedAtomicFile {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); let block = armed; armed = false
        if block { didEnter = true }; lock.unlock()
        if block {
            guard semaphore.wait(timeout: .now()+5) == .success else { throw BoundaryError.invalid("Test save gate timed out") }
        }
        defer { if block { lock.lock(); didReturn = true; lock.unlock() } }
        return try PreparedAtomicFile(data: data,destination: destination,lockCompatible: true)
    }
}
